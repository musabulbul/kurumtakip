import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:kurum_takip/core/app_bootstrap.dart';

import '../controllers/institution_controller.dart';
import '../controllers/user_controller.dart';
import '../pages/Login_Screen/Login_Screen.dart';
import '../pages/ara.dart';
import '../pages/detayli_ara.dart';
import '../pages/home_page.dart';
import '../pages/kullanici_ekle.dart';
import '../pages/kullanici_profil.dart';
import '../pages/kullanicilar.dart';
import '../pages/kurumlar.dart';

void runAdminApp() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdminApp());
}

void _registerGlobalControllers() {
  if (!Get.isRegistered<UserController>()) {
    Get.put(UserController(), permanent: true);
  }
  if (!Get.isRegistered<InstitutionController>()) {
    Get.put(InstitutionController(), permanent: true);
  }
}

Future<void> _initializeAppServices() async {
  await AppBootstrap.initialize();
  _registerGlobalControllers();
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  static final Future<void> _bootstrapFuture = _initializeAppServices();

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
      initialRoute: '/',
      routes: {
        '/': (context) => AppBootstrapPage(bootstrapFuture: _bootstrapFuture),
        '/login': (context) => Theme(
              data: _buildLegacyLoginTheme(),
              child: LoginScreen(),
            ),
        '/homepage': (context) => HomePage(),
        '/ara': (context) => Ara(),
        '/detayliara': (context) => DetayliAra(),
        '/kullaniciekle': (context) => KullaniciEkle(),
        '/kullanicilar': (context) => const Kullanicilar(),
        '/kullaniciprofil': (context) => _buildUserProfileRoute(context),
        '/UserProfilePage': (context) => _buildUserProfileRoute(context),
        '/kurumlar': (context) => const KurumlarPage(),
      },
    );
  }

  Widget _buildUserProfileRoute(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    String userDocId = '';
    if (args is String) {
      userDocId = args.trim();
    } else if (args is Map) {
      final raw = args['userDocId'];
      if (raw != null) {
        userDocId = raw.toString().trim();
      }
    }
    userDocId = userDocId.isNotEmpty
        ? userDocId
        : (Uri.base.queryParameters['userDocId'] ?? '').trim();

    if (userDocId.isEmpty) {
      return const Kullanicilar();
    }
    return UserProfilePage(userDocId: userDocId);
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
        titleMedium:
            baseText.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

class AppBootstrapPage extends StatelessWidget {
  const AppBootstrapPage({super.key, required this.bootstrapFuture});

  final Future<void> bootstrapFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Uygulama baslatilamadi. Lutfen sayfayi yenileyin.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return const CheckLoginPage();
        }

        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

class CheckLoginPage extends StatefulWidget {
  const CheckLoginPage({super.key});

  @override
  State<CheckLoginPage> createState() => _CheckLoginPageState();
}

class _CheckLoginPageState extends State<CheckLoginPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final StreamSubscription<User?> _authSubscription;
  bool _isNavigating = false;
  String? _processedUserId;

  @override
  void initState() {
    super.initState();
    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen(_handleAuthState);
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<void> _handleAuthState(User? user) async {
    if (!mounted || _isNavigating) {
      return;
    }

    if (user == null) {
      _processedUserId = null;
      _navigateToLogin();
      return;
    }

    if (_processedUserId == user.uid) {
      return;
    }
    _processedUserId = user.uid;
    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      await FirebaseAuth.instance.signOut();
      _processedUserId = null;
      _navigateToLogin();
      return;
    }

    try {
      final query = await _findUserByEmail(email);

      if (query.docs.isEmpty) {
        await FirebaseAuth.instance.signOut();
        _processedUserId = null;
        _navigateToLogin();
        return;
      }

      final userDoc = query.docs.first;
      final userData = userDoc.data();
      final userKurum = (userData['kurumkodu'] as String?) ?? '';

      _navigateToHome(userDoc.id, userKurum);
    } catch (_) {
      _processedUserId = null;
      _navigateToLogin();
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _findUserByEmail(
    String? email,
  ) async {
    final usersQuery = _firestore
        .collection('kullanicilar')
        .where('email', isEqualTo: email)
        .limit(1);

    try {
      final cached = await usersQuery.get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty) {
        return cached;
      }
    } catch (_) {
      // Cache hatasında network sorgusuna devam edilir.
    }

    return usersQuery.get();
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
    _isNavigating = true;
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
