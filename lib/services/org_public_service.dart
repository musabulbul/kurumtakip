import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/org_public_profile.dart';
import '../models/org_service.dart';

class OrgPublicService {
  OrgPublicService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const Map<String, int> _legacyDayToIndex = <String, int>{
    'mon': 1,
    'tue': 2,
    'wed': 3,
    'thu': 4,
    'fri': 5,
    'sat': 6,
    'sun': 7,
  };

  Future<OrgPublicProfile?> _getOrgFromAnyCollection(String orgId) async {
    final orgDoc = await _firestore.collection('orgs').doc(orgId).get();
    if (orgDoc.exists && orgDoc.data() != null) {
      return OrgPublicProfile.fromMap(orgDoc.id, _normalizeOrgMap(orgDoc.data()!));
    }

    final legacyDoc = await _firestore.collection('kurumlar').doc(orgId).get();
    if (legacyDoc.exists && legacyDoc.data() != null) {
      return OrgPublicProfile.fromMap(
        legacyDoc.id,
        _normalizeOrgMap(legacyDoc.data()!),
      );
    }

    return null;
  }

  Map<String, dynamic> _normalizeOrgMap(Map<String, dynamic> raw) {
    final rootSettings = raw['settings'] is Map
        ? Map<String, dynamic>.from(raw['settings'] as Map)
        : <String, dynamic>{};
    final onlineBookingSettings = rootSettings['onlineBooking'] is Map
        ? Map<String, dynamic>.from(rootSettings['onlineBooking'] as Map)
        : <String, dynamic>{};

    final settings = raw['bookingSettings'] is Map
        ? Map<String, dynamic>.from(raw['bookingSettings'] as Map)
        : onlineBookingSettings;
    settings['enabled'] = settings['enabled'] ?? (raw['bookingEnabled'] == true);
    settings['maxDaysAhead'] = settings['maxDaysAhead'] ?? 30;
    settings['minHoursBefore'] = settings['minHoursBefore'] ?? 2;
    settings['slotMinutes'] = settings['slotMinutes'] ?? 15;
    settings['allowSameDay'] = settings['allowSameDay'] ?? true;
    settings['weekendOpen'] = settings['weekendOpen'] ?? false;
    settings['authMode'] = settings['authMode'] ?? 'phone_birthdate';
    settings['showServicePrices'] = settings['showServicePrices'] ?? false;
    settings['showAccountStatement'] = settings['showAccountStatement'] ?? false;

    final workingHours = raw['workingHours'] is Map
        ? Map<String, dynamic>.from(raw['workingHours'] as Map)
        : (settings['workingHours'] is Map
            ? Map<String, dynamic>.from(settings['workingHours'] as Map)
            : <String, dynamic>{});
    final legacySessionHours = rootSettings['sessionHours'] is Map
        ? Map<String, dynamic>.from(rootSettings['sessionHours'] as Map)
        : <String, dynamic>{};
    if (workingHours.isEmpty && legacySessionHours.isNotEmpty) {
      workingHours.addAll(_legacySessionHoursToWorkingHours(legacySessionHours));
    }

    return {
      'name': raw['name'] ?? raw['kurumadi'] ?? '',
      'slug': raw['slug'] ?? '',
      'il': raw['il'],
      'district': raw['district'] ?? raw['ilce'],
      'phone': raw['phone'] ?? raw['ilgiliKisiTelefon'],
      'address': raw['address'] ?? raw['adres'],
      'logoUrl': raw['logoUrl'] ?? raw['logo'],
      'mapsLink': raw['mapsLink'],
      'latitude': raw['latitude'],
      'longitude': raw['longitude'],
      'bookingEnabled': raw['bookingEnabled'] == true || settings['enabled'] == true,
      'bookingSettings': settings,
      'workingHours': workingHours,
    };
  }

