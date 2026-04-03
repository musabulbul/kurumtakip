import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/booking_models.dart';
import '../models/booking_settings.dart';
import '../models/org_public_profile.dart';
import '../models/org_service.dart';
import 'booking_api_service.dart';
import 'phone_verification_service.dart';

// ─── Veri Modelleri ──────────────────────────────────────────────────────────

/// Sohbet ekranında görüntülenen bir mesajı temsil eder.
class AiChatMessage {
  final String role; // 'user' veya 'model'
  final String text;
  final bool isLoading;
  final bool isError;

  const AiChatMessage({
    required this.role,
    required this.text,
    this.isLoading = false,
    this.isError = false,
  });
}

// ─── Gemini Servisi ──────────────────────────────────────────────────────────

/// Gemini Flash 2.0 API entegrasyonu.
/// Konuşma geçmişini dahili olarak yönetir.
/// Firestore araçları (rezervasyon işlemleri) bu sınıf içinde tanımlanmıştır.
class GeminiService {
  GeminiService({
    required this.orgProfile,
    required this.services,
    required this.bookingApiService,
    required this.bookingSettings,
    required this.workingHours,
    this.aiExtraContext,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final OrgPublicProfile orgProfile;
  final List<OrgService> services;
  final BookingApiService bookingApiService;
  final BookingSettings bookingSettings;
  final WorkingHours workingHours;
  /// Yönetici tarafından girilen kuruma özel talimatlar ve ek bilgiler.
  final String? aiExtraContext;
  final FirebaseFirestore _firestore;

  // Gemini REST API uç noktası
  static const _apiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent';

  // Dahili konuşma geçmişi (Gemini API formatında)
  final List<Map<String, dynamic>> _history = [];

  // Önbelleğe alınmış API anahtarı ve sistem promptu
  String? _apiKey;
  String? _systemPrompt;
  // Platform genelinde geçerli global prompt (sistem/ai_ayarlari)
  String? _globalPrompt;

  // ── Sohbet içi doğrulama durumu ─────────────────────────────────────────────
  String? _otpToken;           // OTP modu: gönderilen token
  String? _otpPhone;           // Doğrulama için saklanan telefon
  String? _verifiedPhone;      // Doğrulanmış telefon
  String? _verifiedName;       // Doğrulanmış müşteri adı
  DateTime? _customerBirthDate; // phone_birthdate modu: müşteri doğum tarihi

  // ── API Anahtarı ────────────────────────────────────────────────────────────

  /// API anahtarını yükler.
  /// Öncelik sırası:
  ///   1. --dart-define=GEMINI_API_KEY=... (web build / CI)
  ///   2. .env dosyası (native geliştirme ortamı)
  Future<String> _getApiKey() async {
    if (_apiKey != null) return _apiKey!;

    // Web build'e --dart-define ile gömülmüş anahtar
    const compiledKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
    if (compiledKey.isNotEmpty) {
      _apiKey = compiledKey;
      return _apiKey!;
    }

    // Native geliştirme: .env dosyasından yükle
    try {
      if (!dotenv.isInitialized) {
        await dotenv.load(fileName: '.env');
      }
      _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    } catch (_) {
      _apiKey = '';
    }
    return _apiKey!;
  }

  // ── Sistem Promptu ──────────────────────────────────────────────────────────

  /// Firestore'dan global talimatları çeker (sistem/ai_ayarlari).
  Future<String> _getGlobalPrompt() async {
    if (_globalPrompt != null) return _globalPrompt!;
    try {
      final doc =
          await _firestore.doc('sistem/ai_ayarlari').get();
      _globalPrompt =
          ((doc.data()?['globalSystemPrompt'] as String?) ?? '').trim();
    } catch (_) {
      _globalPrompt = '';
    }
    return _globalPrompt!;
  }

  /// Firestore'dan kampanyaları çekerek dinamik sistem promptu oluşturur.
  Future<String> _getSystemPrompt() async {
    if (_systemPrompt != null) return _systemPrompt!;

    // Platform geneli global talimatları çek
    final globalPrompt = await _getGlobalPrompt();

    // Aktif kampanyaları getir
    String kampanyaBloku = '';
    try {
      final kampSnap = await _firestore
          .collection('kurumlar')
          .doc(orgProfile.id)
          .collection('kampanyalar')
          .get();

      final aktif = kampSnap.docs.where((d) {
        final raw = d.data()['son_tarih'];
        if (raw == null) return true;
        try {
          final dt = (raw as dynamic).toDate() as DateTime;
          return dt.isAfter(DateTime.now());
        } catch (_) {
          return true;
        }
      }).toList();

      if (aktif.isNotEmpty) {
        kampanyaBloku = '\nAktif Kampanyalar:\n';
        for (final k in aktif) {
          final d = k.data();
          kampanyaBloku +=
              '- ${d['baslik'] ?? ''}: ${d['aciklama'] ?? ''}\n';
        }
      }
    } catch (_) {
      // Kampanya verisi alınamazsa sessizce devam et
    }

    // Hizmet listesi metni
    final hizmetler = services.map((s) {
      final fiyat =
          s.price != null ? ' (${s.price!.toStringAsFixed(0)} TL)' : '';
      final sure = ' – ${s.durationMinutes} dk';
      final aciklama = (s.description ?? '').isNotEmpty
          ? '\n    Açıklama: ${s.description}'
          : '';
      return '  • ${s.name}$fiyat$sure$aciklama';
    }).join('\n');

    // Çalışma saatleri özeti
    const gunAdi = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    final saatlerBloku = StringBuffer();
    for (var i = 1; i <= 7; i++) {
      final gun = workingHours.days[i];
      if (gun != null && gun.isOpen && gun.windows.isNotEmpty) {
        final aralik = gun.windows.map((w) => '${w.start}-${w.end}').join(', ');
        saatlerBloku.writeln('  ${gunAdi[i]}: $aralik');
      }
    }

    final bugun = DateTime.now();
    final bugunStr = '${bugun.day}.${bugun.month}.${bugun.year}';

    // Yönetici tarafından girilen özel talimatlar/ek bilgiler
    final extraBlok = (aiExtraContext ?? '').trim().isNotEmpty
        ? '\nKuruma Özel Bilgiler ve Talimatlar (bunları mutlaka dikkate al):\n'
            '${aiExtraContext!.trim()}\n'
        : '';

    // Platform geneli global talimatlar (admin tarafından belirlenir)
    final globalBlok = globalPrompt.isNotEmpty
        ? '\nPlatform Kuralları (her durumda uy):\n$globalPrompt\n'
        : '';

    final authModeStr = bookingSettings.authMode == 'otp' ? 'otp' : 'phone_birthdate';

    _systemPrompt = '''
Sen ${orgProfile.name} işletmesinin samimi ve yardımsever rezervasyon asistanısın.
Türkçe konuş. Kısa ve net cevaplar ver. Bugünün tarihi: $bugunStr.$globalBlok

${(orgProfile.address ?? '').isNotEmpty ? 'Adres: ${orgProfile.address}' : ''}
${(orgProfile.phone ?? '').isNotEmpty ? 'Telefon: ${orgProfile.phone}' : ''}

Çalışma Saatleri:
${saatlerBloku.toString().trim()}

Sunduğumuz Hizmetler:
$hizmetler
$kampanyaBloku$extraBlok
Görevin:
- Önce müşterinin ihtiyacını dinle, hizmetler hakkında bilgi ver, soruları cevapla.
- Hizmet açıklaması yoksa adından yola çıkarak kendi bilginle açıkla.
- Kuruma özel talimatlar varsa onlara uy; cihaz/makine bilgisi varsa kullan.
- Aktif kampanyaları uygun yerde belirt.
- Müşteri rezervasyon yapmak isteyince şu sırayı takip et:
  1. Telefon numarasını sor (10 hane, başında 0 olmadan).
  2. dogrulama_gonder ile telefonu gönder.
  ${authModeStr == 'otp' ? '''3. (OTP modu) Kullanıcıdan SMS kodunu iste, dogrulama_kontrol ile deger=kod olarak doğrula.
  4. Doğrulama başarılıysa: müşteri kayıtlıysa adını zaten bilirsin, kayıtlı değilse adını sor.''' : '''3. (Doğum tarihi modu) Yanıtta dogrulama_gerekli=true ise GG.AA.YYYY formatında doğum tarihini iste,
     dogrulama_kontrol ile deger=doğum_tarihi olarak doğrula.
     dogrulama_gerekli=false ise bu adımı atla (müşteri zaten tanındı).
  4. Doğrulama başarılıysa: müşteri kayıtlıysa adını zaten bilirsin, kayıtlı değilse adını sor.'''}
  5. Tarih sor → musait_saatleri_getir çağır → saati seç.
  6. Özet göster ve onayla → rezervasyon_olustur ile kaydet.
  7. SMS'in otomatik gideceğini belirt.
- Müşteri doğrulandıktan sonra paket sorarsa veya hangi hizmetlerin pakette olduğunu anlamak istersen danisan_paketleri_getir çağır.
- Rezervasyon sorgusu veya iptali için ilgili araçları kullan.
''';

    return _systemPrompt!;
  }

  // ── Mesaj Gönderme ──────────────────────────────────────────────────────────

  /// Kullanıcı mesajını konuşma geçmişine ekler ve Gemini'den yanıt alır.
  /// Fonksiyon çağrılarını otomatik olarak yönetir (maksimum 6 tur).
  Future<String> sendMessage(String userText) async {
    final apiKey = await _getApiKey();
    if (apiKey.isEmpty || apiKey == 'BURAYA_GEMINI_API_ANAHTARINIZI_GIRIN') {
      throw Exception(
          'Gemini API anahtarı bulunamadı.\n'
          'Lütfen .env dosyasındaki GEMINI_API_KEY değerini doldurun.');
    }

    final systemPrompt = await _getSystemPrompt();

    // Kullanıcı mesajını geçmişe ekle
    _history.add({
      'role': 'user',
      'parts': [
        {'text': userText}
      ],
    });

    // Araçlar (Gemini function declarations)
    final tools = [
      {
        'function_declarations': [
          _funcDecl(
            name: 'musait_saatleri_getir',
            description:
                'Belirtilen tarih ve hizmet için müsait randevu saatlerini getirir. '
                'Rezervasyon oluşturmadan önce mutlaka çağrılmalıdır.',
            properties: {
              'tarih': {
                'type': 'string',
                'description': 'Tarih (YYYY-MM-DD formatı, örn: 2024-03-15)',
              },
              'hizmet_adi': {
                'type': 'string',
                'description': 'İstenen hizmetin adı',
              },
            },
            required: ['tarih', 'hizmet_adi'],
          ),
          _funcDecl(
            name: 'rezervasyon_olustur',
            description:
                'Yeni bir randevu kaydeder. Önce musait_saatleri_getir ile '
                'müsait saat doğrulanmalıdır.',
            properties: {
              'ad_soyad': {
                'type': 'string',
                'description': 'Müşterinin adı ve soyadı',
              },
              'telefon': {
                'type': 'string',
                'description': '10 haneli telefon (başında 0 olmadan)',
              },
              'tarih': {
                'type': 'string',
                'description': 'Rezervasyon tarihi (YYYY-MM-DD)',
              },
              'saat': {
                'type': 'string',
                'description': 'Rezervasyon saati (HH:MM, örn: 10:30)',
              },
              'hizmet_adi': {
                'type': 'string',
                'description': 'Seçilen hizmetin adı',
              },
            },
            required: ['ad_soyad', 'telefon', 'tarih', 'saat', 'hizmet_adi'],
          ),
          _funcDecl(
            name: 'rezervasyon_sorgula',
            description:
                'Bir telefon numarasına ait mevcut rezervasyonları listeler.',
            properties: {
              'telefon': {
                'type': 'string',
                'description': '10 haneli telefon numarası',
              },
            },
            required: ['telefon'],
          ),
          _funcDecl(
            name: 'rezervasyon_iptal',
            description: 'Belirtilen ID\'ye sahip rezervasyonu iptal eder.',
            properties: {
              'rezervasyon_id': {
                'type': 'string',
                'description': 'İptal edilecek rezervasyonun Firestore doküman ID\'si',
              },
            },
            required: ['rezervasyon_id'],
          ),
          _funcDecl(
            name: 'danisan_paketleri_getir',
            description:
                'Doğrulanmış müşterinin aktif paketlerini ve kalan seans haklarını getirir. '
                'Müşteri doğrulandıktan sonra çağrılabilir.',
            properties: {},
            required: [],
          ),
          // ── OTP Doğrulama Araçları ──────────────────────────────────────────
          _funcDecl(
            name: 'dogrulama_gonder',
            description:
                'OTP modunda telefona SMS kodu gönderir. '
                'Doğum tarihi modunda müşteriyi sorgular ve doğum tarihi istenmesi gerekip gerekmediğini döner. '
                'Rezervasyon oluşturmadan önce mutlaka çağrılmalıdır.',
            properties: {
              'telefon': {
                'type': 'string',
                'description': '10 haneli telefon (başında 0 olmadan)',
              },
            },
            required: ['telefon'],
          ),
          _funcDecl(
            name: 'dogrulama_kontrol',
            description:
                'OTP modunda SMS kodunu, doğum tarihi modunda doğum tarihini doğrular ve müşteri kaydını sorgular.',
            properties: {
              'deger': {
                'type': 'string',
                'description':
                    'OTP modunda: kullanıcının girdiği SMS kodu. '
                    'Doğum tarihi modunda: GG.AA.YYYY formatında doğum tarihi.',
              },
            },
            required: ['deger'],
          ),
        ],
      }
    ];

    String finalText = '';

    // Maksimum 6 tur: metin yanıt alana kadar fonksiyon döngüsü
    for (var tur = 0; tur < 6; tur++) {
      final body = {
        'system_instruction': {
          'parts': [
            {'text': systemPrompt}
          ],
        },
        'contents': _history,
        'tools': tools,
        'generation_config': {
          'temperature': 0.75,
          'max_output_tokens': 1024,
        },
      };

      final resp = await http.post(
        Uri.parse('$_apiUrl?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (resp.statusCode != 200) {
        Map<String, dynamic> errJson = {};
        try {
          errJson = jsonDecode(resp.body) as Map<String, dynamic>;
        } catch (_) {}
        final msg =
            (errJson['error']?['message'] as String?) ?? 'Bilinmeyen hata';
        throw Exception('Gemini API hatası (${resp.statusCode}): $msg');
      }

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final candidates = (decoded['candidates'] as List?) ?? [];
      if (candidates.isEmpty) {
        throw Exception('Gemini yanıt vermedi. Lütfen tekrar deneyin.');
      }

      final content =
          candidates.first['content'] as Map<String, dynamic>? ?? {};
      final parts = (content['parts'] as List?) ?? [];

      // Fonksiyon çağrısı var mı?
      final fcPart = parts
          .cast<Map<String, dynamic>>()
          .where((p) => p.containsKey('functionCall'))
          .firstOrNull;

      if (fcPart != null) {
        final fc = fcPart['functionCall'] as Map<String, dynamic>;
        final funcName = fc['name'] as String;
        final funcArgs =
            (fc['args'] as Map<String, dynamic>?) ?? {};

        // Model fonksiyon çağrısını geçmişe ekle (thought_signature dahil tüm parts)
        _history.add({
          'role': 'model',
          'parts': parts,
        });

        // Fonksiyonu çalıştır
        final sonuc = await _executeFunction(funcName, funcArgs);

        // Fonksiyon sonucunu geçmişe ekle (user rolüyle)
        _history.add({
          'role': 'user',
          'parts': [
            {
              'functionResponse': {
                'name': funcName,
                'response': {'result': sonuc},
              }
            }
          ],
        });

        continue; // Tekrar Gemini'ye gönder
      }

      // Metin yanıtı al
      finalText = parts
          .cast<Map<String, dynamic>>()
          .where((p) => p.containsKey('text'))
          .map((p) => p['text'] as String)
          .join('');

      // Model yanıtını geçmişe ekle
      _history.add({
        'role': 'model',
        'parts': parts,
      });

      break;
    }

    return finalText.isNotEmpty
        ? finalText
        : 'Üzgünüm, bir sorun oluştu. Lütfen tekrar deneyin.';
  }

  /// Konuşma geçmişini sıfırlar (yeni sohbet başlatır).
  void resetConversation() {
    _history.clear();
    // Sistem promptunu koru, konuşma geçmişini temizle
  }

  // ── Fonksiyon Çalıştırıcı ──────────────────────────────────────────────────

  Future<dynamic> _executeFunction(
      String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'musait_saatleri_getir':
        return _musaitSaatleriGetir(args);
      case 'rezervasyon_olustur':
        return _rezervasyonOlustur(args);
      case 'rezervasyon_sorgula':
        return _rezervasyonSorgula(args);
      case 'rezervasyon_iptal':
        return _rezervasyonIptal(args);
      case 'danisan_paketleri_getir':
        return _danisanPaketleriGetir();
      case 'dogrulama_gonder':
        return _dogrulamaGonder(args);
      case 'dogrulama_kontrol':
        return _dogrulamaKontrol(args);
      default:
        return {'hata': 'Bilinmeyen fonksiyon: $name'};
    }
  }

  // ── Araç: Müsait Saatler ───────────────────────────────────────────────────

  Future<dynamic> _musaitSaatleriGetir(Map<String, dynamic> args) async {
    final tarihStr = (args['tarih'] as String?) ?? '';
    final hizmetAdi = (args['hizmet_adi'] as String?) ?? '';

    final tarih = DateTime.tryParse(tarihStr);
    if (tarih == null) {
      return {'hata': 'Geçersiz tarih formatı. YYYY-MM-DD kullanın.'};
    }

    // Hizmet adından eşleştir
    final service = _hizmetBul(hizmetAdi) ??
        (services.isNotEmpty ? services.first : null);
    if (service == null) {
      return {'hata': 'Hizmet listesi boş veya hizmet bulunamadı.'};
    }

    try {
      final slots = await bookingApiService.fetchAvailability(
        query: AvailabilityQuery(
          orgId: orgProfile.id,
          serviceId: service.id,
          date: tarih,
          mekanIds: service.mekanIds,
        ),
        settings: bookingSettings,
        workingHours: workingHours,
        service: service,
      );

      if (slots.isEmpty) {
        return {
          'musait_saatler': <String>[],
          'hizmet': service.name,
          'mesaj': 'Bu tarihte müsait randevu saati bulunmuyor.',
        };
      }

      return {
        'musait_saatler': slots.map((s) => s.label).toList(),
        'hizmet': service.name,
        'sure': '${service.durationMinutes} dakika',
      };
    } catch (e) {
      return {'hata': 'Müsait saatler alınırken hata oluştu: $e'};
    }
  }

  // ── Araç: Doğrulama Gönder ─────────────────────────────────────────────────

  Future<dynamic> _dogrulamaGonder(Map<String, dynamic> args) async {
    final telefon = ((args['telefon'] as String?) ?? '').trim();
    if (telefon.isEmpty) return {'hata': 'Telefon numarası gerekli.'};

    final normalTelefon = _telefonNormalize(telefon);
    _otpPhone = normalTelefon;

    // ── OTP modu: SMS gönder ──────────────────────────────────────────────────
    if (bookingSettings.authMode == 'otp') {
      try {
        final service = SmsOtpPhoneVerificationService(
          orgId: orgProfile.id,
          orgName: orgProfile.name,
        );
        _otpToken = await service.requestCode(normalTelefon);
        return {
          'basarili': true,
          'mod': 'otp',
          'mesaj': 'Doğrulama kodu $telefon numarasına gönderildi. Kodu sorun.',
        };
      } catch (e) {
        _otpToken = null;
        _otpPhone = null;
        return {'hata': 'Kod gönderilemedi: ${e.toString().replaceAll('Exception: ', '')}'};
      }
    }

    // ── Doğum tarihi modu: müşteriyi sorgula ─────────────────────────────────
    try {
      final qSnap = await _firestore
          .collection('kurumlar')
          .doc(orgProfile.id)
          .collection('danisanlar')
          .where('telefon', isEqualTo: normalTelefon)
          .limit(1)
          .get();

      if (qSnap.docs.isNotEmpty) {
        final d = qSnap.docs.first.data();
        final dogumStr = (d['dogumtarihi'] as String?) ?? '';
        if (dogumStr.isNotEmpty) {
          // Doğum tarihi kayıtlı — doğrulama gerekli
          _otpToken = 'birthdate_required';
          try {
            _customerBirthDate = DateTime.parse(dogumStr);
          } catch (_) {
            _customerBirthDate = null;
          }
          return {
            'basarili': true,
            'mod': 'dogum_tarihi',
            'dogrulama_gerekli': true,
            'mesaj': 'Kayıtlı müşteri bulundu. Doğum tarihini GG.AA.YYYY formatında isteyin.',
          };
        } else {
          // Kayıtlı ama doğum tarihi yok — doğrudan geç
          _otpToken = 'birthdate_skip';
          _verifiedPhone = normalTelefon;
          final ad = (d['adi'] ?? '').toString().trim();
          final soyad = (d['soyadi'] ?? '').toString().trim();
          _verifiedName = '$ad $soyad'.trim();
          return {
            'basarili': true,
            'mod': 'dogum_tarihi',
            'dogrulama_gerekli': false,
            'musteri_kayitli': true,
            'ad_soyad': _verifiedName,
            'mesaj': 'Kayıtlı müşteri: $_verifiedName. Doğrulama atlandı.',
          };
        }
      } else {
        // Yeni müşteri — doğrulama gerekmez
        _otpToken = 'birthdate_skip';
        _verifiedPhone = normalTelefon;
        _verifiedName = null;
        return {
          'basarili': true,
          'mod': 'dogum_tarihi',
          'dogrulama_gerekli': false,
          'musteri_kayitli': false,
          'mesaj': 'Yeni müşteri. Adını sorun.',
        };
      }
    } catch (e) {
      return {'hata': 'Müşteri sorgulanamadı: ${e.toString()}'};
    }
  }

  // ── Araç: Doğrulama Kontrol ─────────────────────────────────────────────────

  Future<dynamic> _dogrulamaKontrol(Map<String, dynamic> args) async {
    final deger = ((args['deger'] as String?) ?? '').trim();
    if (deger.isEmpty) return {'hata': 'Değer gerekli.'};

    if (_otpToken == null || _otpPhone == null) {
      return {'hata': 'Önce dogrulama_gonder çağrılmalıdır.'};
    }

    // ── OTP modu ─────────────────────────────────────────────────────────────
    if (bookingSettings.authMode == 'otp') {
      final service = SmsOtpPhoneVerificationService(
        orgId: orgProfile.id,
        orgName: orgProfile.name,
      );
      final ok = await service.verifyCode(
        verificationToken: _otpToken!,
        smsCode: deger,
      );
      if (!ok) return {'hata': 'Kod hatalı. Lütfen tekrar deneyin.'};
      return await _musteriyiDogrula();
    }

    // ── Doğum tarihi modu ────────────────────────────────────────────────────
    if (_otpToken == 'birthdate_skip') {
      // Doğrulama atlanmış (yeni müşteri veya doğum tarihi yok)
      return await _musteriyiDogrula();
    }

    // Doğum tarihini parse et (GG.AA.YYYY)
    DateTime? girilenTarih;
    try {
      final parts = deger.split('.');
      if (parts.length == 3) {
        girilenTarih = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }
    } catch (_) {}

    if (girilenTarih == null) {
      return {'hata': 'Geçersiz tarih formatı. GG.AA.YYYY şeklinde girin.'};
    }

    if (_customerBirthDate == null ||
        girilenTarih.year != _customerBirthDate!.year ||
        girilenTarih.month != _customerBirthDate!.month ||
        girilenTarih.day != _customerBirthDate!.day) {
      return {'hata': 'Doğum tarihi eşleşmiyor. Lütfen tekrar deneyin.'};
    }

    return await _musteriyiDogrula();
  }

  /// Doğrulama başarılı — müşteriyi Firestore'da ara ve sonucu döndür.
  Future<Map<String, dynamic>> _musteriyiDogrula() async {
    _verifiedPhone = _otpPhone;
    try {
      final qSnap = await _firestore
          .collection('kurumlar')
          .doc(orgProfile.id)
          .collection('danisanlar')
          .where('telefon', isEqualTo: _otpPhone!)
          .limit(1)
          .get();

      if (qSnap.docs.isNotEmpty) {
        final d = qSnap.docs.first.data();
        final ad = (d['adi'] ?? '').toString().trim();
        final soyad = (d['soyadi'] ?? '').toString().trim();
        _verifiedName = '$ad $soyad'.trim();
        return {
          'basarili': true,
          'musteri_kayitli': true,
          'ad_soyad': _verifiedName,
          'telefon': _verifiedPhone,
          'mesaj': 'Doğrulama başarılı. Kayıtlı müşteri: $_verifiedName',
        };
      } else {
        _verifiedName = null;
        return {
          'basarili': true,
          'musteri_kayitli': false,
          'telefon': _verifiedPhone,
          'mesaj': 'Doğrulama başarılı. Kayıtlı müşteri bulunamadı, adını sor.',
        };
      }
    } catch (_) {
      return {
        'basarili': true,
        'musteri_kayitli': false,
        'telefon': _verifiedPhone,
      };
    }
  }

  // ── Araç: Danışan Paketleri ─────────────────────────────────────────────────

  Future<dynamic> _danisanPaketleriGetir() async {
    if (_verifiedPhone == null) {
      return {'hata': 'Önce müşteri doğrulanmalıdır.'};
    }

    // Doğrulanmış telefona göre danışan ID'sini bul
    String? danisanId;
    try {
      final qSnap = await _firestore
          .collection('kurumlar')
          .doc(orgProfile.id)
          .collection('danisanlar')
          .where('telefon', isEqualTo: _verifiedPhone!)
          .limit(1)
          .get();
      if (qSnap.docs.isEmpty) {
        return {'mesaj': 'Kayıtlı müşteri bulunamadı, aktif paket yok.'};
      }
      danisanId = qSnap.docs.first.id;
    } catch (e) {
      return {'hata': 'Müşteri sorgulanamadı: $e'};
    }

    // Paketleri getir
    try {
      final paketSnap = await _firestore
          .collection('kurumlar')
          .doc(orgProfile.id)
          .collection('danisanlar')
          .doc(danisanId)
          .collection('paketler')
          .get();

      if (paketSnap.docs.isEmpty) {
        return {'mesaj': 'Aktif paket bulunmuyor.'};
      }

      final now = DateTime.now();
      final paketler = <Map<String, dynamic>>[];

      for (final doc in paketSnap.docs) {
        final d = doc.data();
        final durum = (d['durum'] ?? '').toString();
        final suresiz = d['suresiz'] == true;
        final bitisTarihi = d['bitisTarihi'];
        DateTime? bitis;
        if (bitisTarihi != null) {
          try {
            bitis = (bitisTarihi as dynamic).toDate() as DateTime;
          } catch (_) {}
        }

        // Süresi dolmuş paketleri atla
        if (!suresiz && bitis != null && bitis.isBefore(now)) continue;
        if (durum == 'iptal' || durum == 'tamamlandi') continue;

        final islemler = d['islemler'];
        int toplamSeans = 0;
        int kullanilanSeans = 0;
        final islemListesi = <String>[];

        if (islemler is List) {
          for (final i in islemler) {
            if (i is Map) {
              final sinirsiz = i['sinirsiz'] == true;
              final toplam = (i['seansSayisi'] as num?)?.toInt() ?? 0;
              final yapilan = (i['yapilanSeans'] as num?)?.toInt() ?? 0;
              final kalan = (i['kalanSeans'] as num?)?.toInt() ?? (toplam - yapilan);
              final ad = (i['islemAdi'] ?? '').toString();
              if (!sinirsiz) {
                toplamSeans += toplam;
                kullanilanSeans += yapilan;
                islemListesi.add('$ad: $kalan seans kaldı (toplam $toplam)');
              } else {
                islemListesi.add('$ad: sınırsız');
              }
            }
          }
        }

        paketler.add({
          'paket_adi': (d['paketAdi'] ?? '').toString(),
          'durum': durum.isEmpty ? 'aktif' : durum,
          'bitis_tarihi': bitis != null
              ? '${bitis.day}.${bitis.month}.${bitis.year}'
              : 'süresi yok',
          'kalan_seans': toplamSeans > 0 ? toplamSeans - kullanilanSeans : null,
          'islemler': islemListesi,
        });
      }

      if (paketler.isEmpty) {
        return {'mesaj': 'Aktif paket bulunmuyor.'};
      }

      return {'paketler': paketler, 'toplam': paketler.length};
    } catch (e) {
      return {'hata': 'Paketler getirilemedi: $e'};
    }
  }

  // ── Araç: Rezervasyon Oluştur ──────────────────────────────────────────────

  Future<dynamic> _rezervasyonOlustur(Map<String, dynamic> args) async {
    var adSoyad = ((args['ad_soyad'] as String?) ?? '').trim();
    var telefon = ((args['telefon'] as String?) ?? '').trim();
    final tarihStr = (args['tarih'] as String?) ?? '';
    final saatStr = (args['saat'] as String?) ?? '';
    final hizmetAdi = (args['hizmet_adi'] as String?) ?? '';

    // Doğrulanmış bilgileri öncelikli kullan
    if (_verifiedPhone != null && _verifiedPhone!.isNotEmpty) {
      telefon = _verifiedPhone!;
    }
    if (_verifiedName != null && _verifiedName!.isNotEmpty && adSoyad.isEmpty) {
      adSoyad = _verifiedName!;
    }

    if (adSoyad.isEmpty || telefon.isEmpty || tarihStr.isEmpty || saatStr.isEmpty) {
      return {'hata': 'Eksik bilgi: ad soyad, telefon, tarih ve saat zorunlu.'};
    }

    final tarih = DateTime.tryParse(tarihStr);
    if (tarih == null) return {'hata': 'Geçersiz tarih formatı.'};

    final saatParts = saatStr.split(':');
    if (saatParts.length != 2) {
      return {'hata': 'Geçersiz saat formatı. HH:MM kullanın.'};
    }
    final saat = int.tryParse(saatParts[0]);
    final dakika = int.tryParse(saatParts[1]);
    if (saat == null || dakika == null) return {'hata': 'Geçersiz saat değeri.'};

    final startTime =
        DateTime(tarih.year, tarih.month, tarih.day, saat, dakika);

    // Hizmet bul
    final service = _hizmetBul(hizmetAdi) ??
        (services.isNotEmpty ? services.first : null);
    if (service == null) return {'hata': 'Hizmet bulunamadı.'};

    final endTime = startTime.add(Duration(minutes: service.durationMinutes));
    final normalTelefon = _telefonNormalize(telefon);

    // Müşteri bul veya oluştur
    String customerId;
    try {
      final qSnap = await _firestore
          .collection('kurumlar')
          .doc(orgProfile.id)
          .collection('danisanlar')
          .where('telefon', isEqualTo: normalTelefon)
          .limit(1)
          .get();

      if (qSnap.docs.isNotEmpty) {
        customerId = qSnap.docs.first.id;
      } else {
        // Yeni müşteri kaydı oluştur
        final parcalar =
            adSoyad.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
        final adi = parcalar.isNotEmpty ? parcalar.first : adSoyad;
        final soyadi =
            parcalar.length > 1 ? parcalar.sublist(1).join(' ') : '';

        final yeniDoc = await _firestore
            .collection('kurumlar')
            .doc(orgProfile.id)
            .collection('danisanlar')
            .add({
          'adi': adi,
          'soyadi': soyadi,
          'telefon': normalTelefon,
          'createdAt': FieldValue.serverTimestamp(),
          'kaynak': 'ai_asistan',
        });
        customerId = yeniDoc.id;
      }
    } catch (_) {
      customerId = 'ai_${DateTime.now().millisecondsSinceEpoch}';
    }

    // Hizmetin mekanını al (tablo görünümünde lokasyon zorunlu)
    String? mekanId;
    try {
      if (service.mekanIds.isNotEmpty) {
        // Hizmetin kendi mekanu varsa ilkini kullan
        mekanId = service.mekanIds.first;
      } else {
        // Hizmete özel mekan yoksa kurumun ilk mekanını al
        final mekanSnap = await _firestore
            .collection('kurumlar')
            .doc(orgProfile.id)
            .collection('mekanlar')
            .limit(1)
            .get();
        if (mekanSnap.docs.isNotEmpty) {
          mekanId = mekanSnap.docs.first.id;
        }
      }
    } catch (_) {}

    // Rezervasyonu oluştur
    try {
      final draft = BookingDraft(
        orgId: orgProfile.id,
        customerId: customerId,
        customerName: adSoyad,
        customerPhone: normalTelefon,
        serviceId: service.id,
        serviceName: service.name,
        bookingDate: startTime,
        startTime: startTime,
        endTime: endTime,
        mekanId: mekanId,
        source: 'ai_asistan',
        notes: 'AI Asistan üzerinden oluşturuldu.',
      );

      final bookingId = await bookingApiService.createBooking(draft);

      // Rezervasyon oluşturuldu — o günün cache'ini temizle ki tekrar sorgulansın
      bookingApiService.invalidateCacheForDate(orgProfile.id, startTime);

      return {
        'basarili': true,
        'rezervasyon_id': bookingId,
        'ozet': {
          'ad_soyad': adSoyad,
          'telefon': telefon,
          'tarih': '${tarih.day}.${tarih.month}.${tarih.year}',
          'saat': saatStr,
          'hizmet': service.name,
          'sure': '${service.durationMinutes} dakika',
        },
        'bilgi': 'SMS otomatik olarak gönderilecek.',
      };
    } catch (e) {
      return {
        'hata': 'Rezervasyon oluşturulamadı: '
            '${e.toString().replaceAll('Exception: ', '')}'
      };
    }
  }

  // ── Araç: Rezervasyon Sorgula ──────────────────────────────────────────────

  Future<dynamic> _rezervasyonSorgula(Map<String, dynamic> args) async {
    final telefon = ((args['telefon'] as String?) ?? '').trim();
    if (telefon.isEmpty) return {'hata': 'Telefon numarası gerekli.'};

    try {
      final normalTelefon = _telefonNormalize(telefon);
      final snap = await _firestore
          .collection('kurumlar')
          .doc(orgProfile.id)
          .collection('rezervasyonlar')
          .where('customerPhone',
              whereIn: [normalTelefon, '0$normalTelefon'])
          .orderBy('date', descending: true)
          .limit(5)
          .get();

      if (snap.docs.isEmpty) {
        return {
          'rezervasyonlar': <dynamic>[],
          'mesaj': 'Bu numaraya ait rezervasyon bulunamadı.',
        };
      }

      final liste = snap.docs.map((doc) {
        final d = doc.data();
        DateTime? dt;
        try {
          dt = (d['date'] as dynamic).toDate() as DateTime;
        } catch (_) {}
        final tarihStr = dt != null
            ? '${dt.day}.${dt.month}.${dt.year} '
                '${dt.hour.toString().padLeft(2, '0')}:'
                '${dt.minute.toString().padLeft(2, '0')}'
            : '—';
        return {
          'id': doc.id,
          'tarih': tarihStr,
          'hizmet': d['operationName'] ?? '',
          'durum': d['status'] ?? '',
          'musteri': d['customerName'] ?? '',
        };
      }).toList();

      return {'rezervasyonlar': liste};
    } catch (e) {
      return {'hata': 'Rezervasyonlar sorgulanırken hata: $e'};
    }
  }

  // ── Araç: Rezervasyon İptal ────────────────────────────────────────────────

  Future<dynamic> _rezervasyonIptal(Map<String, dynamic> args) async {
    final rid = ((args['rezervasyon_id'] as String?) ?? '').trim();
    if (rid.isEmpty) return {'hata': 'Rezervasyon ID gerekli.'};

    try {
      await _firestore
          .collection('kurumlar')
          .doc(orgProfile.id)
          .collection('rezervasyonlar')
          .doc(rid)
          .update({'status': 'iptal'});

      return {'basarili': true, 'mesaj': 'Rezervasyon iptal edildi.'};
    } catch (e) {
      return {'hata': 'İptal sırasında hata: $e'};
    }
  }

  // ── Yardımcı Metodlar ──────────────────────────────────────────────────────

  /// Hizmet adından OrgService bul (tam veya kısmi eşleşme).
  OrgService? _hizmetBul(String hizmetAdi) {
    if (hizmetAdi.isEmpty) return null;
    final lower = hizmetAdi.toLowerCase().trim();
    // Tam eşleşme önce
    final exact =
        services.where((s) => s.name.toLowerCase() == lower).firstOrNull;
    if (exact != null) return exact;
    // Kısmi eşleşme
    return services
        .where((s) =>
            s.name.toLowerCase().contains(lower) ||
            lower.contains(s.name.toLowerCase()))
        .firstOrNull;
  }

  /// Telefon numarasını +905XXXXXXXXX formatına normalleştirir.
  /// Firestore'daki kayıtlarla uyumlu olması için danisan_ekle ile aynı format kullanılır.
  String _telefonNormalize(String telefon) {
    var digits = telefon.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('90')) {
      // zaten ülke koduyla başlıyor
    } else if (digits.startsWith('0')) {
      digits = digits.substring(1);
      digits = '90$digits';
    } else {
      digits = '90$digits';
    }
    return '+$digits';
  }

  /// Gemini function declaration nesnesi oluşturur.
  Map<String, dynamic> _funcDecl({
    required String name,
    required String description,
    required Map<String, dynamic> properties,
    required List<String> required,
  }) {
    return {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': required,
      },
    };
  }
}
