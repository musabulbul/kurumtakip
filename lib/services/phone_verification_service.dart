abstract class PhoneVerificationService {
  Future<String> requestCode(String phone);

  Future<bool> verifyCode({
    required String verificationToken,
    required String smsCode,
  });
}

class BypassPhoneVerificationService implements PhoneVerificationService {
  @override
  Future<String> requestCode(String phone) async {
    return 'bypass-token';
  }

  @override
  Future<bool> verifyCode({
    required String verificationToken,
    required String smsCode,
  }) async {
    return true;
  }
}
