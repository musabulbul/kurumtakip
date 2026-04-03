import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/utils/date_time_utils.dart';
import '../models/booking_models.dart';
import '../models/booking_settings.dart';
import '../models/org_service.dart';
import 'notification_service.dart';

class BookingApiService {
  BookingApiService({
    FirebaseFirestore? firestore,
    String? baseUrl,
    String? notifUrl,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _baseUrl = baseUrl ?? const String.fromEnvironment('BOOKING_API_BASE_URL'),
        _notifUrl = notifUrl ?? const String.fromEnvironment('NOTIFICATION_URL');

  final FirebaseFirestore _firestore;
  final String _baseUrl;
  /// Backend bildirim servisi URL'i (NOTIFICATION_URL dart-define ile verilir).
  final String _notifUrl;

  void _log(String message, [Map<String, Object?> data = const {}]) {
    if (data.isEmpty) {
      debugPrint('[BookingApi] $message');
      return;
    }
    final details = data.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' | ');
    debugPrint('[BookingApi] $message | $details');
  }

  // Session-level cache: key = "{orgId}_{serviceId}_{yyyy-MM-dd}"
  final Map<String, List<BookingSlot>> _cache = {};

  /// Rezervasyon oluşturulduktan sonra ilgili günün cache'ini temizler.
  void invalidateCacheForDate(String orgId, DateTime date) {
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    _cache.removeWhere((key, _) => key.startsWith('${orgId}_') && key.endsWith('_$dateStr'));
  }

  Future<List<BookingSlot>> fetchAvailability({
    required AvailabilityQuery query,
    required BookingSettings settings,
    required WorkingHours workingHours,
    required OrgService service,
  }) async {
    if (_baseUrl.isNotEmpty) {
      try {
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
      } catch (_) {
        // Backend unavailable — use local Firestore fallback.
      }
    }

    return _fallbackAvailability(
      query: query,
      settings: settings,
      workingHours: workingHours,
      service: service,
    );
  }

  Future<String> createBooking(BookingDraft draft) async {
    if (_baseUrl.isNotEmpty) {
      Exception? userFacingError;
      String? backendBookingId;

      try {
        final uri = Uri.parse('$_baseUrl/booking/create');
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(draft.toApiPayload()),
        );

        Map<String, dynamic> decoded = const <String, dynamic>{};
        try {
          final raw = jsonDecode(response.body);
          if (raw is Map<String, dynamic>) decoded = raw;
        } catch (_) {}

        if (response.statusCode >= 200 && response.statusCode < 300 && decoded['ok'] == true) {
          backendBookingId = decoded['bookingId'] as String;
        } else {
          // Map known business-logic error codes to user messages.
          final code = (decoded['error'] as String?)?.trim() ?? '';
          userFacingError = switch (code) {
            'slot_not_available' =>
              Exception('Seçtiğiniz saat artık uygun değil. Lütfen farklı bir saat seçin.'),
            'too_close_to_now' =>
              Exception('Bu saat için minimum bekleme süresi kuralı nedeniyle rezervasyon alınamıyor.'),
            'too_far_in_future' =>
              Exception('Seçilen tarih kurumun izin verdiği aralığın dışında.'),
            'booking_closed' => Exception('Online rezervasyon şu anda kapalı.'),
            'org_not_found'  => Exception('Kurum bilgisi bulunamadı.'),
            'invalid_request' => Exception('Rezervasyon bilgileri eksik veya hatalı.'),
            // Infrastructure / credential failures → null → fall through to Firestore.
            _ => null,
          };
        }
      } catch (_) {
        // Network error or unexpected exception → fall through to Firestore fallback.
      }

      if (backendBookingId != null) {
        // Backend rezervasyonu oluşturduğunda da uygulama içi bildirimleri
        // Firestore'a yazmaya devam et. Böylece bildirim çanı backend'e
        // bağımlı kalmaz.
        _notifyReservationAudienceViaFirestore(
          draft: draft,
          bookingId: backendBookingId,
        ).ignore();
        return backendBookingId;
      }
      if (userFacingError != null) throw userFacingError;
    }

    // Firestore fallback: write directly to the bookings collection.
    return _fallbackCreateBooking(draft);
  }

