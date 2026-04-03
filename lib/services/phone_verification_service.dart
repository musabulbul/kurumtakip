import 'dart:convert';

import 'package:http/http.dart' as http;

abstract class PhoneVerificationService {
  Future<String> requestCode(String phone);

  Future<bool> verifyCode({
    required String verificationToken,
    required String smsCode,
  });
}

class BypassPhoneVerificationService implements PhoneVerificationService {
  @override
  Future<String> requestCode(String phone) async {
    return 'bypass-token';
  }

  @override
  Future<bool> verifyCode({
    required String verificationToken,
    required String smsCode,
  }) async {
    return true;
  }
}

/// Backend SMS servisi üzerinden OTP gönderir.
/// Backend `/sms/otp` endpoint'i kurumun kayıtlı SMS sağlayıcısını kullanarak
/// kodu gönderir ve üretilen kodu yanıtta döner.
class SmsOtpPhoneVerificationService implements PhoneVerificationService {
  SmsOtpPhoneVerificationService({
    required String orgId,
    required String orgName,
    String? baseUrl,
  })  : _orgId = orgId,
        _orgName = orgName,
        _baseUrl = (baseUrl ?? defaultBaseUrl).replaceAll(RegExp(r'/+$'), '');

  static const defaultBaseUrl = String.fromEnvironment(
    'SMS_SERVICE_URL',
    defaultValue: 'https://whatsapp-service-694457330631.europe-west1.run.app',
  );

  final String _orgId;
  final String _orgName;
  final String _baseUrl;

  @override
  Future<String> requestCode(String phone) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/sms/otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'kurum_id': _orgId,
        'phone': phone,
        'org_name': _orgName,
      }),
    );

    Map<String, dynamic> decoded = const {};
    try {
      final raw = jsonDecode(response.body);
      if (raw is Map<String, dynamic>) decoded = raw;
    } catch (_) {}

    if (response.statusCode >= 200 && response.statusCode < 300 && decoded['ok'] == true) {
      final code = (decoded['code'] as String?)?.trim() ?? '';
      if (code.isNotEmpty) return code;
    }

    final errCode = (decoded['error'] as String?)?.trim() ?? '';
    final msg = switch (errCode) {
      'sms_provider_missing' => 'SMS sağlayıcısı tanımlı değil.',
      'sms_provider_not_found' => 'SMS sağlayıcısı bulunamadı.',
      'sms_provider_failed' => 'SMS gönderilemedi. Lütfen tekrar deneyin.',
      _ => (decoded['message'] as String?)?.trim() ?? 'OTP kodu gönderilemedi.',
    };
    throw Exception(msg);
  }

  @override
  Future<bool> verifyCode({
    required String verificationToken,
    required String smsCode,
  }) async {
    return verificationToken.trim() == smsCode.trim();
  }
}
