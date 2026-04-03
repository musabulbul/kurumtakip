import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kurum_takip/utils/permission_utils.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class AppNotification {
  const AppNotification({
    required this.id,
    required this.baslik,
    required this.mesaj,
    required this.tip,
    required this.okundu,
    required this.tarih,
    this.veri,
  });

  final String id;

  /// Kısa başlık, örn. "Yeni Rezervasyon".
  final String baslik;

  /// Açıklama metni.
  final String mesaj;

  /// 'rezervasyon' | 'atama' | ...
  final String tip;

  final bool okundu;
  final DateTime tarih;

  /// İsteğe bağlı ek veri (rezervasyonId, danisanId, vb.).
  final Map<String, dynamic>? veri;

  factory AppNotification.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data();
    return AppNotification(
      id: snap.id,
      baslik: (data['baslik'] as String?) ?? '',
      mesaj: (data['mesaj'] as String?) ?? '',
      tip: (data['tip'] as String?) ?? '',
      okundu: (data['okundu'] as bool?) ?? false,
      tarih: (data['tarih'] as Timestamp?)?.toDate() ?? DateTime.now(),
      veri: data['veri'] as Map<String, dynamic>?,
    );
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────

class NotificationService {
  NotificationService({FirebaseFirestore? firestore, String? notifUrl})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _notifUrl = notifUrl ?? const String.fromEnvironment('NOTIFICATION_URL');

  final FirebaseFirestore _firestore;
  final String _notifUrl;

  void _log(String message, [Map<String, Object?> data = const {}]) {
    if (data.isEmpty) {
      debugPrint('[Notif] $message');
      return;
    }
    final details = data.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' | ');
    debugPrint('[Notif] $message | $details');
  }

  Map<String, Object?> _permissionDebug(dynamic userData) {
    final map = userData is Map ? userData : const {};
    final rawPerms = map['yetkiler'];
    final perms = rawPerms is Iterable
        ? rawPerms.map((e) => e?.toString()).whereType<String>().toList()
        : <String>[];
    return {
      'rol': (map['rol'] ?? '').toString(),
      'impersonated': map['impersonated'] == true,
      'isManagerUser': isManagerUser(map),
      'canReceiveAll': canReceiveAllReservationNotifications(map),
      'canReceiveAssigned': canReceiveAssignedReservationNotifications(map),
      'yetkiler': perms.join(','),
    };
  }

  CollectionReference<Map<String, dynamic>> _ref(String userId) =>
      _firestore.collection('kullanicilar').doc(userId).collection('bildirimler');

  bool _isSameUser(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String userId,
  ) {
    final target = userId.trim();
    if (target.isEmpty) return false;
    if (doc.id == target) return true;
    final data = doc.data();
    final uid = (data['uid'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();
    return uid == target || email == target;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _queryInstitutionUsers(
    String kurumkodu,
  ) async {
    final byKurumKodu = await _firestore
        .collection('kullanicilar')
        .where('kurumkodu', isEqualTo: kurumkodu)
        .get();

    // Bazı eski/yeni kayıtlarda kurum alanı orgId olarak tutulabiliyor.
    final byOrgId = await _firestore
        .collection('kullanicilar')
        .where('orgId', isEqualTo: kurumkodu)
        .get();

    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in byKurumKodu.docs) {
      byId[doc.id] = doc;
    }
    for (final doc in byOrgId.docs) {
      byId[doc.id] = doc;
    }
    return byId.values.toList(growable: false);
  }

  /// Rezervasyon açılış bildirimi ve atama bildirimi alıcılarını
  /// kullanıcı yetkilerine göre belirleyerek gönderir.
  Future<void> sendBookingNotifications({
    required String kurumkodu,
    required String reservationTitle,
    required String reservationMessage,
    required String assignmentTitle,
    required String assignmentMessage,
    required String reservationType,
    String assignmentType = 'atama',
    String? excludeUserId,
    String? assignedUserId,
    Map<String, dynamic>? veri,
  }) async {
    final trimmedKurumkodu = kurumkodu.trim();
    if (trimmedKurumkodu.isEmpty) {
      _log('sendBookingNotifications iptal: kurumkodu boş');
      return;
    }

    _log('sendBookingNotifications başladı', {
      'kurumkodu': trimmedKurumkodu,
      'excludeUserId': excludeUserId ?? '-',
      'assignedUserId': (assignedUserId ?? '').trim(),
      'notifUrlSet': _notifUrl.isNotEmpty,
      'veriKeys': veri?.keys.join(',') ?? '-',
    });

    try {
      final docs = await _queryInstitutionUsers(trimmedKurumkodu);
      _log('kurum kullanıcıları yüklendi', {'count': docs.length});
      final recipients = <String>{};

      for (final doc in docs) {
        if (excludeUserId != null && _isSameUser(doc, excludeUserId)) {
          _log('alıcı atlandı: tetikleyen kullanıcı', {'docId': doc.id});
          continue;
        }
        final data = doc.data();
        final canReceiveAll = canReceiveAllReservationNotifications(data);
        _log('alıcı kontrolü', {
          'docId': doc.id,
          'canReceiveAll': canReceiveAll,
        });
        if (canReceiveAll) {
          recipients.add(doc.id);
        }
      }

      final futures = <Future<void>>[];
      for (final userId in recipients) {
        futures.add(
          sendToUser(
            userId: userId,
            baslik: reservationTitle,
            mesaj: reservationMessage,
            tip: reservationType,
            veri: veri,
          ),
        );
      }

      final assignedCandidate = (assignedUserId ?? '').trim();
      if (assignedCandidate.isNotEmpty) {
        QueryDocumentSnapshot<Map<String, dynamic>>? assignedDoc;
        for (final doc in docs) {
          if (_isSameUser(doc, assignedCandidate)) {
            assignedDoc = doc;
            break;
          }
        }

        if (assignedDoc != null &&
            (excludeUserId == null || !_isSameUser(assignedDoc, excludeUserId)) &&
            !recipients.contains(assignedDoc.id) &&
            canReceiveAssignedReservationNotifications(assignedDoc.data())) {
          _log('atanan kullanıcıya özel bildirim eklendi', {
            'docId': assignedDoc.id,
          });
          futures.add(
            sendToUser(
              userId: assignedDoc.id,
              baslik: assignmentTitle,
              mesaj: assignmentMessage,
              tip: assignmentType,
              veri: veri,
            ),
          );
        } else {
          _log('atanan kullanıcıya özel bildirim gönderilmedi', {
            'assignedCandidate': assignedCandidate,
            'assignedFound': assignedDoc != null,
            'alreadyRecipient': assignedDoc != null && recipients.contains(assignedDoc.id),
          });
        }
      }

      _log('gönderim başlatıldı', {'recipientCount': futures.length});
      await Future.wait(futures);
      _log('sendBookingNotifications tamamlandı', {
        'recipientCount': futures.length,
      });
    } catch (e, st) {
      _log('sendBookingNotifications HATA', {
        'error': e.toString(),
        'stack': st.toString(),
      });
    }
  }

  /// Tekil kullanıcı için "kendine atanan görev" bildirim yetkisini kontrol eder.
  Future<bool> canReceiveAssignmentNotification({
    required String userId,
  }) async {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) {
      _log('canReceiveAssignmentNotification iptal: userId boş');
      return false;
    }
    _log('canReceiveAssignmentNotification başladı', {'userId': trimmed});
    try {
      final doc = await _firestore.collection('kullanicilar').doc(trimmed).get();
      if (doc.exists) {
        final allowed = canReceiveAssignedReservationNotifications(doc.data());
        _log('canReceiveAssignmentNotification doc detay', {
          'userId': trimmed,
          ..._permissionDebug(doc.data()),
        });
        _log('canReceiveAssignmentNotification docId sonucu', {
          'userId': trimmed,
          'allowed': allowed,
        });
        return allowed;
      }

      final uidQuery = await _firestore
          .collection('kullanicilar')
          .where('uid', isEqualTo: trimmed)
          .limit(1)
          .get();
      if (uidQuery.docs.isNotEmpty) {
        final allowed =
            canReceiveAssignedReservationNotifications(uidQuery.docs.first.data());
        _log('canReceiveAssignmentNotification uid detay', {
          'userId': uidQuery.docs.first.id,
          ..._permissionDebug(uidQuery.docs.first.data()),
        });
        _log('canReceiveAssignmentNotification uid sonucu', {
          'userId': uidQuery.docs.first.id,
          'allowed': allowed,
        });
        return allowed;
      }

      final emailQuery = await _firestore
          .collection('kullanicilar')
          .where('email', isEqualTo: trimmed)
          .limit(1)
          .get();
      if (emailQuery.docs.isNotEmpty) {
        final allowed =
            canReceiveAssignedReservationNotifications(emailQuery.docs.first.data());
        _log('canReceiveAssignmentNotification email detay', {
          'userId': emailQuery.docs.first.id,
          ..._permissionDebug(emailQuery.docs.first.data()),
        });
        _log('canReceiveAssignmentNotification email sonucu', {
          'userId': emailQuery.docs.first.id,
          'allowed': allowed,
        });
        return allowed;
      }
      _log('canReceiveAssignmentNotification kullanıcı bulunamadı', {'userId': trimmed});
      return false;
    } catch (e) {
      _log('canReceiveAssignmentNotification hata', {
        'userId': trimmed,
        'error': e.toString(),
      });
      return false;
    }
  }

  /// Belirli bir kullanıcıya bildirim gönderir.
  Future<void> sendToUser({
    required String userId,
    required String baslik,
    required String mesaj,
    required String tip,
    Map<String, dynamic>? veri,
  }) async {
    if (userId.isEmpty) {
      _log('sendToUser iptal: userId boş');
      return;
    }
    _log('sendToUser başladı', {
      'uid': userId,
      'tip': tip,
      'baslik': baslik,
      'veriKeys': veri?.keys.join(',') ?? '-',
    });
    try {
      final docRef = await _ref(userId).add({
        'baslik': baslik,
        'mesaj': mesaj,
        'tip': tip,
        'okundu': false,
        'tarih': FieldValue.serverTimestamp(),
        if (veri != null) 'veri': veri,
      });
      _log('sendToUser Firestore yazıldı', {
        'uid': userId,
        'notifDocId': docRef.id,
      });
      // Firestore yazıldıktan sonra FCM push gönder.
      if (_notifUrl.isNotEmpty) {
        _sendFcm(userId: userId, baslik: baslik, mesaj: mesaj).ignore();
      } else {
        _log('sendToUser push atlandı: NOTIFICATION_URL boş', {'uid': userId});
      }
    } catch (e, st) {
      _log('sendToUser HATA', {
        'uid': userId,
        'error': e.toString(),
        'stack': st.toString(),
      });
    }
  }

  Future<void> _sendFcm({
    required String userId,
    required String baslik,
    required String mesaj,
  }) async {
    try {
      final endpoint = '$_notifUrl/send-fcm';
      _log('_sendFcm başladı', {
        'uid': userId,
        'endpoint': endpoint,
      });
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'title': baslik, 'body': mesaj}),
      );
      final responseBody = response.body.length > 500
          ? '${response.body.substring(0, 500)}...(truncated)'
          : response.body;
      _log('_sendFcm cevap', {
        'uid': userId,
        'statusCode': response.statusCode,
        'responseBody': responseBody,
      });
    } catch (e, st) {
      _log('_sendFcm HATA', {
        'uid': userId,
        'error': e.toString(),
        'stack': st.toString(),
      });
    }
  }

  /// Kurumun tüm YÖNETİCİ kullanıcılarına bildirim gönderir.
  /// [excludeUserId]: Bu kullanıcıya (genellikle bildirimi tetikleyen kişiye)
  /// bildirim gönderilmez.
  ///
  /// Not: Firestore composite index sorunundan ve Türkçe büyük/küçük harf
  /// uyumsuzluğundan kaçınmak için rol filtresi client tarafında yapılır.
  Future<void> sendToManagers({
    required String kurumkodu,
    required String baslik,
    required String mesaj,
    required String tip,
    String? excludeUserId,
    Map<String, dynamic>? veri,
  }) async {
    debugPrint('[Notif] sendToManagers başladı — kurumkodu=$kurumkodu');
    if (kurumkodu.isEmpty) {
      debugPrint('[Notif] kurumkodu boş, iptal.');
      return;
    }
    try {
      final snapshot = await _firestore
          .collection('kullanicilar')
          .where('kurumkodu', isEqualTo: kurumkodu)
          .get();

      debugPrint('[Notif] kullanicilar sorgusu döndü — ${snapshot.docs.length} belge bulundu.');

      final futures = <Future<void>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final rolRaw = (data['rol'] as String? ?? '').trim();
        final uid = (data['uid'] as String? ?? '').trim();
        debugPrint('[Notif]   belge=${doc.id} | rol="$rolRaw" | uid="$uid" | docId="${doc.id}"');

        if (!isManagerUser(data)) {
          debugPrint('[Notif]   → yönetici değil, atlandı.');
          continue;
        }
        if (!canReceiveAllReservationNotifications(data)) {
          debugPrint('[Notif]   → yöneticide tüm rezervasyon bildirimi yetkisi yok, atlandı.');
          continue;
        }
        // Bildirim çanı user.data['uid']'i kullanır; UserController bunu
        // doc.id (Firestore document ID) ile üzerine yazar, bu yüzden doc.id kullanıyoruz.
        final docId = doc.id;
        if (excludeUserId != null && (docId == excludeUserId || uid == excludeUserId)) {
          debugPrint('[Notif]   → tetikleyen kişi, atlandı.');
          continue;
        }

        debugPrint('[Notif]   → bildirim gönderiliyor docId=$docId');
        futures.add(sendToUser(
          userId: docId,
          baslik: baslik,
          mesaj: mesaj,
          tip: tip,
          veri: veri,
        ));
      }
      await Future.wait(futures);
      debugPrint('[Notif] sendToManagers tamamlandı — ${futures.length} bildirim gönderildi.');
    } catch (e, st) {
      debugPrint('[Notif] sendToManagers HATA: $e\n$st');
    }
  }

  /// Kullanıcının okunmamış bildirimlerini canlı olarak dinler.
  Stream<List<AppNotification>> streamUnread(String userId) {
    if (userId.isEmpty) return const Stream.empty();
    return _ref(userId)
        .where('okundu', isEqualTo: false)
        // orderBy kaldırıldı — composite index gerektirdiğinden badge sayacı çalışmıyordu.
        .snapshots()
        .map((s) => s.docs.map(AppNotification.fromSnapshot).toList());
  }

  /// Kullanıcının son 50 bildirimini canlı olarak dinler.
  Stream<List<AppNotification>> streamAll(String userId) {
    if (userId.isEmpty) return const Stream.empty();
    return _ref(userId)
        .orderBy('tarih', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map(AppNotification.fromSnapshot).toList());
  }

  /// Tek bir bildirimi okundu olarak işaretler.
  Future<void> markRead(String userId, String notifId) async {
    if (userId.isEmpty || notifId.isEmpty) return;
    try {
      await _ref(userId).doc(notifId).update({'okundu': true});
    } catch (e) {
      _log('markRead hata', {
        'userId': userId,
        'notifId': notifId,
        'error': e.toString(),
      });
    }
  }

  /// Tüm okunmamış bildirimleri okundu olarak işaretler.
  Future<void> markAllRead(String userId) async {
    if (userId.isEmpty) return;
    try {
      final unread =
          await _ref(userId).where('okundu', isEqualTo: false).get();
      if (unread.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final doc in unread.docs) {
        batch.update(doc.reference, {'okundu': true});
      }
      await batch.commit();
    } catch (e) {
      _log('markAllRead hata', {
        'userId': userId,
        'error': e.toString(),
      });
    }
  }
}