  Future<String> _fallbackCreateBooking(BookingDraft draft) async {
    // Look up mekan name if mekanId is provided (needed for display in rezervasyonlar).
    String? mekanName;
    if (draft.mekanId != null && draft.mekanId!.isNotEmpty && draft.orgId.isNotEmpty) {
      try {
        final mekanDoc = await _firestore
            .collection('kurumlar')
            .doc(draft.orgId)
            .collection('mekanlar')
            .doc(draft.mekanId)
            .get();
        if (mekanDoc.exists) {
          mekanName = (mekanDoc.data()?['adi'] as String?)?.trim();
        }
      } catch (_) {}
    }

    final startMinutes = draft.startTime.hour * 60 + draft.startTime.minute;
    final endMinutes = draft.endTime.hour * 60 + draft.endTime.minute;
    final shortName = _buildShortName(draft.customerName);
    final now = FieldValue.serverTimestamp();

    final rezervasyonDoc = _firestore
        .collection('kurumlar')
        .doc(draft.orgId)
        .collection('rezervasyonlar')
        .doc();

    await rezervasyonDoc.set({
      'date': Timestamp.fromDate(draft.startTime),
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
      'customerId': draft.customerId,
      'customerName': draft.customerName,
      'customerShortName': shortName,
      'customerPhone': draft.customerPhone,
      'operationName': draft.serviceName,
      'operationId': draft.serviceId,
      'status': 'online',
      'source': 'online',
      'olusturan': 'Online',
      'createdByName': 'Online',
      if (mekanName != null) 'locationName': mekanName,
      if (draft.mekanId != null) 'locationId': draft.mekanId,
      if (draft.notes != null && draft.notes!.isNotEmpty) 'aciklama': draft.notes,
      if (draft.staffId != null) 'assignedUserId': draft.staffId,
      if (draft.staffName != null) 'assignedUserName': draft.staffName,
      if (draft.paketId != null) 'paketId': draft.paketId,
      if (draft.paketAdi != null) 'paketAdi': draft.paketAdi,
      if (draft.paketOperationId != null) 'paketOperationId': draft.paketOperationId,
      'createdAt': now,
    });

    final bookingId = rezervasyonDoc.id;

    // Uygulama içi bildirimleri her durumda Firestore'a yaz.
    _notifyReservationAudienceViaFirestore(
      draft: draft,
      bookingId: bookingId,
    ).ignore();

    return bookingId;
  }

  Future<void> _notifyReservationAudienceViaFirestore({
    required BookingDraft draft,
    required String bookingId,
  }) async {
    _log('_notifyReservationAudienceViaFirestore başladı', {
      'orgId': draft.orgId,
      'bookingId': bookingId,
      'staffId': (draft.staffId ?? '').trim(),
      'notifUrlSet': _notifUrl.isNotEmpty,
    });
    const ay = ['Oca','Şub','Mar','Nis','May','Haz','Tem','Ağu','Eyl','Eki','Kas','Ara'];
    final t = draft.startTime;
    final tarihStr =
        '${t.day} ${ay[t.month - 1]}, ${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';
    final notif = NotificationService(
      firestore: _firestore,
      notifUrl: _notifUrl,
    );
    try {
      await notif.sendBookingNotifications(
        kurumkodu: draft.orgId,
        reservationTitle: 'Yeni Online Rezervasyon',
        reservationMessage:
            '${draft.customerName} — $tarihStr tarihine ${draft.serviceName} rezervasyonu oluşturdu.',
        assignmentTitle: 'Yeni İşlem Ataması',
        assignmentMessage:
            '${draft.customerName} için $tarihStr tarihli online randevu size atandı.',
        reservationType: 'rezervasyon',
        assignmentType: 'atama',
        assignedUserId: (draft.staffId ?? '').trim(),
        veri: <String, dynamic>{
          'bookingId': bookingId,
          'customerId': draft.customerId,
        },
      );
      _log('_notifyReservationAudienceViaFirestore tamamlandı', {
        'bookingId': bookingId,
      });
    } catch (e, st) {
      _log('_notifyReservationAudienceViaFirestore hata', {
        'bookingId': bookingId,
        'error': e.toString(),
        'stack': st.toString(),
      });
      rethrow;
    }
  }

  String _buildShortName(String fullName) {
    final parts =
        fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '-';
    final first = parts.first;
    if (parts.length < 2) return first;
    return '$first ${parts.last.substring(0, 1).toUpperCase()}';
  }

