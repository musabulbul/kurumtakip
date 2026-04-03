import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/fcm_service.dart';

class UserController extends GetxController {
  var data = {}.obs;
  var isLoading = true.obs;
  Map<String, dynamic>? _originalData;
  String? _impersonatedRole;
  String? _impersonatedInstitutionId;

  // Kullanıcı bilgilerini al
  Future<void> getUserInfo(String userDocId) async {
    final trimmedUserDocId = userDocId.trim();
    if (trimmedUserDocId.isEmpty) {
      data.value = {};
      isLoading(false);
      return;
    }
    try {
      isLoading(true); // Yükleniyor olduğunu belirt
      final userDoc = await FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(trimmedUserDocId)
          .get()
          .timeout(const Duration(seconds: 12));
      if (userDoc.exists) {
        final fetched = userDoc.data() as Map<String, dynamic>;
        fetched['uid'] = trimmedUserDocId;
        data.value = fetched;
        _originalData = Map<String, dynamic>.from(fetched);
        _impersonatedRole = null;
        _impersonatedInstitutionId = null;
        // FCM token'ı kaydet (mobil platformlarda push bildirim için).
        FcmService.init(trimmedUserDocId).ignore();
      } else {
        data.value = {};
        _originalData = null;
        _impersonatedRole = null;
        _impersonatedInstitutionId = null;
      }
    } catch (e) {
      // Sessizce yutmak yerine konsola yazdırıp UI'nin kilitlenmesini önle.
      // ignore: avoid_print
      print('[user_controller] getUserInfo error | $e');
      data.value = {};
    } finally {
      isLoading(false); // Yükleme işlemi bitti
    }
  }

  bool get isImpersonating => _impersonatedRole != null || _impersonatedInstitutionId != null;

  void impersonate({required String role, required String institutionId}) {
    if (_originalData == null) {
      return;
    }
    final updated = Map<String, dynamic>.from(_originalData!);
    updated['rol'] = role;
    updated['kurumkodu'] = institutionId;
    updated['impersonated'] = true;
    updated['impersonatedRol'] = role;
    updated['impersonatedKurum'] = institutionId;
    data.value = updated;
    _impersonatedRole = role;
    _impersonatedInstitutionId = institutionId;
  }

  void clearImpersonation() {
    if (_originalData != null) {
      data.value = Map<String, dynamic>.from(_originalData!);
    }
    _impersonatedRole = null;
    _impersonatedInstitutionId = null;
  }
}
