import 'dart:convert';

import 'package:http/http.dart' as http;

class WhatsAppApi {
  WhatsAppApi({required this.baseUrl});

  final String baseUrl;

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
