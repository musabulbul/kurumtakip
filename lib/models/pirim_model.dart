import 'package:cloud_firestore/cloud_firestore.dart';

/// Satış işlemlerini temsil eden özel sabit kategori ID'si.
const kSatisPirimKategoriId = '_satis_';
const kSatisPirimKategoriAdi = 'Satış';

class PirimTanimi {
  final String kategoriId;
  final String kategoriAdi;
  final double oran;

  const PirimTanimi({
    required this.kategoriId,
    required this.kategoriAdi,
    required this.oran,
  });

  bool get isSatis => kategoriId == kSatisPirimKategoriId;

  factory PirimTanimi.fromMap(String id, Map<String, dynamic> map) {
    return PirimTanimi(
      kategoriId: id,
      kategoriAdi: (map['kategoriAdi'] as String?) ?? '',
      oran: (map['oran'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'kategoriAdi': kategoriAdi,
        'oran': oran,
      };
}

class AylikPirimKalemi {
  final String kategoriId;
  final String kategoriAdi;
  final double toplam;
  final double oran;

  const AylikPirimKalemi({
    required this.kategoriId,
    required this.kategoriAdi,
    required this.toplam,
    required this.oran,
  });

  bool get isSatis => kategoriId == kSatisPirimKategoriId;
  double get pirim => toplam * oran / 100;

  factory AylikPirimKalemi.fromMap(Map<String, dynamic> map) {
    return AylikPirimKalemi(
      kategoriId: (map['kategoriId'] as String?) ?? '',
      kategoriAdi: (map['kategoriAdi'] as String?) ?? '',
      toplam: (map['toplam'] as num?)?.toDouble() ?? 0,
      oran: (map['oran'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'kategoriId': kategoriId,
        'kategoriAdi': kategoriAdi,
        'toplam': toplam,
        'oran': oran,
      };
}

class AylikPirim {
  final String userId;
  final int yil;
  final int ay;
  final List<AylikPirimKalemi> kalemler;
  final String durum; // 'bekliyor' | 'onaylandi' | 'odendi'
  final String? onaylayan;
  final DateTime? onayTarihi;
  final DateTime? odemeTarihi;

  const AylikPirim({
    required this.userId,
    required this.yil,
    required this.ay,
    required this.kalemler,
    required this.durum,
    this.onaylayan,
    this.onayTarihi,
    this.odemeTarihi,
  });

  double get toplamPirim => kalemler.fold(0, (s, k) => s + k.pirim);

  String get yilAyKey => '$yil-${ay.toString().padLeft(2, '0')}';

  factory AylikPirim.fromMap(
      String userId, String key, Map<String, dynamic> map) {
    final parts = key.split('-');
    final kalemlerRaw = map['kalemler'];
    final kalemler = kalemlerRaw is List
        ? kalemlerRaw
            .map((e) =>
                AylikPirimKalemi.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList()
        : <AylikPirimKalemi>[];

    return AylikPirim(
      userId: userId,
      yil: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0,
      ay: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
      kalemler: kalemler,
      durum: (map['durum'] as String?) ?? 'bekliyor',
      onaylayan: map['onaylayan'] as String?,
      onayTarihi: _toDate(map['onayTarihi']),
      odemeTarihi: _toDate(map['odemeTarihi']),
    );
  }

  Map<String, dynamic> toMap() => {
        'yil': yil,
        'ay': ay,
        'kalemler': kalemler.map((k) => k.toMap()).toList(),
        'durum': durum,
        'toplamPirim': toplamPirim,
        if (onaylayan != null) 'onaylayan': onaylayan,
      };

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
