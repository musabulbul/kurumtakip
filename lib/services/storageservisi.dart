import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

class StorageServisi {
  final Reference _storage = FirebaseStorage.instance.ref();
  final Uuid _uuid = const Uuid();
  late String resimId;

  Future<String> profilResmiYukle(File resimDosyasi) async {
    resimId = _uuid.v4();
    final uploadTask = _storage
        .child("resimler/profil/profil_$resimId.jpg")
        .putFile(resimDosyasi);
    final snapshot = await uploadTask;
    return snapshot.ref.getDownloadURL();
  }

  void gonderiResmiSil(String gonderiResmiUrl) {
    RegExp arama = RegExp(r"gonderi_.+\.jpg");
    var eslesme = arama.firstMatch(gonderiResmiUrl);
    String? dosyaAdi = eslesme![0];

    if (dosyaAdi != null) {
      _storage.child("resimler/gonderiler/$dosyaAdi").delete();
    }
  }
}
