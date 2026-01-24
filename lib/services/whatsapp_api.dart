import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

class WhatsAppApiException implements Exception {
  WhatsAppApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'WhatsAppApiException($statusCode): $body';
}

class WhatsAppApi {
  WhatsAppApi({String? baseUrl}) : baseUrl = (baseUrl ?? defaultBaseUrl).trim();

  static const String defaultBaseUrl =
      'https://whatsapp-service-694457330631.europe-west1.run.app';

  final String baseUrl;

  Future<void> sendMessage({
    required String recipient,
    required String message,
    String? kurumId,
  }) async {
    if (baseUrl.isEmpty) {
      throw Exception('WhatsApp servis adresi tanımlı değil.');
    }
    final uri = Uri.parse('$baseUrl/send-message');
    final payload = {
      'recipient': recipient,
      'message': message,
      if (kurumId != null && kurumId.trim().isNotEmpty) 'kurum_id': kurumId.trim(),
    };

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      debugPrint(
        '[WhatsAppApi] sendMessage failed status=${response.statusCode} body=${response.body}',
      );
      throw WhatsAppApiException(response.statusCode, response.body);
    }
    debugPrint('[WhatsAppApi] sendMessage success status=${response.statusCode}');
  }

  Future<String> requestPairingCode({
    required String phone,
    String? kurumId,
  }) async {
    if (baseUrl.isEmpty) {
      throw Exception('WhatsApp servis adresi tanımlı değil.');
    }
    final uri = Uri.parse('$baseUrl/get-code').replace(
      queryParameters: {
        'phone': phone,
        if (kurumId != null && kurumId.trim().isNotEmpty) 'kurum_id': kurumId.trim(),
      },
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      debugPrint(
        '[WhatsAppApi] requestPairingCode failed status=${response.statusCode} body=${response.body}',
      );
      throw WhatsAppApiException(response.statusCode, response.body);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final code = (decoded['code'] ?? '').toString().trim();
    if (code.isEmpty) {
      throw Exception('Pairing code alınamadı.');
    }
    debugPrint('[WhatsAppApi] requestPairingCode success');
    return code;
  }

  Future<void> sendExamResults({
    required List<Map<String, dynamic>> students,
    required bool parent1,
    required bool parent2,
    required bool student,
  }) async {
    final uri = Uri.parse('$baseUrl/send-results');
    final payload = {
      'students': students,
      'sendTo': {
        'parent1': parent1,
        'parent2': parent2,
        'student': student,
      },
    };

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception('Gönderim başarısız: ${response.statusCode} ${response.body}');
    }
  }

  Future<String?> fetchLatestQr() async {
    final uri = Uri.parse('$baseUrl/qr');
    final response = await http.get(uri);
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw Exception('QR alınamadı: ${response.statusCode} ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['qr'] as String?;
  }
}
