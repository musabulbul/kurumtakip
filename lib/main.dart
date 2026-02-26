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
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mebs Kurum Takip',
      theme: _buildAppTheme(),
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
        '/login': (context) => Theme(
              data: _buildLegacyLoginTheme(),
              child: LoginScreen(),
            ),
        '/homepage': (context) => HomePage(),
        '/ara': (context) => Ara(),
        '/detayliara': (context) => DetayliAra(),
         '/kullaniciekle': (context) => KullaniciEkle(),
        '/kurumlar': (context) => const KurumlarPage(),
        
        
      },
    );
  }

  ThemeData _buildAppTheme() {
    const baseSeed = Color(0xFFD14B8F);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: baseSeed,
      brightness: Brightness.light,
    );
    final baseText = ThemeData.light().textTheme;

    return ThemeData(
      useMaterial3: false,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF6F8FB),
      textTheme: baseText.copyWith(
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
        titleMedium: baseText.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: baseText.bodyLarge?.copyWith(height: 1.35),
        bodyMedium: baseText.bodyMedium?.copyWith(height: 1.35),
        labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: baseText.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surface,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.55),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 1.6,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: colorScheme.outline),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        iconColor: colorScheme.primary,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withOpacity(0.7),
      ),
    );
  }

  ThemeData _buildLegacyLoginTheme() {
    return ThemeData(
      useMaterial3: false,
      primarySwatch: Colors.blue,
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
