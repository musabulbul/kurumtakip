const String _kSettingsKey = 'settings';
const String _kRestrictTcknKey = 'restrictTcknToManagers';
const String _kRoleKey = 'rol';
const String _kUpperManagementKey = 'ustyonetici';
const String _kImpersonatedKey = 'impersonated';

bool _isTruthy(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return ['true', '1', 'yes', 'evet', 'on'].contains(normalized);
  }
  return false;
}

Map<dynamic, dynamic> _asMap(dynamic source) {
  if (source is Map) return source;
  return const {};
}

String _readString(dynamic source, String key) {
  final map = _asMap(source);
  final value = map[key];
  if (value == null) return '';
  return value.toString().trim();
}

bool isManagerUser(dynamic userData) {
  final map = _asMap(userData);
  final role = _readString(map, _kRoleKey).toUpperCase();
  final isImpersonated = _isTruthy(map[_kImpersonatedKey]);

  if (isImpersonated) {
    return role == 'YÖNETİCİ';
  }

  if (role == 'YÖNETİCİ') {
    return true;
  }

  final upperRole = _readString(map, _kUpperManagementKey).toUpperCase();
  return upperRole == 'ADMIN' || upperRole == 'YÖNETİCİ';
}

bool isTcknRestricted(dynamic institutionData) {
  final map = _asMap(institutionData);
  dynamic raw = map[_kRestrictTcknKey];

  if (raw == null) {
    final settings = _asMap(map[_kSettingsKey]);
    raw = settings[_kRestrictTcknKey];
  }

  return _isTruthy(raw);
}

bool canUserSeeTckn(dynamic userData, dynamic institutionData) {
  if (!isTcknRestricted(institutionData)) {
    return true;
  }
  return isManagerUser(userData);
}

bool isUserImpersonated(dynamic userData) {
  final map = _asMap(userData);
  return _isTruthy(map[_kImpersonatedKey]);
}
