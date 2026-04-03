import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Firebase Cloud Messaging token yönetimi.
/// Kullanıcı giriş yaptıktan sonra [init] çağrılmalıdır.
/// Token Firestore'daki kullanıcı belgesine `fcmToken` alanı olarak kaydedilir.
class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static void _log(String message, [Map<String, Object?> data = const {}]) {
    if (data.isEmpty) {
      debugPrint('[FCM] $message');
      return;
    }
    final details = data.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' | ');
    debugPrint('[FCM] $message | $details');
  }

  /// [userId]: Firestore'daki kullanıcı belge ID'si (email).
  static Future<void> init(String userId) async {
    if (userId.isEmpty) {
      _log('init iptal: userId boş');
      return;
    }
    if (kIsWeb) {
      _log('init atlandı: web platformu');
      return;
    }

    try {
      _log('init başladı', {'userId': userId});
      // iOS / macOS için bildirim izni iste.
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _log('izin sonucu', {
        'userId': userId,
        'authorizationStatus': settings.authorizationStatus.name,
      });
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _log('init durdu: bildirim izni reddedildi', {'userId': userId});
        return;
      }

      // Token al ve kaydet.
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveToken(userId, token);
      } else {
        _log('getToken boş döndü', {'userId': userId});
      }

      // Token yenilendiğinde güncelle.
      _messaging.onTokenRefresh.listen((newToken) {
        _log('onTokenRefresh', {
          'userId': userId,
          'tokenLength': newToken.length,
        });
        _saveToken(userId, newToken);
      });

      // Uygulama ön plandayken gelen mesajları logla.
      // (Görsel bildirim için flutter_local_notifications eklenebilir.)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _log('Foreground mesaj', {
          'messageId': message.messageId ?? '-',
          'title': message.notification?.title ?? '-',
          'body': message.notification?.body ?? '-',
          'data': message.data.toString(),
        });
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _log('onMessageOpenedApp', {
          'messageId': message.messageId ?? '-',
          'data': message.data.toString(),
        });
      });

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _log('getInitialMessage bulundu', {
          'messageId': initialMessage.messageId ?? '-',
          'data': initialMessage.data.toString(),
        });
      } else {
        _log('getInitialMessage yok');
      }
    } catch (e) {
      _log('init hatası', {'error': e.toString()});
    }
  }

  static Future<void> _saveToken(String userId, String token) async {
    try {
      await FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(userId)
          .update({'fcmToken': token});
      _log('Token kaydedildi', {
        'userId': userId,
        'tokenLength': token.length,
      });
    } catch (e) {
      _log('Token kayıt hatası', {
        'userId': userId,
        'error': e.toString(),
      });
    }
  }
}
