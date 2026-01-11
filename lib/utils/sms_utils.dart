class SmsConfig {
  SmsConfig({
    required this.username,
    required this.password,
    required this.baslik,
    required this.tur,
  });

  final String username;
  final String password;
  final String baslik;
  final String tur;

  int get charLimit => tur.toLowerCase() == 'turkce' ? 155 : 160;
}

SmsConfig? buildSmsConfig(dynamic institutionData) {
  final normalized = _normalizeMap(institutionData);
  if (normalized == null) {
    return null;
  }

  final username = normalized['smsApiUsername']?.toString().trim() ?? '';
  final password = normalized['smsApiPassword']?.toString().trim() ?? '';
  final baslik = normalized['smsApiBaslik']?.toString().trim() ?? '';
  var tur = normalized['smsApiTur']?.toString().trim() ?? 'normal';

  if (username.isEmpty || password.isEmpty || baslik.isEmpty) {
    return null;
  }

  if (tur.isEmpty) {
    tur = 'normal';
  }

  return SmsConfig(
    username: username,
    password: password,
    baslik: baslik,
    tur: tur,
  );
}

bool canUserSendSms(
  dynamic userData,
  dynamic institutionData,
) {
  final userMap = _normalizeMap(userData);
  final role = (userMap?['rol'] ?? '').toString().toUpperCase();
  if (role != 'YÖNETİCİ') {
    return false;
  }

  return buildSmsConfig(institutionData) != null;
}

Map<String, dynamic>? _normalizeMap(dynamic source) {
  if (source == null) {
    return null;
  }

  if (source is Map) {
    final result = <String, dynamic>{};
    source.forEach((key, value) {
      if (key == null) {
        return;
      }
      result[key.toString()] = value;
    });
    return result;
  }

  return null;
}
