import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  BuildContext? _loadingDialogContext;

  Future<void> loginWithEmail(
      String email, String password, BuildContext context) async {
    _showLoadingDialog(context);
    try {
      // Önce Firebase Auth ile giriş yap, sonra Firestore'dan kullanıcı verisini çek.
      UserCredential userCredential;
      try {
        userCredential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        _dismissLoadingDialog();
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;
        String message;
        if (e.code == 'user-not-found') {
          message = 'Bu e-posta ile kayıtlı bir hesap bulunamadı.';
        } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          message = 'E-posta veya şifre hatalı.';
        } else {
          message = 'Firebase giriş hatası: ${e.message}';
        }
        messenger.showSnackBar(SnackBar(content: Text(message)));
        return;
      }

      // Auth başarılı — artık Firestore okunabilir.
      final QuerySnapshot userQuery = await _firestore
          .collection('kullanicilar')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        _dismissLoadingDialog();
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          const SnackBar(content: Text('Kullanıcı kaydı bulunamadı.')),
        );
        return;
      }

      final userDoc = userQuery.docs.first;
      final userData = userDoc.data() as Map<String, dynamic>;
      final uid = userData['uid'];
      final durum = (userData['durum'] ?? 'aktif').toString();

      if (durum == 'pasif') {
        await _auth.signOut();
        _dismissLoadingDialog();
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          const SnackBar(content: Text('Hesabınız pasif durumda. Yöneticinizle iletişime geçin.')),
        );
        return;
      }

      if (durum == 'ayrildi') {
        await _auth.signOut();
        _dismissLoadingDialog();
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          const SnackBar(content: Text('Bu hesap artık aktif değil.')),
        );
        return;
      }

      if (uid == null || uid != userCredential.user!.uid) {
        await _firestore.collection('kullanicilar').doc(userDoc.id).update({
          'uid': userCredential.user!.uid,
        });
      }

      _dismissLoadingDialog();
      _navigateToHome(context, userDoc.id, userData['kurumkodu']);
    } catch (e) {
      _dismissLoadingDialog();
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(content: Text('Giriş işlemi başarısız: $errorMessage')),
      );
    }
  }

  // CircularProgressIndicator göstermek için
  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _loadingDialogContext = dialogContext;
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 10),
                Text("Giriş yapılıyor..."),
              ],
            ),
          ),
        );
      },
    );
  }

  void _dismissLoadingDialog() {
    if (_loadingDialogContext == null) {
      return;
    }
    final navigator = Navigator.of(_loadingDialogContext!, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
    _loadingDialogContext = null;
  }

  void _navigateToHome(BuildContext context, String userDocId, String userKurum) {
    final navigator = Navigator.maybeOf(context);
    if (navigator == null) {
      return;
    }
    navigator.pushReplacementNamed(
      '/homepage',
      arguments: {"userDocId": userDocId, "userKurum": userKurum},
    );
  }
}
