import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../core/utils/date_time_utils.dart';
import '../models/booking_models.dart';
import '../models/booking_settings.dart';
import '../models/org_service.dart';

class BookingApiService {
  BookingApiService({
    FirebaseFirestore? firestore,
    String? baseUrl,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _baseUrl = baseUrl ?? const String.fromEnvironment('BOOKING_API_BASE_URL');

  final FirebaseFirestore _firestore;
  final String _baseUrl;

  Future<List<BookingSlot>> fetchAvailability({
    required AvailabilityQuery query,
    required BookingSettings settings,
    required WorkingHours workingHours,
    required OrgService service,
  }) async {
    if (_baseUrl.isNotEmpty) {
      final uri = Uri.parse('$_baseUrl/booking/availability');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(query.toApiPayload()),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final rawSlots = (decoded['slots'] as List?) ?? const [];
        return rawSlots
            .whereType<Map>()
            .map((e) => BookingSlot.fromMap(Map<String, dynamic>.from(e)))
            .toList(growable: false);
      }

      throw Exception('Müsait saatler alınamadı (${response.statusCode}).');
    }

    return _fallbackAvailability(
      query: query,
      settings: settings,
      workingHours: workingHours,
      service: service,
    );
  }

  Future<String> createBooking(BookingDraft draft) async {
    if (_baseUrl.isEmpty) {
      throw Exception(
        'BOOKING_API_BASE_URL tanımı gerekli. Güvenli rezervasyon için backend endpoint kullanın.',
      );
    }

    final uri = Uri.parse('$_baseUrl/booking/create');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(draft.toApiPayload()),
    );

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300 && decoded['ok'] == true) {
      return decoded['bookingId'] as String;
    }

    throw Exception(decoded['error'] ?? 'Rezervasyon oluşturulamadı.');
  }

  Future<List<BookingSlot>> _fallbackAvailability({
    required AvailabilityQuery query,
    required BookingSettings settings,
    required WorkingHours workingHours,
    required OrgService service,
  }) async {
    final day = DateTimeUtils.stripTime(query.date);
    final weekday = day.weekday;
    final closedKey = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

    if (workingHours.closedDates.contains(closedKey)) {
      return const [];
    }

    final dayConfig = workingHours.days[weekday];
    if (dayConfig == null || !dayConfig.isOpen || dayConfig.windows.isEmpty) {
      return const [];
    }

    final now = DateTime.now();
    final minAllowed = now.add(Duration(hours: settings.minHoursBefore));
    final dayStart = DateTimeUtils.stripTime(day);
    if (!settings.allowSameDay && dayStart == DateTimeUtils.stripTime(now)) {
      return const [];
    }

    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final bookingsQuery = await _firestore
        .collection('bookings')
        .where('orgId', isEqualTo: query.orgId)
        .where('bookingDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('bookingDate', isLessThan: Timestamp.fromDate(endOfDay))
        .where('status', whereIn: ['pending', 'confirmed'])
        .get();

    final occupied = bookingsQuery.docs
        .map((doc) => doc.data())
        .map((data) => (
              start: (data['startTime'] as Timestamp).toDate(),
              end: (data['endTime'] as Timestamp).toDate(),
            ))
        .toList(growable: false);

    final slots = <BookingSlot>[];

    for (final window in dayConfig.windows) {
      final startParts = window.start.split(':');
      final endParts = window.end.split(':');
      if (startParts.length != 2 || endParts.length != 2) continue;

      var cursor = DateTime(
        day.year,
        day.month,
        day.day,
        int.parse(startParts[0]),
        int.parse(startParts[1]),
      );
      final windowEnd = DateTime(
        day.year,
        day.month,
        day.day,
        int.parse(endParts[0]),
        int.parse(endParts[1]),
      );

      while (cursor.add(Duration(minutes: service.durationMinutes)).isBefore(windowEnd) ||
          cursor.add(Duration(minutes: service.durationMinutes)).isAtSameMomentAs(windowEnd)) {
        final slotEnd = cursor.add(Duration(minutes: service.durationMinutes));

        final overlaps = occupied.any((item) {
          return cursor.isBefore(item.end) && slotEnd.isAfter(item.start);
        });

        if (!overlaps && !cursor.isBefore(minAllowed)) {
          slots.add(BookingSlot(start: cursor, end: slotEnd));
        }

        cursor = cursor.add(Duration(minutes: settings.slotMinutes));
      }
    }

    return slots;
  }
}
