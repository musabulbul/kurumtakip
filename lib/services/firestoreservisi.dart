import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../utils/student_utils.dart';
import 'institution_metadata_service.dart';

class FireStoreServisi {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String zaman = DateFormat('yyyy-MM-dd – kk:mm').format(DateTime.now());
  final String kayittarihi = DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> kullaniciOlustur(
      {id,
      kurumkodu,
      kurumturu,
      tckn,
      email,
      kullaniciAdi,
      fotoUrl = "",
      rol,
      adi,
      soyadi,
      hakkinda = ""}) async {
    await _firestore.collection("kullanicilar").doc(id).set({
      "id": id,
      "kurumkodu":kurumkodu,
      "kurumturu":kurumturu,
      "tckn": tckn,
      "kullaniciAdi": kullaniciAdi,
      "email": email,
      "fotoUrl": fotoUrl,
      "rol": rol,
      "adi": adi,
      "soyadi": soyadi,
      "siniflar": [],
      "hakkinda": hakkinda,
      "olusturulmaZamani": zaman
    });
  }

  CollectionReference<Map<String, dynamic>> _studentsCollection(String kurumkodu) {
    return _firestore.collection("kurumlar").doc(kurumkodu).collection("danisanlar");
  }

  Future<String> ogrenciolustur({
    required String kurumkodu,
    String? tckn,
    required String adi,
    required String soyadi,
    required String no,
    required String sinif,
    required String sube,
    required String cinsiyet,
    String? alan,
    String yatililik = "GÜNDÜZLÜ",
    String ogrencitel = "+90",
    String veli1 = "GİRİLMEMİŞ",
    String veli1yakin = "",
    String veli1tel = "+90",
    String veli2 = "GİRİLMEMİŞ",
    String veli2yakin = "",
    String veli2tel = "+90",
    String adres = "GİRİLMEMİŞ",
    String? kayitTarihi,
    Map<String, dynamic>? ekstra,
    bool updateMetadata = true,
  }) async {
    final sinifSube = buildSinifSube(sinif, sube);
    final studentsRef = _studentsCollection(kurumkodu);
    final trimmedTckn = tckn?.trim() ?? '';
    final uniqueKey = buildStudentUniqueKey(
      institutionId: kurumkodu,
      tckn: trimmedTckn,
      name: adi,
      surname: soyadi,
      number: no,
    );

    final duplicateSnapshot = await studentsRef.where('uniqueKey', isEqualTo: uniqueKey).limit(1).get();
    if (duplicateSnapshot.docs.isNotEmpty) {
      throw StateError('Bu öğrenci için zaten kayıt var.');
    }

    final docRef = studentsRef.doc();
    final normalizedKayitTarihi = kayitTarihi?.trim();

    final payload = <String, dynamic>{
      "id": docRef.id,
      "uniqueKey": uniqueKey,
      "adi": adi,
      "soyadi": soyadi,
      "no": no,
      "sinif": sinif,
      "sube": sube,
      if (sinifSube != null) "sinifsube": sinifSube,
      "cinsiyet": cinsiyet,
      "yatililik": yatililik,
      "ogrencitel": ogrencitel,
      "veli1": veli1,
      "veli1yakin": veli1yakin,
      "veli1tel": veli1tel,
      "veli2": veli2,
      "veli2yakin": veli2yakin,
      "veli2tel": veli2tel,
      "adres": adres,
      "kayittarihi": (normalizedKayitTarihi != null && normalizedKayitTarihi.isNotEmpty)
          ? normalizedKayitTarihi
          : this.kayittarihi,
      "kurumkodu": kurumkodu,
      "olusturulmaZamani": Timestamp.now(),
    };

    final trimmedAlan = alan?.trim() ?? '';
    if (trimmedAlan.isNotEmpty) {
      payload['alan'] = trimmedAlan;
    }

    if (trimmedTckn.isNotEmpty) {
      payload["tckn"] = trimmedTckn;
    }

    if (ekstra != null && ekstra.isNotEmpty) {
      payload.addAll(ekstra);
    }

    await docRef.set(payload);

    if (updateMetadata) {
      final metadataService = InstitutionMetadataService(firestore: _firestore);
      await metadataService.refreshClassBranchSummary(kurumkodu);
    }
    return docRef.id;
  }

  Future<void> topluogrenciolustur({
    id,
    kurumkodu,
    tckn,
    adi,
    soyadi,
    no,
    sinif,
    sube,
    cinsiyet,
    alan,
    yatililik,
    ogrencitel,
    veli1,
    veli1yakin,
    veli1tel,
    veli2,
    veli2yakin,
    veli2tel,
    adres,
    kayittarihi,
    
  }) async {
    final kurumIdString = (kurumkodu ?? '').toString();
    final sinifSube = buildSinifSube(sinif, sube);
    final ekstra = <String, dynamic>{};
    if (alan != null) ekstra['alan'] = alan;
    if (sinifSube != null) {
      ekstra['sinifsube'] = sinifSube;
    }

    await ogrenciolustur(
      kurumkodu: kurumIdString,
      tckn: (tckn ?? '').toString().trim().isEmpty ? null : (tckn ?? '').toString().trim(),
      adi: (adi ?? '').toString(),
      soyadi: (soyadi ?? '').toString(),
      no: (no ?? '').toString(),
      sinif: (sinif ?? '').toString(),
      sube: (sube ?? '').toString(),
      cinsiyet: (cinsiyet ?? '').toString(),
      yatililik: (yatililik ?? '').toString(),
      ogrencitel: (ogrencitel ?? '').toString(),
      veli1: (veli1 ?? '').toString(),
      veli1yakin: (veli1yakin ?? '').toString(),
      veli1tel: (veli1tel ?? '').toString(),
      veli2: (veli2 ?? '').toString(),
      veli2yakin: (veli2yakin ?? '').toString(),
      veli2tel: (veli2tel ?? '').toString(),
      adres: (adres ?? '').toString(),
      kayitTarihi: (kayittarihi ?? '').toString(),
      ekstra: ekstra,
      updateMetadata: false,
    );
  }

 

  

  

  
  
}
