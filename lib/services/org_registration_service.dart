import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'notification_service.dart';

class OrgRegistrationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const _baseUrl = String.fromEnvironment(
    'SMS_SERVICE_URL',
    defaultValue: 'https://whatsapp-service-694457330631.europe-west1.run.app',
  );

  String slugify(String raw) {
    var value = raw.toLowerCase().trim();
    const trMap = {
      'ç': 'c',
      'ğ': 'g',
      'ı': 'i',
      'ö': 'o',
      'ş': 's',
      'ü': 'u',
    };
    trMap.forEach((key, val) => value = value.replaceAll(key, val));
    value = value.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    value = value.replaceAll(RegExp(r'-{2,}'), '-');
    value = value.replaceAll(RegExp(r'^-+|-+$'), '');
    return value;
  }

  Future<String> _ensureUniqueSlug(String baseName) async {
    var candidate = slugify(baseName);
    if (candidate.isEmpty) throw Exception('Geçerli bir kurum adı giriniz.');
    var suffix = 1;
    while (true) {
      final query = await _firestore
          .collection('kurumlar')
          .where('slug', isEqualTo: candidate)
          .limit(1)
          .get();
      if (query.docs.isEmpty) return candidate;
      suffix++;
      candidate = '${slugify(baseName)}-$suffix';
    }
  }

  String _generateKurumKodu(String kisaad) {
    final clean = kisaad
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-ZÇĞİÖŞÜ0-9]'), '');
    final prefix = clean.isEmpty
        ? 'KURUM'
        : (clean.length > 8 ? clean.substring(0, 8) : clean);
    final suffix = (1000 + Random().nextInt(9000)).toString();
    return '$prefix$suffix';
  }

  Future<String> _ensureUniqueKurumKodu(String kisaad) async {
    while (true) {
      final candidate = _generateKurumKodu(kisaad);
      final doc = await _firestore.collection('kurumlar').doc(candidate).get();
      if (!doc.exists) return candidate;
    }
  }

  String normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    var normalized = digits;
    if (normalized.startsWith('00')) normalized = normalized.substring(2);
    if (normalized.startsWith('90') && normalized.length == 12) {
      normalized = normalized.substring(2);
    }
    if (normalized.startsWith('0') && normalized.length == 11) {
      normalized = normalized.substring(1);
    }
    if (!normalized.startsWith('90')) normalized = '90$normalized';
    return '+$normalized';
  }

  /// Email veya telefon daha önce kayıtlı mı kontrol eder.
  /// Backend endpoint kullanır; ulaşılamazsa sessizce atlanır
  /// (Firebase Auth zaten email duplikasyonunu yakalar).
  /// {'emailExists': bool, 'phoneExists': bool} döner.
  Future<Map<String, bool>> checkDuplicates({
    required String email,
    required String phone,
  }) async {
    final normalizedPhone = normalizePhone(phone);
    try {
      final response = await http
          .post(
            Uri.parse(
                '${_baseUrl.replaceAll(RegExp(r'/+$'), '')}/registration/check'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'phone': normalizedPhone,
            }),
          )
          .timeout(const Duration(seconds: 8));

      Map<String, dynamic> decoded = const {};
      try {
        final raw = jsonDecode(response.body);
        if (raw is Map<String, dynamic>) decoded = raw;
      } catch (_) {}

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {
          'emailExists': decoded['emailExists'] == true,
          'phoneExists': decoded['phoneExists'] == true,
        };
      }
    } catch (_) {
      // Backend ulaşılamazsa veya timeout olursa atla.
      // createUserWithEmailAndPassword email duplikasyonunu zaten yakalar.
    }

    return {'emailExists': false, 'phoneExists': false};
  }

  /// Kayıt için OTP gönderir; doğrulama kodunu (token) döner.
  /// Önce yeni /sms/registration-otp endpoint'ini dener;
  /// ulaşılamazsa mevcut /sms/otp endpoint'ini kullanır
  /// (kurumlar koleksiyonundan sistem kurumunu okur — public read).
  Future<String> sendRegistrationOtp(String phone) async {
    final normalizedPhone = normalizePhone(phone);
    final base = _baseUrl.replaceAll(RegExp(r'/+$'), '');

    // Önce yeni endpoint'i dene
    try {
      final resp = await http
          .post(
            Uri.parse('$base/sms/registration-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': normalizedPhone}),
          )
          .timeout(const Duration(seconds: 10));

      Map<String, dynamic> dec = const {};
      try {
        final raw = jsonDecode(resp.body);
        if (raw is Map<String, dynamic>) dec = raw;
      } catch (_) {}

      if (resp.statusCode >= 200 && resp.statusCode < 300 && dec['ok'] == true) {
        final code = (dec['code'] as String?)?.trim() ?? '';
        if (code.isNotEmpty) return code;
      }
      // 404 → endpoint yok, fallback'e geç; diğer hatalar fırlat
      if (resp.statusCode != 404) {
        final errCode = (dec['error'] as String?)?.trim() ?? '';
        final msg = switch (errCode) {
          'sms_provider_missing' => 'SMS sağlayıcısı tanımlı değil.',
          'sms_provider_not_found' => 'SMS sağlayıcısı bulunamadı.',
          'sms_provider_failed' => 'SMS gönderilemedi. Lütfen tekrar deneyin.',
          _ => (dec['message'] as String?)?.trim() ?? 'Doğrulama kodu gönderilemedi.',
        };
        throw Exception(msg);
      }
    } catch (e) {
      if (e is Exception &&
          e.toString().contains('Doğrulama kodu') == false &&
          e.toString().contains('SMS') == false) {
        // Bağlantı hatası → fallback
      } else {
        rethrow;
      }
    }

    // Fallback: mevcut /sms/otp — sistem kurumunu slug ile bul (public read)
    const systemSlug = String.fromEnvironment(
      'SYSTEM_KURUM_SLUG',
      defaultValue: 'mebs',
    );

    final slugQuery = await _firestore
        .collection('kurumlar')
        .where('slug', isEqualTo: systemSlug)
        .limit(1)
        .get();

    if (slugQuery.docs.isEmpty) {
      throw Exception('Sistem SMS sağlayıcısı bulunamadı ($systemSlug).');
    }

    final kurumId = slugQuery.docs.first.id;

    final response = await http
        .post(
          Uri.parse('$base/sms/otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'kurum_id': kurumId,
            'phone': normalizedPhone,
            'org_name': 'Mebs Kurum Takip kayit',
          }),
        )
        .timeout(const Duration(seconds: 15));

    Map<String, dynamic> decoded = const {};
    try {
      final raw = jsonDecode(response.body);
      if (raw is Map<String, dynamic>) decoded = raw;
    } catch (_) {}

    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        decoded['ok'] == true) {
      final code = (decoded['code'] as String?)?.trim() ?? '';
      if (code.isNotEmpty) return code;
    }

    final errCode = (decoded['error'] as String?)?.trim() ?? '';
    final msg = switch (errCode) {
      'sms_provider_missing' => 'SMS sağlayıcısı tanımlı değil.',
      'sms_provider_not_found' => 'SMS sağlayıcısı bulunamadı.',
      'sms_provider_failed' => 'SMS gönderilemedi. Lütfen tekrar deneyin.',
      _ => (decoded['message'] as String?)?.trim() ?? 'Doğrulama kodu gönderilemedi.',
    };
    throw Exception(msg);
  }

  /// Kurum ve yönetici kullanıcı kaydını gerçekleştirir.
  /// Başarıda {'userDocId': String, 'kurumkodu': String} döner.
  Future<Map<String, String>> registerOrgAndAdmin({
    required String kurumAdi,
    required String kisaad,
    required String il,
    required String ilce,
    required String mahalle,
    required String adres,
    required String yetkiliAdi,
    required String yetkiliSoyadi,
    required String email,
    required String sifre,
    required String telefon,
  }) async {
    final kurumkodu = await _ensureUniqueKurumKodu(kisaad);
    final slug = await _ensureUniqueSlug(kurumAdi);

    final now = DateTime.now();
    final bitisTarihi = DateTime(now.year, now.month + 1, now.day);
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    UserCredential userCred;
    try {
      userCred = await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: sifre,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw Exception('Bu e-posta adresi zaten kayıtlı.');
      }
      throw Exception('Hesap oluşturulamadı: ${e.message}');
    }

    try {
      final batch = _firestore.batch();
      final normalizedPhone = normalizePhone(telefon);
      final fullAdres = [mahalle.trim(), adres.trim()]
          .where((s) => s.isNotEmpty)
          .join(', ');

      final orgRef = _firestore.collection('kurumlar').doc(kurumkodu);
      final slugRef = _firestore.collection('orgSlugs').doc(slug);
      batch.set(slugRef, {
        'orgId': kurumkodu,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(orgRef, {
        'kurumadi': kurumAdi.trim(),
        'kisaad': kisaad.trim(),
        'kurumkodu': kurumkodu,
        'slug': slug,
        'il': il.trim(),
        'ilce': ilce.trim(),
        'mahalle': mahalle.trim(),
        'adres': fullAdres,
        'ilgiliKisiAdi': '${yetkiliAdi.trim()} ${yetkiliSoyadi.trim()}',
        'ilgiliKisiTelefon': normalizedPhone,
        'baslangicTarihi': fmt(now),
        'bitisTarihi': fmt(bitisTarihi),
        'kurumturu': '',
        'bookingEnabled': false,
        'olusturulmaZamani': FieldValue.serverTimestamp(),
        'kayitTipi': 'online_kayit',
      });

      final adInitials = yetkiliAdi
          .trim()
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .map((w) => '${w[0].toUpperCase()}.')
          .join();
      final userKisaad = '$adInitials${yetkiliSoyadi.trim()}';

      final userDocRef = _firestore.collection('kullanicilar').doc();
      batch.set(userDocRef, {
        'uid': userCred.user!.uid,
        'email': email.trim().toLowerCase(),
        'telefon': normalizedPhone,
        'adi': yetkiliAdi.trim(),
        'soyadi': yetkiliSoyadi.trim(),
        'kisaad': userKisaad,
        'kurumkodu': kurumkodu,
        'rol': 'YÖNETİCİ',
        'kullaniciAdi': email.trim().toLowerCase(),
        'olusturulmaZamani': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      // Varsayılan mekan, kategori ve işlem verilerini oluştur
      await _createDefaultData(kurumkodu);

      // Üst yönetici (admin) kullanıcılara yeni kurum kaydı bildirimi gönder.
      _notifyAdmins(kurumkodu: kurumkodu, kurumAdi: kurumAdi.trim()).ignore();

      return {'userDocId': userDocRef.id, 'kurumkodu': kurumkodu};
    } catch (e) {
      await userCred.user?.delete();
      rethrow;
    }
  }

  Future<void> _notifyAdmins({
    required String kurumkodu,
    required String kurumAdi,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('kullanicilar')
          .where('ustyonetici', isEqualTo: 'admin')
          .get();

      final notif = NotificationService();
      await Future.wait(snapshot.docs.map((doc) => notif.sendToUser(
            userId: doc.id,
            baslik: 'Yeni Kurum Kaydı',
            mesaj: kurumAdi,
            tip: 'yeni_kurum',
            veri: {'kurumkodu': kurumkodu},
          )));
    } catch (_) {
      // Bildirim hatası kayıt işlemini etkilemez.
    }
  }

  Future<void> _createDefaultData(String kurumkodu) async {
    final orgRef = _firestore.collection('kurumlar').doc(kurumkodu);

    // ── 1. Çalışma saatleri ──────────────────────────────────────────────────
    final whMap = <String, dynamic>{};
    for (var i = 1; i <= 7; i++) {
      whMap['$i'] = {
        'isOpen': i <= 5,
        'windows': [
          {'start': '09:00', 'end': '18:00'},
        ],
      };
    }
    whMap['closedDates'] = <String>[];
    await orgRef.set({'workingHours': whMap}, SetOptions(merge: true));

    // ── 2. Mekanlar (3 adet) ─────────────────────────────────────────────────
    final mekanlarRef = orgRef.collection('mekanlar');
    final mekanIds = <String>[];
    for (var i = 1; i <= 3; i++) {
      final doc = await mekanlarRef.add({
        'adi': 'Salon $i',
        'siraNo': i,
        'createdAt': FieldValue.serverTimestamp(),
      });
      mekanIds.add(doc.id);
    }

    // ── 3. Kategoriler (2 adet) + her birine 2 işlem ─────────────────────────
    final kategoriler = [
      {'adi': 'Genel Hizmetler', 'islemler': ['Hizmet 1', 'Hizmet 2']},
      {'adi': 'Özel Hizmetler', 'islemler': ['Hizmet 3', 'Hizmet 4']},
    ];

    final kategoriRef = orgRef.collection('islemKategorileri');
    for (final kat in kategoriler) {
      final katDoc = await kategoriRef.add({
        'adi': kat['adi'],
        'createdAt': FieldValue.serverTimestamp(),
      });
      final islemlerRef = katDoc.collection('islemler');
      for (final islemAdi in kat['islemler'] as List<String>) {
        await islemlerRef.add({
          'adi': islemAdi,
          'fiyat': 0.0,
          'seansSayisi': 1,
          'sureDakika': 30,
          'onlineAktif': false,
          'mekanIds': mekanIds,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }
}
