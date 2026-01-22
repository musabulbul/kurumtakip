const String _kSettingsKey = 'settings';
const String _kRestrictTcknKey = 'restrictTcknToManagers';
const String _kRoleKey = 'rol';
const String _kUpperManagementKey = 'ustyonetici';
const String _kImpersonatedKey = 'impersonated';
const String _kPermissionsKey = 'yetkiler';

const String kPermissionViewPrice = 'can_view_price';
const String kPermissionUpdatePrice = 'can_update_price';
const String kPermissionCreateReservation = 'can_create_reservation';
const String kPermissionUpdateReservation = 'can_update_reservation';
const String kPermissionTakePayment = 'can_take_payment';
const String kPermissionViewAllReservations = 'can_view_all_reservations';
const String kPermissionViewContactInfo = 'can_view_contact_info';
const String kPermissionSearchStudents = 'can_search_students';
const String kPermissionUpdateStudent = 'can_update_student';
const String kPermissionMakeSale = 'can_make_sale';

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

List<String> _readPermissions(dynamic source) {
  final map = _asMap(source);
  final raw = map[_kPermissionsKey];
  if (raw is Iterable) {
    return raw
        .map((item) => item?.toString().trim())
        .where((item) => item != null && item!.isNotEmpty)
        .cast<String>()
        .toList();
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return [raw.trim()];
  }
  return const [];
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

bool hasPermission(dynamic userData, String permissionKey) {
  if (permissionKey.trim().isEmpty) {
    return false;
  }
  if (isManagerUser(userData)) {
    return true;
  }
  final permissions = _readPermissions(userData)
      .map((permission) => permission.toLowerCase())
      .toSet();
  return permissions.contains(permissionKey.toLowerCase());
}

bool canViewPrice(dynamic userData) =>
    hasPermission(userData, kPermissionViewPrice) || canUpdatePrice(userData);

bool canUpdatePrice(dynamic userData) =>
    hasPermission(userData, kPermissionUpdatePrice);

bool canCreateReservation(dynamic userData) =>
    hasPermission(userData, kPermissionCreateReservation);

bool canUpdateReservation(dynamic userData) =>
    hasPermission(userData, kPermissionUpdateReservation);

bool canTakePayment(dynamic userData) =>
    hasPermission(userData, kPermissionTakePayment);

bool canViewAllReservations(dynamic userData) =>
    hasPermission(userData, kPermissionViewAllReservations);

bool canViewContactInfo(dynamic userData) =>
    hasPermission(userData, kPermissionViewContactInfo);

bool canSearchStudents(dynamic userData) =>
    hasPermission(userData, kPermissionSearchStudents);

bool canUpdateStudent(dynamic userData) =>
    hasPermission(userData, kPermissionUpdateStudent);

bool canMakeSale(dynamic userData) =>
    hasPermission(userData, kPermissionMakeSale);

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
