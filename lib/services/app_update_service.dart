import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateStatus {
  AppUpdateStatus({
    required this.requiresUpdate,
    required this.forceUpdate,
    required this.currentVersion,
    required this.packageName,
    this.latestVersion,
    this.storeUrl,
    this.message,
  });

  final bool requiresUpdate;
  final bool forceUpdate;
  final String currentVersion;
  final String packageName;
  final String? latestVersion;
  final String? storeUrl;
  final String? message;

  bool get hasStoreUrl => storeUrl != null && storeUrl!.trim().isNotEmpty;
}

class AppUpdateService {
  /// Expects Firestore to contain a document at `app_config/versions` with either
  /// platform-specific maps:
  /// ```
  /// {
  ///   "android": {
  ///     "minVersion": "1.2.0",
  ///     "latestVersion": "1.3.0",
  ///     "storeUrl": "https://play.google.com/store/apps/details?id=com.example.app",
  ///     "message": "Önemli güvenlik düzeltmeleri içerir."
  ///   },
  ///   "ios": {
  ///     "minVersion": "1.2.0",
  ///     "latestVersion": "1.3.0",
  ///     "storeUrl": "https://apps.apple.com/app/id0000000000"
  ///   },
  ///   "message": "Varsayılan bilgi metni"
  /// }
  /// ```
  /// or flattened keys such as `androidMinVersion`, `iosStoreUrl`, etc.
  AppUpdateService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String _configCollection = 'app_config';
  static const String _versionsDoc = 'versions';

  Future<AppUpdateStatus?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final config = await _fetchConfig();
      if (config == null || config.isEmpty) {
        return null;
      }

      final platformData = _extractPlatformData(config);
      if (platformData == null || platformData.isEmpty) {
        return null;
      }

      final String currentVersion = packageInfo.version;
      final String packageName = packageInfo.packageName;

      final String? minVersion =
          _readString(platformData, 'minVersion') ?? _readString(platformData, 'minimumVersion');
      final String? latestVersion =
          _readString(platformData, 'latestVersion') ?? _readString(platformData, 'version');
      final String? storeUrl = _readString(platformData, 'storeUrl');
      final String? message = _readString(platformData, 'message') ?? _readString(config, 'message');

      bool forceUpdate = false;
      bool optionalUpdate = false;

      if (minVersion != null && minVersion.isNotEmpty) {
        if (_compareVersions(currentVersion, minVersion) < 0) {
          forceUpdate = true;
        }
      }

      if (!forceUpdate && latestVersion != null && latestVersion.isNotEmpty) {
        if (_compareVersions(currentVersion, latestVersion) < 0) {
          optionalUpdate = true;
        }
      }

      if (!forceUpdate && !optionalUpdate) {
        return AppUpdateStatus(
          requiresUpdate: false,
          forceUpdate: false,
          currentVersion: currentVersion,
          packageName: packageName,
          latestVersion: latestVersion ?? minVersion,
          storeUrl: storeUrl,
          message: message,
        );
      }

      return AppUpdateStatus(
        requiresUpdate: true,
        forceUpdate: forceUpdate,
        currentVersion: currentVersion,
        packageName: packageName,
        latestVersion: latestVersion ?? minVersion,
        storeUrl: storeUrl,
        message: message,
      );
    } catch (error) {
      print('AppUpdateService.checkForUpdate error: $error');
      return null;
    }
  }

  Future<bool> launchStore(AppUpdateStatus status) async {
    final url = await _resolveStoreUrl(status);
    if (url == null) {
      return false;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _fetchConfig() async {
    final snapshot = await _firestore.collection(_configCollection).doc(_versionsDoc).get();
    if (!snapshot.exists) {
      return null;
    }
    return snapshot.data();
  }

  Map<String, dynamic>? _extractPlatformData(Map<String, dynamic> raw) {
    final platformKey = Platform.isIOS ? 'ios' : 'android';
    final dynamic section = raw[platformKey];
    if (section is Map) {
      return section.map((key, value) => MapEntry(key.toString(), value));
    }

    final prefix = Platform.isIOS ? 'ios' : 'android';
    final candidates = <String, dynamic>{
      if (raw['${prefix}MinVersion'] != null) 'minVersion': raw['${prefix}MinVersion'],
      if (raw['${prefix}MinimumVersion'] != null)
        'minVersion': raw['${prefix}MinimumVersion'],
      if (raw['${prefix}LatestVersion'] != null)
        'latestVersion': raw['${prefix}LatestVersion'],
      if (raw['${prefix}Version'] != null) 'latestVersion': raw['${prefix}Version'],
      if (raw['${prefix}StoreUrl'] != null) 'storeUrl': raw['${prefix}StoreUrl'],
      if (raw['${prefix}Message'] != null) 'message': raw['${prefix}Message'],
    };

    return candidates.isEmpty ? null : candidates;
  }

  String? _readString(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return value.toString();
  }

  int _compareVersions(String a, String b) {
    final aParts = _normalizeVersion(a);
    final bParts = _normalizeVersion(b);
    final maxLength = aParts.length > bParts.length ? aParts.length : bParts.length;

    for (int i = 0; i < maxLength; i++) {
      final aPart = i < aParts.length ? aParts[i] : 0;
      final bPart = i < bParts.length ? bParts[i] : 0;
      if (aPart != bPart) {
        return aPart.compareTo(bPart);
      }
    }
    return 0;
  }

  List<int> _normalizeVersion(String input) {
    final cleaned = input.split('+').first;
    return cleaned
        .split('.')
        .map((segment) {
          final numeric = int.tryParse(segment.trim());
          return numeric ?? 0;
        })
        .take(4)
        .toList();
  }

  Future<String?> _resolveStoreUrl(AppUpdateStatus status) async {
    if (status.hasStoreUrl) {
      return status.storeUrl;
    }

    if (Platform.isAndroid) {
      return 'https://play.google.com/store/apps/details?id=${status.packageName}';
    }

    return null;
  }
}