  Map<String, dynamic> _legacySessionHoursToWorkingHours(
    Map<String, dynamic> sessionHours,
  ) {
    final result = <String, dynamic>{};
    for (final entry in sessionHours.entries) {
      final dayIndex = _legacyDayToIndex[entry.key.toLowerCase().trim()];
      if (dayIndex == null) continue;
      final item = entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map)
          : <String, dynamic>{};
      final startMinutes = _toInt(item['startMinutes']);
      final endMinutes = _toInt(item['endMinutes']);
      if (startMinutes == null || endMinutes == null) continue;

      result['$dayIndex'] = {
        'isOpen': true,
        'windows': [
          {
            'start': _minutesToTime(startMinutes),
            'end': _minutesToTime(endMinutes),
          }
        ],
      };
    }
    if (result.isNotEmpty) {
      result['closedDates'] = <String>[];
    }
    return result;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  String _minutesToTime(int minutes) {
    final safe = minutes.clamp(0, (24 * 60) - 1);
    final hh = (safe ~/ 60).toString().padLeft(2, '0');
    final mm = (safe % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<OrgPublicProfile?> findBySlug(String slug) async {
    final normalizedSlug = slug.trim().toLowerCase();
    if (normalizedSlug.isEmpty) return null;

    // Fast path: direct slug mapping with document id = slug.
    final mappingRef = _firestore.collection('orgSlugs').doc(normalizedSlug);
    final mappingDoc = await mappingRef.get();
    if (mappingDoc.exists) {
      final mappingData = mappingDoc.data() ?? <String, dynamic>{};
      if (mappingData['active'] == false) return null;

      final orgId = (mappingData['orgId'] as String?)?.trim();
      if (orgId != null && orgId.isNotEmpty) {
        final profile = await _getOrgFromAnyCollection(orgId);
        if (profile != null) {
          return profile;
        }
      }
    }

    // Fallback: query slug in orgs first.
    final orgQuery = await _firestore
        .collection('orgs')
        .where('slug', isEqualTo: normalizedSlug)
        .limit(1)
        .get();
    if (orgQuery.docs.isNotEmpty) {
      final doc = orgQuery.docs.first;
      return OrgPublicProfile.fromMap(doc.id, _normalizeOrgMap(doc.data()));
    }

    // Legacy fallback: query slug field in kurumlar.
    final legacyQuery = await _firestore
        .collection('kurumlar')
        .where('slug', isEqualTo: normalizedSlug)
        .limit(1)
        .get();
    if (legacyQuery.docs.isEmpty) return null;
    final legacyDoc = legacyQuery.docs.first;
    return OrgPublicProfile.fromMap(
      legacyDoc.id,
      _normalizeOrgMap(legacyDoc.data()),
    );
  }

  Future<List<OrgService>> listActiveServices(String orgId) async {
    // Primary: try islemKategorileri (manual booking system with mekan support)
    final fromIslemler = await _listFromIslemKategorileri(orgId);
    if (fromIslemler.isNotEmpty) return fromIslemler;

    // Secondary: dedicated orgs/services subcollection
    final query = await _firestore
        .collection('orgs')
        .doc(orgId)
        .collection('services')
        .where('active', isEqualTo: true)
        .get();

    if (query.docs.isNotEmpty) {
      final items = query.docs
          .map((doc) => OrgService.fromMap(doc.id, doc.data()))
          .toList(growable: false);
      items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return items;
    }

    // Fallback: legacy kurumlar/services
    final legacyQuery = await _firestore
        .collection('kurumlar')
        .doc(orgId)
        .collection('services')
        .where('active', isEqualTo: true)
        .get();

    final legacyItems = legacyQuery.docs
        .map((doc) => OrgService.fromMap(doc.id, doc.data()))
        .toList(growable: false);
    legacyItems.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return legacyItems;
  }

  /// Reads active services from `kurumlar/{orgId}/islemKategorileri` hierarchy.
  /// Returns only operations where `onlineAktif == true`.
  Future<List<OrgService>> _listFromIslemKategorileri(String orgId) async {
    final categories = await _firestore
        .collection('kurumlar')
        .doc(orgId)
        .collection('islemKategorileri')
        .get();

    if (categories.docs.isEmpty) return const [];

    final results = <OrgService>[];
    for (final catDoc in categories.docs) {
      final catName = (catDoc.data()['adi'] as String?)?.trim() ?? catDoc.id;
      final ops = await catDoc.reference
          .collection('islemler')
          .where('onlineAktif', isEqualTo: true)
          .get();
      for (final opDoc in ops.docs) {
        final data = {
          ...opDoc.data(),
          'kategoriId': catDoc.id,
          'kategoriAdi': catName,
        };
        final service = OrgService.fromIslem(opDoc.id, orgId, data);
        if (service.name.isNotEmpty) {
          results.add(service);
        }
      }
    }

    results.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return results;
  }
}
