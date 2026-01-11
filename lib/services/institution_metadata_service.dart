import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';

class InstitutionMetadataService {
  InstitutionMetadataService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String _institutionsCollection = 'kurumlar';
  static const String _studentsCollection = 'danisanlar';

  Future<Map<String, dynamic>> refreshClassBranchSummary(String institutionId) async {
    if (institutionId.trim().isEmpty) {
      return const {};
    }

    final studentsSnapshot = await _firestore
        .collection(_institutionsCollection)
        .doc(institutionId)
        .collection(_studentsCollection)
        .get();

    final classes = SplayTreeSet<String>();
    final branches = SplayTreeSet<String>();
    final Map<String, SplayTreeSet<String>> classBranches = {};

    for (final doc in studentsSnapshot.docs) {
      final data = doc.data();
      final primary = _normalizeClassBranch(data['sinif'], data['sube']);
      final fallbackCombined = _normalizeClassBranch(data['sinifsube'], null);

      final classValue = primary.classValue ?? fallbackCombined.classValue;
      final branchValue = primary.branchValue ?? fallbackCombined.branchValue;

      if (classValue != null && classValue.isNotEmpty) {
        classes.add(classValue);
        if (branchValue != null && branchValue.isNotEmpty) {
          classBranches.putIfAbsent(classValue, () => SplayTreeSet<String>()).add(branchValue);
        }
      }

      if (branchValue != null && branchValue.isNotEmpty) {
        branches.add(branchValue);
      }
    }

    final sinifSubeler = <String>[];
    classBranches.forEach((sinif, subelerSet) {
      for (final sube in subelerSet) {
        sinifSubeler.add('$sinif$sube');
      }
    });

    final metadata = <String, dynamic>{
      'siniflar': classes.toList(),
      'subeler': branches.toList(),
      'sinifSubeHaritasi': classBranches.map(
        (key, value) => MapEntry(key, value.toList()),
      ),
      if (sinifSubeler.isNotEmpty) 'sinifSubeler': sinifSubeler,
      'metadataGuncellemeZamani': FieldValue.serverTimestamp(),
    };

    await _firestore.collection(_institutionsCollection).doc(institutionId).set(
          metadata,
          SetOptions(merge: true),
        );

    return metadata;
  }
}

class _ClassBranchPair {
  const _ClassBranchPair({this.classValue, this.branchValue});

  final String? classValue;
  final String? branchValue;
}

_ClassBranchPair _normalizeClassBranch(dynamic rawClass, dynamic rawBranch) {
  final classInput = _sanitizeClassInput(rawClass);
  String? branchValue = _normalizeBranchValue(rawBranch);
  String? classValue = _normalizeClassValue(classInput);

  if ((branchValue == null || branchValue.isEmpty) && classInput != null) {
    final extracted = _extractBranchFromClass(classInput);
    classValue = extracted.classValue ?? classValue;
    branchValue = extracted.branchValue ?? branchValue;
  }

  classValue = _normalizeClassValue(classValue);
  branchValue = _normalizeBranchValue(branchValue);

  return _ClassBranchPair(classValue: classValue, branchValue: branchValue);
}

String? _sanitizeClassInput(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  return raw.toUpperCase();
}

String? _normalizeClassValue(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;

  var cleaned = raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');
  cleaned = cleaned.replaceAll(RegExp(r'[-_]'), '');

  if (cleaned == 'SINIF') {
    return null;
  }

  final slashIndex = cleaned.indexOf('/');
  if (slashIndex != -1) {
    cleaned = cleaned.substring(0, slashIndex);
  }

  final match = RegExp(r'^(HAZIRLIK|HAZ\.?|\d{1,2})').firstMatch(cleaned);
  if (match != null) {
    final normalized = match.group(0)!;
    if (normalized.startsWith('HAZ')) {
      return 'HAZ.';
    }
    return normalized;
  }

  return cleaned;
}

String? _normalizeBranchValue(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;

  final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-ZÇĞİÖŞÜ0-9]'), '');
  if (cleaned.isEmpty || cleaned == 'ŞUBE') {
    return null;
  }
  return cleaned;
}

_ClassBranchPair _extractBranchFromClass(String classValue) {
  var cleaned = classValue.toUpperCase();
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), '');

  if (cleaned.contains('/')) {
    final parts = cleaned.split('/');
    final classPart = _normalizeClassValue(parts.isNotEmpty ? parts.first : null);
    final branchPart = _normalizeBranchValue(parts.length > 1 ? parts[1] : null);
    return _ClassBranchPair(classValue: classPart, branchValue: branchPart);
  }

  final match = RegExp(r'^(HAZIRLIK|HAZ\.?|\d{1,2})([A-ZÇĞİÖŞÜ]{1,2})$').firstMatch(cleaned);
  if (match != null) {
    final classPart = _normalizeClassValue(match.group(1));
    final branchPart = _normalizeBranchValue(match.group(2));
    return _ClassBranchPair(classValue: classPart, branchValue: branchPart);
  }

  return _ClassBranchPair(classValue: cleaned, branchValue: null);
}
