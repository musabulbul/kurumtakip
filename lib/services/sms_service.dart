import 'dart:convert';

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
  static const _endpoint = 'https://app.ilksms.com/api/ntonsms';

  static Future<SmsServiceResult> sendSms({
    required String apiUsername,
    required String apiPassword,
    required String baslik,
    required String tur,
    List<String>? phones,
    String? message,
    List<SmsMessagePayload>? personalizedMessages,
  }) async {
    final telMesajlar = <Map<String, String>>[];

    if (personalizedMessages != null && personalizedMessages.isNotEmpty) {
      for (final entry in personalizedMessages) {
        if (entry.phone.trim().isEmpty || entry.message.trim().isEmpty) {
          continue;
        }
        telMesajlar.add({'telefon': entry.phone.trim(), 'mesaj': entry.message});
      }
    } else if (phones != null && message != null) {
      telMesajlar.addAll(
        phones
            .where((phone) => phone.trim().isNotEmpty)
            .map((phone) => {'telefon': phone.trim(), 'mesaj': message}),
      );
    }

    if (telMesajlar.isEmpty) {
      return SmsServiceResult(
        success: false,
        message: 'Gönderilecek SMS bulunamadı.',
      );
    }

    final payload = {
      'apiUsername': apiUsername,
      'apiPassword': apiPassword,
      'baslik': baslik,
      'tur': tur,
      'telMesajlar': telMesajlar,
    };

    try {
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      Map<String, dynamic>? decoded;
      try {
        decoded = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        decoded = null;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return SmsServiceResult(
          success: true,
          message: 'SMS başarıyla gönderildi.',
          rawResponse: decoded,
        );
      }

      final errorMessage = decoded?['message']?.toString() ??
          'SMS gönderimi başarısız oldu (HTTP ${response.statusCode}).';
      print(errorMessage);
      return SmsServiceResult(
        success: false,
        message: errorMessage,
        rawResponse: decoded,
      );
    } catch (e) {
      print(e);
      return SmsServiceResult(
        success: false,
        message: 'SMS gönderilirken hata oluştu: $e',
        rawResponse: null,
      );
    }
  }
}
