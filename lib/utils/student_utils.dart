String? buildSinifSube(dynamic sinif, dynamic sube) {
  final classValue = (sinif ?? '').toString().trim();
  final branchValue = (sube ?? '').toString().trim().toUpperCase();

  if (classValue.isEmpty || branchValue.isEmpty) {
    return null;
  }

  const invalidTokens = {'-', '--'};
  if (invalidTokens.contains(classValue.toUpperCase()) ||
      invalidTokens.contains(branchValue)) {
    return null;
  }

  return '${classValue.toUpperCase()}$branchValue';
}

String _normalizeKeyPart(String? value) {
  if (value == null) {
    return '';
  }
  final sanitized = value
      .toString()
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'\s+'), ' ');
  return sanitized;
}

String buildStudentUniqueKey({
  required String institutionId,
  String? tckn,
  String? name,
  String? surname,
  String? number,
}) {
  final normalizedInstitution = _normalizeKeyPart(institutionId);
  final normalizedTckn = (tckn ?? '').trim();

  if (normalizedTckn.isNotEmpty) {
    return '$normalizedInstitution|TCKN|$normalizedTckn';
  }

  final normalizedNumber = _normalizeKeyPart(number);
  final normalizedName = _normalizeKeyPart(name);
  final normalizedSurname = _normalizeKeyPart(surname);

  return '$normalizedInstitution|COMPOSITE|$normalizedNumber|$normalizedName|$normalizedSurname';
}

String resolveStudentId(Map<dynamic, dynamic> data) {
  final idCandidates = [
    data['id'],
    data['studentId'],
    data['ogrenciid'],
    data['ogrenciId'],
    data['memberId'],
  ];

  for (final candidate in idCandidates) {
    if (candidate is String && candidate.trim().isNotEmpty) {
      return candidate.trim();
    }
  }

  final tckn = data['tckn'];
  if (tckn is String && tckn.trim().isNotEmpty) {
    return tckn.trim();
  }

  return '';
}
