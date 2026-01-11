import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserController extends GetxController {
  var data = {}.obs;
  var isLoading = true.obs;
  Map<String, dynamic>? _originalData;
  String? _impersonatedRole;
  String? _impersonatedInstitutionId;

  // Kullanıcı bilgilerini al
  void getUserInfo(String userDocId) async {
    try {
      isLoading(true);  // Yükleniyor olduğunu belirt
      var userDoc = await FirebaseFirestore.instance.collection('kullanicilar').doc(userDocId).get();
      if (userDoc.exists) {
        final fetched = userDoc.data() as Map<String, dynamic>;
        data.value = fetched;
        _originalData = Map<String, dynamic>.from(fetched);
        _impersonatedRole = null;
        _impersonatedInstitutionId = null;
      } else {
       
      }
    } catch (e) {
     
    } finally {
      isLoading(false);  // Yükleme işlemi bitti
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
