// ─── Banner Görseli ──────────────────────────────────────────────────────────

class BannerImage {
  final String url;
  final String caption;

  const BannerImage({required this.url, required this.caption});

  factory BannerImage.fromMap(Map<String, dynamic> map) {
    return BannerImage(
      url: (map['url'] as String?) ?? '',
      caption: (map['caption'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() => {'url': url, 'caption': caption};
}

// ─── Booking Ayarları ─────────────────────────────────────────────────────────

class BookingSettings {
  final bool enabled;
  final int maxDaysAhead;
  final int minHoursBefore;
  final int slotMinutes;
  final bool allowSameDay;
  final bool weekendOpen;
  final String authMode;
  final bool showServicePrices;
  final bool showAccountStatement;
  final String? publicInfoText;
  final String? successText;

  // AI Asistan ayarları
  /// AI asistanın rezervasyon sayfasında görünüp görünmeyeceğini belirler.
  final bool aiAssistantEnabled;
  /// Asistana verilecek kuruma özel talimatlar ve ek bilgiler.
  final String? aiExtraContext;

  /// Randevu sayfasında görüntülenen tanıtım görselleri (en fazla 3).
  final List<BannerImage> bannerImages;

  /// Danışanın randevu sırasında personel seçip seçemeyeceğini belirler.
  final bool allowStaffSelection;

  const BookingSettings({
    required this.enabled,
    required this.maxDaysAhead,
    required this.minHoursBefore,
    required this.slotMinutes,
    required this.allowSameDay,
    required this.weekendOpen,
    required this.authMode,
    required this.showServicePrices,
    required this.showAccountStatement,
    this.publicInfoText,
    this.successText,
    this.aiAssistantEnabled = false,
    this.aiExtraContext,
    this.bannerImages = const [],
    this.allowStaffSelection = false,
  });

  factory BookingSettings.fromMap(Map<String, dynamic>? map) {
    final source = map ?? <String, dynamic>{};
    return BookingSettings(
      enabled: source['enabled'] == true,
      maxDaysAhead: (source['maxDaysAhead'] as num?)?.toInt() ?? 30,
      minHoursBefore: (source['minHoursBefore'] as num?)?.toInt() ?? 2,
      slotMinutes: (source['slotMinutes'] as num?)?.toInt() ?? 15,
      allowSameDay: source['allowSameDay'] != false,
      weekendOpen: source['weekendOpen'] == true,
      authMode: (source['authMode'] as String?) == 'otp' ? 'otp' : 'phone_birthdate',
      showServicePrices: source['showServicePrices'] == true,
      showAccountStatement: source['showAccountStatement'] == true,
      publicInfoText: source['publicInfoText'] as String?,
      successText: source['successText'] as String?,
      aiAssistantEnabled: source['aiAssistantEnabled'] == true,
      aiExtraContext: source['aiExtraContext'] as String?,
      bannerImages: ((source['bannerImages'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => BannerImage.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      allowStaffSelection: source['allowStaffSelection'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'maxDaysAhead': maxDaysAhead,
      'minHoursBefore': minHoursBefore,
      'slotMinutes': slotMinutes,
      'allowSameDay': allowSameDay,
      'weekendOpen': weekendOpen,
      'authMode': authMode,
      'showServicePrices': showServicePrices,
      'showAccountStatement': showAccountStatement,
      'publicInfoText': publicInfoText,
      'successText': successText,
      'aiAssistantEnabled': aiAssistantEnabled,
      'aiExtraContext': aiExtraContext,
      'bannerImages': bannerImages.map((b) => b.toMap()).toList(),
      'allowStaffSelection': allowStaffSelection,
    };
  }
}

class WorkingHourWindow {
  final String start;
  final String end;

  const WorkingHourWindow({
    required this.start,
    required this.end,
  });

  factory WorkingHourWindow.fromMap(Map<String, dynamic> map) {
    return WorkingHourWindow(
      start: (map['start'] as String?) ?? '09:00',
      end: (map['end'] as String?) ?? '18:00',
    );
  }

  Map<String, dynamic> toMap() => {
        'start': start,
        'end': end,
      };
}

class WorkingDayConfig {
  final bool isOpen;
  final List<WorkingHourWindow> windows;

  const WorkingDayConfig({
    required this.isOpen,
    required this.windows,
  });

  factory WorkingDayConfig.fromMap(Map<String, dynamic>? map) {
    final source = map ?? <String, dynamic>{};
    final rawWindows = (source['windows'] as List?) ?? const [];
    return WorkingDayConfig(
      isOpen: source['isOpen'] != false,
      windows: rawWindows
          .whereType<Map>()
          .map((e) => WorkingHourWindow.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'isOpen': isOpen,
        'windows': windows.map((e) => e.toMap()).toList(),
      };
}

class WorkingHours {
  final Map<int, WorkingDayConfig> days;
  final List<String> closedDates;

  const WorkingHours({
    required this.days,
    required this.closedDates,
  });

  factory WorkingHours.fromMap(Map<String, dynamic>? map) {
    final source = map ?? <String, dynamic>{};
    final dayMap = <int, WorkingDayConfig>{};

    for (var i = 1; i <= 7; i++) {
      final key = i.toString();
      dayMap[i] = WorkingDayConfig.fromMap(
        source[key] is Map ? Map<String, dynamic>.from(source[key] as Map) : null,
      );
    }

    final closed = (source['closedDates'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];

    return WorkingHours(days: dayMap, closedDates: closed);
  }

  Map<String, dynamic> toMap() {
    final result = <String, dynamic>{};
    days.forEach((key, value) {
      result['$key'] = value.toMap();
    });
    result['closedDates'] = closedDates;
    return result;
  }
}
