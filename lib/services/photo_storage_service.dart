import 'package:firebase_storage/firebase_storage.dart';

class PhotoStorageService {
  static String _base(String kurumkodu) => '${kurumkodu.trim()}/fotograflar';

  static Reference studentProfileRef(String kurumkodu, String studentId) {
    final cleanedId = studentId.trim();
    return FirebaseStorage.instance
        .ref('${_base(kurumkodu)}/danisanlar/$cleanedId/profile.jpg');
  }

  static Reference studentOperationPhotoRef(
    String kurumkodu,
    String studentId,
    String operationId,
    String photoId,
  ) {
    final cleanedId = studentId.trim();
    return FirebaseStorage.instance.ref(
      '${kurumkodu.trim()}/danisanlar/$cleanedId/islemler/${operationId.trim()}/$photoId.jpg',
    );
  }

  static Reference reservationOperationPhotoRef(
    String kurumkodu,
    String studentId,
    String operationKey,
    String photoId,
  ) {
    final cleanedId = studentId.trim();
    return FirebaseStorage.instance.ref(
      '${kurumkodu.trim()}/danisanlar/$cleanedId/islemler/${operationKey.trim()}/$photoId.jpg',
    );
  }

  static Reference legacyStudentProfileRef(String kurumkodu, String studentId) {
    final cleanedId = studentId.trim();
    return FirebaseStorage.instance
        .ref('${kurumkodu.trim()}/danisanlar/$cleanedId.jpg');
  }
}