  Future<List<BookingSlot>> _fallbackAvailability({
    required AvailabilityQuery query,
    required BookingSettings settings,
    required WorkingHours workingHours,
    required OrgService service,
  }) async {
    final day = DateTimeUtils.stripTime(query.date);
    final dateStr =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final cacheKey = '${query.orgId}_${query.serviceId}_$dateStr';

    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    if (workingHours.closedDates.contains(dateStr)) return const [];

    final weekday = day.weekday;
    final dayConfig = workingHours.days[weekday];
    if (dayConfig == null || !dayConfig.isOpen || dayConfig.windows.isEmpty) {
      return const [];
    }

    final now = DateTime.now();
    final minAllowed = now.add(Duration(hours: settings.minHoursBefore));
    if (!settings.allowSameDay &&
        DateTimeUtils.stripTime(day) == DateTimeUtils.stripTime(now)) {
      return const [];
    }

    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // Single query: all rezervasyonlar for the day (both regular and blocked).
    final snapshot = await _queryRezervasyonlarForDay(
      orgId: query.orgId,
      startOfDay: startOfDay,
      endOfDay: endOfDay,
    );

    // Group occupied intervals by locationId (null = no mekan / applies globally).
    final occupiedByMekan = <String?, List<({DateTime start, DateTime end})>>{};
    // Staff-specific occupied intervals.
    final staffOccupied = <({DateTime start, DateTime end})>[];
    for (final data in snapshot) {
      final status = (data['status'] as String?)?.trim() ?? '';
      final customerId = (data['customerId'] as String?)?.trim() ?? '';
      // Skip cancelled entries; everything else (online, blocked, confirmed, etc.) occupies the slot.
      if (status == 'cancelled' || status == 'iptal') continue;
      final startMin = _readInt(data['startMinutes']) ?? 0;
      final endMin = _readInt(data['endMinutes']) ?? 0;
      if (endMin <= startMin) continue;
      final start = startOfDay.add(Duration(minutes: startMin));
      final end = startOfDay.add(Duration(minutes: endMin));
      // blocked docs use locationId; regular reservations also have locationId.
      final locationId = data['locationId'] as String?;
      // Blocked without locationId → blocks all mekanlar (global block).
      final key = (status == 'blocked' || customerId == '__blocked__') && locationId == null
          ? null
          : locationId;
      occupiedByMekan.putIfAbsent(key, () => []).add((start: start, end: end));
      // Collect staff reservation conflicts.
      if (query.staffId != null && query.staffId!.isNotEmpty) {
        final assignedUserId = (data['assignedUserId'] as String?)?.trim() ?? '';
        if (assignedUserId == query.staffId) {
          staffOccupied.add((start: start, end: end));
        }
      }
    }

    // Fetch staff working hours if staffId is specified.
    DateTime? staffDayStart;
    DateTime? staffDayEnd;
    bool staffWorksToday = true;
    if (query.staffId != null && query.staffId!.isNotEmpty) {
      try {
        final staffDoc = await _firestore
            .collection('kullanicilar')
            .doc(query.staffId)
            .get();
        final rawCG = staffDoc.data()?['calismaGunleri'];
        if (rawCG is Map) {
          // calismaGunleri keys are 0–6 where 0=Pazartesi, 6=Pazar.
          // DateTime.weekday is 1=Mon, 7=Sun → subtract 1 for key.
          final dayKey = (day.weekday - 1).toString();
          final gunData = rawCG[dayKey];
          if (gunData is Map) {
            staffWorksToday = (gunData['aktif'] as bool?) ?? false;
            if (staffWorksToday) {
              final basStr = (gunData['baslangic'] as String?) ?? '09:00';
              final bitStr = (gunData['bitis'] as String?) ?? '18:00';
              final basParts = basStr.split(':');
              final bitParts = bitStr.split(':');
              staffDayStart = DateTime(day.year, day.month, day.day,
                  int.tryParse(basParts[0]) ?? 9, int.tryParse(basParts.length > 1 ? basParts[1] : '0') ?? 0);
              staffDayEnd = DateTime(day.year, day.month, day.day,
                  int.tryParse(bitParts[0]) ?? 18, int.tryParse(bitParts.length > 1 ? bitParts[1] : '0') ?? 0);
            }
          }
        }
      } catch (_) {}
      if (!staffWorksToday) return const [];
    }

    bool conflicts(List<({DateTime start, DateTime end})>? intervals, DateTime s, DateTime e) {
      if (intervals == null) return false;
      return intervals.any((i) => s.isBefore(i.end) && e.isAfter(i.start));
    }

    final slots = <BookingSlot>[];
    final hasMekanFilter = query.mekanIds.isNotEmpty;
    final hasStaffFilter = query.staffId != null && query.staffId!.isNotEmpty;

    for (final window in dayConfig.windows) {
      final startParts = window.start.split(':');
      final endParts = window.end.split(':');
      if (startParts.length != 2 || endParts.length != 2) continue;

      var cursor = DateTime(
        day.year, day.month, day.day,
        int.parse(startParts[0]), int.parse(startParts[1]),
      );
      final windowEnd = DateTime(
        day.year, day.month, day.day,
        int.parse(endParts[0]), int.parse(endParts[1]),
      );

      while (!cursor.add(Duration(minutes: service.durationMinutes)).isAfter(windowEnd)) {
        final slotEnd = cursor.add(Duration(minutes: service.durationMinutes));

        if (!cursor.isBefore(minAllowed)) {
          // Personel filtresi: çalışma saatleri ve meşgul slotları kontrol et.
          if (hasStaffFilter) {
            final withinStaffHours = staffDayStart != null &&
                staffDayEnd != null &&
                !cursor.isBefore(staffDayStart) &&
                !slotEnd.isAfter(staffDayEnd);
            if (!withinStaffHours) {
              cursor = cursor.add(Duration(minutes: settings.slotMinutes));
              continue;
            }
            if (conflicts(staffOccupied, cursor, slotEnd)) {
              cursor = cursor.add(Duration(minutes: settings.slotMinutes));
              continue;
            }
          }

          if (hasMekanFilter) {
            String? freeMekanId;
            for (final mekanId in query.mekanIds) {
              if (!conflicts(occupiedByMekan[null], cursor, slotEnd) &&
                  !conflicts(occupiedByMekan[mekanId], cursor, slotEnd)) {
                freeMekanId = mekanId;
                break;
              }
            }
            if (freeMekanId != null) {
              slots.add(BookingSlot(start: cursor, end: slotEnd, mekanId: freeMekanId));
            }
          } else {
            final allOccupied = occupiedByMekan.values.expand((e) => e).toList();
            if (!allOccupied.any((i) => cursor.isBefore(i.end) && slotEnd.isAfter(i.start))) {
              slots.add(BookingSlot(start: cursor, end: slotEnd));
            }
          }
        }

        cursor = cursor.add(Duration(minutes: settings.slotMinutes));
      }
    }

    _cache[cacheKey] = slots;
    return slots;
  }

