import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class InstitutionController extends GetxController {
  var data = {}.obs;
  var isLoading = true.obs;
  Map<String, dynamic>? _originalData;
  String? _originalInstitutionId;
  String? currentInstitutionId;
  String? _impersonatedInstitutionId;

  Future<void> getInstitutionInfo(String institutionId, {bool setAsOriginal = false}) async {
    try {
      isLoading(true);  // Yükleniyor olduğunu belirt
      var userDoc = await FirebaseFirestore.instance.collection('kurumlar').doc(institutionId).get();
      if (userDoc.exists) {
        final fetched = userDoc.data() as Map<String, dynamic>;
        data.value = fetched;
        currentInstitutionId = institutionId;
        if (_originalData == null || setAsOriginal) {
          _originalData = Map<String, dynamic>.from(fetched);
          _originalInstitutionId = institutionId;
        }
        if (setAsOriginal) {
          _impersonatedInstitutionId = null;
        }
      } else {
       
      }
    } catch (e) {
      
    } finally {
      isLoading(false);  // Yükleme işlemi bitti
    }
  }

  bool get isImpersonating =>
      _impersonatedInstitutionId != null &&
      _impersonatedInstitutionId != _originalInstitutionId;

  Future<void> switchInstitution(String institutionId) async {
    await getInstitutionInfo(institutionId, setAsOriginal: false);
    _impersonatedInstitutionId = institutionId;
  }

  void clearImpersonation() {
    if (_originalData != null && _originalInstitutionId != null) {
      data.value = Map<String, dynamic>.from(_originalData!);
      currentInstitutionId = _originalInstitutionId;
    }
    _impersonatedInstitutionId = null;
  }
}
