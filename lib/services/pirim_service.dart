import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pirim_model.dart';

class PirimService {
  PirimService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _tanimlarRef(String userId) =>
      _db.collection('kullanicilar').doc(userId).collection('pirimTanimlari');

  CollectionReference<Map<String, dynamic>> _kayitlarRef(String userId) =>
      _db.collection('kullanicilar').doc(userId).collection('pirimKayitlari');

  // ─── Pirim Tanımları ──────────────────────────────────────────────────────

  Future<List<PirimTanimi>> getPirimTanimlari(String userId) async {
    final snap = await _tanimlarRef(userId).get();
    final list = snap.docs
        .map((d) => PirimTanimi.fromMap(d.id, d.data()))
        .toList();
    // Satış en sona, hizmet kategorileri alfabetik
    list.sort((a, b) {
      if (a.isSatis) return 1;
      if (b.isSatis) return -1;
      return a.kategoriAdi.compareTo(b.kategoriAdi);
    });
    return list;
  }

  Future<void> savePirimTanimi(String userId, PirimTanimi tanim) async {
    await _tanimlarRef(userId).doc(tanim.kategoriId).set(tanim.toMap());
  }

  Future<void> deletePirimTanimi(String userId, String kategoriId) async {
    await _tanimlarRef(userId).doc(kategoriId).delete();
  }

  // ─── Aylık Pirim Hesaplama ────────────────────────────────────────────────

  Future<AylikPirim> hesaplaAylikPirim(
      String userId, int yil, int ay) async {
    final tanimlar = await getPirimTanimlari(userId);
    final tanimMap = {for (final t in tanimlar) t.kategoriId: t};

    final startDate = DateTime(yil, ay);
    final endDate = DateTime(yil, ay + 1);

    final snap = await _db
        .collectionGroup('islemler')
        .where('performedById', isEqualTo: userId)
        .where('completedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('completedAt', isLessThan: Timestamp.fromDate(endDate))
        .get();

    final Map<String, _KategoriAcc> accMap = {};

    for (final doc in snap.docs) {
      final data = doc.data();
      final entryType = (data['entryType'] as String?) ?? '';
      final price = (data['operationPrice'] as num?)?.toDouble() ?? 0.0;
      if (price <= 0) continue;

      final bool isSatis = entryType == 'satis';

      // Satış işlemleri → özel Satış kategorisi
      // Hizmet işlemleri → kendi kategorisi
      final categoryId = isSatis
          ? kSatisPirimKategoriId
          : ((data['operationCategoryId'] ?? data['categoryId']) as String? ??
              '');
      final categoryName = isSatis
          ? kSatisPirimKategoriAdi
          : ((data['operationCategoryName'] ?? data['categoryName'])
                  as String?)
              ?.trim() ??
              'Kategorisiz';

      if (categoryId.isEmpty) continue;

      accMap.putIfAbsent(
          categoryId, () => _KategoriAcc(categoryId, categoryName));
      accMap[categoryId]!.toplam += price;
    }

    final kalemler = accMap.values.map((acc) {
      final tanim = tanimMap[acc.kategoriId];
      return AylikPirimKalemi(
        kategoriId: acc.kategoriId,
        kategoriAdi: acc.kategoriAdi,
        toplam: acc.toplam,
        oran: tanim?.oran ?? 0,
      );
    }).toList()
      ..sort((a, b) {
        if (a.isSatis) return 1;
        if (b.isSatis) return -1;
        return a.kategoriAdi.compareTo(b.kategoriAdi);
      });

    return AylikPirim(
      userId: userId,
      yil: yil,
      ay: ay,
      kalemler: kalemler,
      durum: 'bekliyor',
    );
  }

  // ─── Pirim Kayıtları ──────────────────────────────────────────────────────

  Future<void> saveAylikPirim(AylikPirim pirim) async {
    await _kayitlarRef(pirim.userId).doc(pirim.yilAyKey).set(pirim.toMap());
  }

  Future<AylikPirim?> getAylikPirim(String userId, int yil, int ay) async {
    final key = '$yil-${ay.toString().padLeft(2, '0')}';
    final doc = await _kayitlarRef(userId).doc(key).get();
    if (!doc.exists || doc.data() == null) return null;
    return AylikPirim.fromMap(userId, key, doc.data()!);
  }

  Future<void> onaylaAylikPirim(
      String userId, int yil, int ay, String onaylayan) async {
    final key = '$yil-${ay.toString().padLeft(2, '0')}';
    await _kayitlarRef(userId).doc(key).update({
      'durum': 'onaylandi',
      'onaylayan': onaylayan,
      'onayTarihi': FieldValue.serverTimestamp(),
    });
  }

  Future<void> odemeYapildi(String userId, int yil, int ay) async {
    final key = '$yil-${ay.toString().padLeft(2, '0')}';
    await _kayitlarRef(userId).doc(key).update({
      'durum': 'odendi',
      'odemeTarihi': FieldValue.serverTimestamp(),
    });
  }
}

class _KategoriAcc {
  final String kategoriId;
  final String kategoriAdi;
  double toplam = 0;

  _KategoriAcc(this.kategoriId, this.kategoriAdi);
}