  Future<List<Map<String, dynamic>>> _queryRezervasyonlarForDay({
    required String orgId,
    required DateTime startOfDay,
    required DateTime endOfDay,
  }) async {
    final startTs = Timestamp.fromDate(startOfDay);
    final endTs = Timestamp.fromDate(endOfDay);
    try {
      final snapshot = await _firestore
          .collection('kurumlar')
          .doc(orgId)
          .collection('rezervasyonlar')
          .where('date', isGreaterThanOrEqualTo: startTs)
          .where('date', isLessThan: endTs)
          .get();
      return snapshot.docs.map((d) => d.data()).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Bir işlem için tanımlı ve aktif personeli getirir.
  Future<List<Map<String, dynamic>>> fetchStaffForService({
    required String orgId,
    required List<String> personelIds,
  }) async {
    if (personelIds.isEmpty) return const [];
    try {
      final results = <Map<String, dynamic>>[];
      for (final id in personelIds) {
        final doc = await _firestore.collection('kullanicilar').doc(id).get();
        if (!doc.exists) continue;
        final data = doc.data()!;
        final durum = (data['durum'] ?? 'aktif').toString();
        if (durum == 'ayrildi') continue;
        final kurumkodu = (data['kurumkodu'] ?? '').toString();
        if (kurumkodu != orgId) continue;
        results.add({
          'id': id,
          'adi': (data['adi'] ?? '').toString(),
          'soyadi': (data['soyadi'] ?? '').toString(),
          'kisaad': (data['kisaad'] ?? '').toString(),
        });
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// Danışanın aktif paketlerini getirir.
  Future<List<CustomerPackage>> fetchCustomerPackages({
    required String orgId,
    required String customerId,
  }) async {
    if (orgId.isEmpty || customerId.isEmpty) return const [];
    try {
      final snap = await _firestore
          .collection('kurumlar')
          .doc(orgId)
          .collection('danisanlar')
          .doc(customerId)
          .collection('paketler')
          .where('durum', isEqualTo: 'aktif')
          .get();
      return snap.docs
          .map((d) => CustomerPackage.fromMap(d.id, d.data()))
          .where((p) => p.islemler.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Danışanın geçmiş rezervasyonlarını getirir (en yeni 10 tanesi).
  Future<List<Map<String, dynamic>>> fetchPastReservations({
    required String orgId,
    required String customerId,
  }) async {
    if (orgId.isEmpty || customerId.isEmpty) return const [];
    try {
      final snap = await _firestore
          .collection('kurumlar')
          .doc(orgId)
          .collection('rezervasyonlar')
          .where('customerId', isEqualTo: customerId)
          .get();
      final docs = snap.docs.map((d) => d.data()).toList();
      docs.sort((a, b) {
        final aDate = (a['date'] as Timestamp?)?.toDate();
        final bDate = (b['date'] as Timestamp?)?.toDate();
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
      return docs.take(10).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<AccountStatementEntry>> fetchAccountStatement({
    required String orgId,
    required String customerId,
  }) async {
    if (orgId.isEmpty || customerId.isEmpty) return const [];
    final danisanRef = _firestore
        .collection('kurumlar')
        .doc(orgId)
        .collection('danisanlar')
        .doc(customerId);
    try {
      final results = await Future.wait([
        danisanRef.collection('islemler').get(),
        danisanRef.collection('odemeler').get(),
        danisanRef.collection('paketler').get(),
      ]);

      final entries = <AccountStatementEntry>[];

      for (final doc in results[0].docs) {
        final d = doc.data();
        final price = (_readDouble(d['operationPrice'])) ?? 0;
        final opName = (d['operationName'] as String?)?.trim() ?? 'İşlem';
        final type = (d['entryType'] as String?)?.trim().toLowerCase() ?? '';
        final typeLabel = type == 'sale' ? 'Satış' : 'Hizmet';
        final by = (d['performedByName'] as String?)?.trim() ?? '';
        final label = by.isNotEmpty ? '$typeLabel - $opName - $by' : '$typeLabel - $opName';
        final date = _readTimestamp(d['completedAt']) ?? _readTimestamp(d['createdAt']);
        entries.add(AccountStatementEntry(date: date, label: label, debit: price, credit: 0));
      }

      for (final doc in results[1].docs) {
        final d = doc.data();
        final amount = (_readDouble(d['amount'])) ?? 0;
        final type = (d['type'] as String?)?.trim() ?? '';
        final typeLabel = _paymentTypeLabel(type);
        final date = _readTimestamp(d['createdAt']);
        entries.add(AccountStatementEntry(date: date, label: 'Ödeme - $typeLabel', debit: 0, credit: amount));
      }

      for (final doc in results[2].docs) {
        final d = doc.data();
        final amount = (_readDouble(d['fiyat'])) ?? 0;
        if (amount <= 0) continue;
        final name = ((d['paketAdi'] ?? d['adi']) as String?)?.trim() ?? 'Paket';
        final date = _readTimestamp(d['createdAt']) ?? _readTimestamp(d['baslamaTarihi']);
        entries.add(AccountStatementEntry(date: date, label: 'Paket - $name', debit: amount, credit: 0));
      }

      entries.sort((a, b) => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)));

      double running = 0;
      for (final e in entries) {
        running += e.debit - e.credit;
        e.balance = running;
      }

      return entries.reversed.toList();
    } catch (_) {
      return const [];
    }
  }

  String _paymentTypeLabel(String type) {
    return switch (type) {
      'nakit' || 'cash' => 'Nakit',
      'kart' || 'credit_card' => 'Kart',
      'havale' || 'transfer' => 'Havale',
      'online' => 'Online',
      _ => type.isNotEmpty ? type : 'Diğer',
    };
  }

  DateTime? _readTimestamp(dynamic v) {
    if (v == null) return null;
    try { return (v as dynamic).toDate() as DateTime; } catch (_) {}
    if (v is DateTime) return v;
    return null;
  }

  double? _readDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
