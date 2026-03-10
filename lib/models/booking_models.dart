class BookingSlot {
  final DateTime start;
  final DateTime end;

  const BookingSlot({required this.start, required this.end});

  String get label {
    final hh = start.hour.toString().padLeft(2, '0');
    final mm = start.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Map<String, dynamic> toMap() {
    return {
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
    };
  }

  factory BookingSlot.fromMap(Map<String, dynamic> map) {
    return BookingSlot(
      start: DateTime.parse(map['start'] as String),
      end: DateTime.parse(map['end'] as String),
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
    };
  }
}

class AvailabilityQuery {
  final String orgId;
  final String serviceId;
  final DateTime date;
  final String? staffId;

  const AvailabilityQuery({
    required this.orgId,
    required this.serviceId,
    required this.date,
    this.staffId,
  });

  Map<String, dynamic> toApiPayload() {
    return {
      'orgId': orgId,
      'serviceId': serviceId,
      'date': date.toIso8601String(),
      'staffId': staffId,
    };
  }
}
