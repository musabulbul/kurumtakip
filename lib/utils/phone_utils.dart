String normalizePhone(String? raw) {
  if (raw == null) {
    return '';
  }

  final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.isEmpty) {
    return '';
  }

  var normalized = digitsOnly;

  if (normalized.startsWith('00')) {
    normalized = normalized.substring(2);
  }

  if (normalized.startsWith('90')) {
    // already starts with country code
  } else if (normalized.startsWith('0')) {
    normalized = normalized.substring(1);
  }

  if (!normalized.startsWith('90')) {
    normalized = '90$normalized';
  }

  return '+$normalized';
}
