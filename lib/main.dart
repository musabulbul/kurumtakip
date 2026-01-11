import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kurum_takip/firebase_options.dart';


import '/pages/Login_Screen/Login_Screen.dart';
import '/pages/ara.dart';
import '/pages/detayli_ara.dart';
import 'pages/home_page.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'pages/kullanici_ekle.dart';
import 'pages/kurumlar.dart';
import 'controllers/user_controller.dart';
import 'controllers/institution_controller.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  ); 

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  await Hive.initFlutter();
  _registerGlobalControllers();
  runApp(MyApp());
}

void _registerGlobalControllers() {
  if (!Get.isRegistered<UserController>()) {
    Get.put(UserController(), permanent: true);
  }
  if (!Get.isRegistered<InstitutionController>()) {
    Get.put(InstitutionController(), permanent: true);
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mebs Kurum Takip',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('tr', 'TR'),
        Locale('en', 'US'),
      ],
      // Rotasyonların tanımlandığı kısım
      initialRoute: '/',
      routes: {
        '/': (context) => CheckLoginPage(),
        '/login': (context) => LoginScreen(),
        '/homepage': (context) => HomePage(),
        '/ara': (context) => Ara(),
        '/detayliara': (context) => DetayliAra(),
         '/kullaniciekle': (context) => KullaniciEkle(),
        '/kurumlar': (context) => const KurumlarPage(),
        
        
      },
    );
  }
}

// Kullanıcı giriş durumu kontrolü yapılan sayfa
class CheckLoginPage extends StatefulWidget {
  @override
  State<CheckLoginPage> createState() => _CheckLoginPageState();
}

class _CheckLoginPageState extends State<CheckLoginPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final StreamSubscription<User?> _authSubscription;
  bool _isNavigating = false;
  String? _processedUserId;
  Timer? _loginFallbackTimer;
  bool _hasObservedAuthenticatedUser = false;

  @override
  void initState() {
    super.initState();
    _loginFallbackTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _isNavigating || _hasObservedAuthenticatedUser) {
        return;
      }
      _navigateToLogin();
    });
    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen(_handleAuthState);
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _loginFallbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleAuthState(User? user) async {
    if (!mounted || _isNavigating) {
      return;
    }

    if (user == null) {
      _processedUserId = null;
      if (_hasObservedAuthenticatedUser) {
        _navigateToLogin();
      }
      return;
    }

    _hasObservedAuthenticatedUser = true;
    _loginFallbackTimer?.cancel();

    if (_processedUserId == user.uid) {
      return;
    }
    _processedUserId = user.uid;

    try {
      final query = await _firestore
          .collection('kullanicilar')
          .where('email', isEqualTo: user.email)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        await FirebaseAuth.instance.signOut();
        _processedUserId = null;
        _isNavigating = true;
        _navigateToLogin();
        return;
      }

      final userDoc = query.docs.first;
      final userData = userDoc.data() as Map<String, dynamic>;
      final userKurum = (userData['kurumkodu'] as String?) ?? '';

      _isNavigating = true;
      _navigateToHome(userDoc.id, userKurum);
    } catch (error) {
      // Anlık bir hata oluşursa kullanıcıyı oturum açma ekranına yönlendir.
      _processedUserId = null;
      _isNavigating = true;
      _navigateToLogin();
    }
  }

  void _navigateToLogin() {
    _isNavigating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  void _navigateToHome(String userDocId, String userKurum) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.pushReplacementNamed(
        context,
        '/homepage',
        arguments: {
          'userDocId': userDocId,
          'userKurum': userKurum,
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
