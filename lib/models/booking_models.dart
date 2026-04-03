class BookingSlot {
  final DateTime start;
  final DateTime end;
  final String? mekanId;

  const BookingSlot({required this.start, required this.end, this.mekanId});

  String get label {
    final hh = start.hour.toString().padLeft(2, '0');
    final mm = start.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Map<String, dynamic> toMap() {
    return {
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      if (mekanId != null) 'mekanId': mekanId,
    };
  }

  factory BookingSlot.fromMap(Map<String, dynamic> map) {
    return BookingSlot(
      start: DateTime.parse(map['start'] as String),
      end: DateTime.parse(map['end'] as String),
      mekanId: map['mekanId'] as String?,
    );
  }
}

class BookingDraft {
  final String orgId;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String serviceId;
  final String serviceName;
  final DateTime bookingDate;
  final DateTime startTime;
  final DateTime endTime;
  final String source;
  final String? notes;
  final String? staffId;
  final String? staffName;
  final String? mekanId;
  final String? paketId;
  final String? paketAdi;
  final String? paketOperationId;

  const BookingDraft({
    required this.orgId,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.serviceId,
    required this.serviceName,
    required this.bookingDate,
    required this.startTime,
    required this.endTime,
    this.source = 'online',
    this.notes,
    this.staffId,
    this.staffName,
    this.mekanId,
    this.paketId,
    this.paketAdi,
    this.paketOperationId,
  });

  Map<String, dynamic> toApiPayload() {
    return {
      'orgId': orgId,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'serviceId': serviceId,
      'serviceName': serviceName,
      'bookingDate': bookingDate.toIso8601String(),
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'source': source,
      'notes': notes,
      'staffId': staffId,
      'staffName': staffName,
      if (mekanId != null) 'mekanId': mekanId,
      if (paketId != null) 'paketId': paketId,
      if (paketAdi != null) 'paketAdi': paketAdi,
      if (paketOperationId != null) 'paketOperationId': paketOperationId,
    };
  }
}

// ─── Customer Package models ──────────────────────────────────────────────────

class CustomerPackageOp {
  final String operationId;
  final String operationName;
  final int seansSayisi;
  final bool sinirsiz;
  final int kalanSeans;
  final int yapilanSeans;

  const CustomerPackageOp({
    required this.operationId,
    required this.operationName,
    required this.seansSayisi,
    required this.sinirsiz,
    required this.kalanSeans,
    required this.yapilanSeans,
  });

  bool get hasRemaining => sinirsiz || kalanSeans > 0;

  factory CustomerPackageOp.fromMap(Map<String, dynamic> m) {
    return CustomerPackageOp(
      operationId: (m['operationId'] as String?) ?? '',
      operationName: (m['operationName'] as String?) ?? '',
      seansSayisi: (m['seansSayisi'] as num?)?.toInt() ?? 0,
      sinirsiz: m['sinirsiz'] == true,
      kalanSeans: (m['kalanSeans'] as num?)?.toInt() ?? 0,
      yapilanSeans: (m['yapilanSeans'] as num?)?.toInt() ?? 0,
    );
  }
}

class CustomerPackage {
  final String id;
  final String paketAdi;
  final DateTime? bitisTarihi;
  final bool suresiz;
  final List<CustomerPackageOp> islemler;

  const CustomerPackage({
    required this.id,
    required this.paketAdi,
    required this.islemler,
    this.bitisTarihi,
    this.suresiz = false,
  });

  bool get hasUsableOps => islemler.any((o) => o.hasRemaining);

  factory CustomerPackage.fromMap(String id, Map<String, dynamic> m) {
    final rawOps = m['islemler'];
    final ops = rawOps is List
        ? rawOps
            .whereType<Map>()
            .map((e) => CustomerPackageOp.fromMap(
                Map<String, dynamic>.from(e)))
            .toList()
        : <CustomerPackageOp>[];
    return CustomerPackage(
      id: id,
      paketAdi: (m['paketAdi'] as String?) ?? 'Paket',
      suresiz: m['suresiz'] == true,
      bitisTarihi: _toDate(m['bitisTarihi']),
      islemler: ops,
    );
  }

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    // Firestore Timestamp duck-typing
    if (v is DateTime) return v;
    try {
      final ts = v as dynamic;
      return (ts.toDate() as DateTime);
    } catch (_) {}
    return null;
  }
}

class AccountStatementEntry {
  final DateTime? date;
  final String label;
  final double debit;
  final double credit;
  double balance;

  AccountStatementEntry({
    this.date,
    required this.label,
    required this.debit,
    required this.credit,
    this.balance = 0,
  });
}

class AvailabilityQuery {
  final String orgId;
  final String serviceId;
  final DateTime date;
  final String? staffId;
  final List<String> mekanIds;

  const AvailabilityQuery({
    required this.orgId,
    required this.serviceId,
    required this.date,
    this.staffId,
    this.mekanIds = const [],
  });

  Map<String, dynamic> toApiPayload() {
    return {
      'orgId': orgId,
      'serviceId': serviceId,
      'date': date.toIso8601String(),
      'staffId': staffId,
      if (mekanIds.isNotEmpty) 'mekanIds': mekanIds,
    };
  }
}
