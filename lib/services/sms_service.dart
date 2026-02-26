import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SmsServiceResult {
  SmsServiceResult({required this.success, required this.message, this.rawResponse});

  final bool success;
  final String message;
  final Map<String, dynamic>? rawResponse;
}

class SmsMessagePayload {
  SmsMessagePayload({required this.phone, required this.message});

  final String phone;
  final String message;
}

class SmsService {
  SmsService({String? baseUrl}) : baseUrl = (baseUrl ?? defaultBaseUrl).trim();

  static const String defaultBaseUrl = String.fromEnvironment(
    'SMS_SERVICE_URL',
    defaultValue:
      'https://whatsapp-service-694457330631.europe-west1.run.app'
  );

  final String baseUrl;

  void _log(String message, [Object? details]) {
    final suffix = details == null ? '' : ' | $details';
    debugPrint('[sms_service] $message$suffix');
  }

  String _joinUrl(String path) {
    final cleanedBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final cleanedPath = path.replaceAll(RegExp(r'^/+'), '');
    return '$cleanedBase/$cleanedPath';
  }

  Map<String, dynamic>? _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'body': decoded.toString()};
    } catch (_) {
      return {'body': body};
    }
  }

  String _readErrorMessage(Map<String, dynamic>? decoded, int statusCode) {
    if (decoded == null) {
      return 'SMS işlemi başarısız oldu (HTTP $statusCode).';
    }
    final message = (decoded['message'] ?? '').toString().trim();
    if (message.isNotEmpty) return message;
    final error = (decoded['error'] ?? '').toString().trim();
    if (error.isNotEmpty) return error;
    return 'SMS işlemi başarısız oldu (HTTP $statusCode).';
  }

  Future<SmsServiceResult> sendSms({
    required String kurumId,
    List<String>? phones,
    String? message,
    List<SmsMessagePayload>? personalizedMessages,
    String? providerId,
    String? messageContentType,
    String? sendDate,
    String? expireDate,
  }) async {
    final payload = {
      'kurum_id': kurumId.trim(),
      if (message != null) 'message': message,
      if (phones != null) 'phones': phones,
      if (personalizedMessages != null)
        'personalized_messages': personalizedMessages
            .map((entry) => {'phone': entry.phone, 'message': entry.message})
            .toList(),
      if (providerId != null && providerId.trim().isNotEmpty)
        'provider_id': providerId.trim(),
      if (messageContentType != null && messageContentType.trim().isNotEmpty)
        'message_content_type': messageContentType.trim(),
      if (sendDate != null && sendDate.trim().isNotEmpty) 'send_date': sendDate.trim(),
      if (expireDate != null && expireDate.trim().isNotEmpty) 'expire_date': expireDate.trim(),
    };

    final url = _joinUrl('/sms/send');
    _log('sendSms request', {'url': url, 'payloadKeys': payload.keys.toList()});

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      final decoded = _decodeMap(response.body);
      _log('sendSms response', {'statusCode': response.statusCode, 'body': decoded});

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return SmsServiceResult(
          success: true,
          message: 'SMS başarıyla gönderildi.',
          rawResponse: decoded,
        );
      }

      return SmsServiceResult(
        success: false,
        message: _readErrorMessage(decoded, response.statusCode),
        rawResponse: decoded,
      );
    } catch (e, stackTrace) {
      _log('sendSms exception', e);
      _log('sendSms stackTrace', stackTrace);
      return SmsServiceResult(
        success: false,
        message: 'SMS gönderilirken hata oluştu: $e',
      );
    }
  }

  Future<SmsServiceResult> fetchUserInformation({
    required String kurumId,
    String? providerId,
  }) async {
    final payload = {
      'kurum_id': kurumId.trim(),
      if (providerId != null && providerId.trim().isNotEmpty)
        'provider_id': providerId.trim(),
    };

    final url = _joinUrl('/sms/user-info');
    _log('fetchUserInformation request', {'url': url, 'payload': payload});

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      final decoded = _decodeMap(response.body);
      _log('fetchUserInformation response', {
        'statusCode': response.statusCode,
        'body': decoded,
      });

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return SmsServiceResult(
          success: true,
          message: 'Kullanıcı bilgileri alındı.',
          rawResponse: decoded,
        );
      }

      return SmsServiceResult(
        success: false,
        message: _readErrorMessage(decoded, response.statusCode),
        rawResponse: decoded,
      );
    } catch (e, stackTrace) {
      _log('fetchUserInformation exception', e);
      _log('fetchUserInformation stackTrace', stackTrace);
      return SmsServiceResult(
        success: false,
        message: 'Kullanıcı bilgileri alınırken hata oluştu: $e',
      );
    }
  }
}
