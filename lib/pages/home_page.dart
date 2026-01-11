import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kurum_takip/pages/ara.dart';

import '../controllers/user_controller.dart';
import '../controllers/institution_controller.dart';
import 'detayli_ara.dart';
import 'raporlar/raporlar_page.dart';


class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final dynamic _launchArgs = Get.arguments;
  final UserController userController = Get.find<UserController>();
  final InstitutionController institutionController = Get.find<InstitutionController>();

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchData();
      }
    });
  }

  Future<void> _fetchData() async {
    final args = _resolveLaunchArguments();
    String? userDocId = args?['userDocId'] as String?;
    String? userKurum = args?['userKurum'] as String?;

    if (userDocId == null || userKurum == null) {
      final restored = await _recoverSessionFromAuth();
      if (!restored) {
        userController.isLoading(false);
        if (mounted) {
          Get.offAllNamed('/login');
        }
      }
      return;
    }

    userController.getUserInfo(userDocId);
    await institutionController.getInstitutionInfo(
      userKurum,
      setAsOriginal: true,
    );
  }

  Map<String, dynamic>? _resolveLaunchArguments() {
    if (_launchArgs is Map<String, dynamic>) {
      return Map<String, dynamic>.from(_launchArgs as Map);
    }
    final modalArgs = ModalRoute.of(context)?.settings.arguments;
    if (modalArgs is Map<String, dynamic>) {
      return Map<String, dynamic>.from(modalArgs);
    }
    return null;
  }

  Future<bool> _recoverSessionFromAuth() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return false;
    }
    try {
      final query = await FirebaseFirestore.instance
          .collection('kullanicilar')
          .where('email', isEqualTo: currentUser.email)
          .limit(1)
          .get();
      if (query.docs.isEmpty) {
        return false;
      }
      final userDoc = query.docs.first;
      final userData = userDoc.data() as Map<String, dynamic>;
      final institutionId = (userData['kurumkodu'] ?? '').toString();
      if (institutionId.isEmpty) {
        return false;
      }
      userController.getUserInfo(userDoc.id);
      await institutionController.getInstitutionInfo(
        institutionId,
        setAsOriginal: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Obx(() {
        if (userController.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        final screens = _buildScreens();
        if (screens.isEmpty) {
          return const SizedBox.shrink();
        }
        final safeIndex = _selectedIndex.clamp(0, screens.length - 1).toInt();
        return screens[safeIndex];
      }),
      bottomNavigationBar: Obx(() {
        if (userController.isLoading.value) {
          return const SizedBox.shrink();
        }
        final items = _navBarsItems();
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }
        final safeIndex = _selectedIndex.clamp(0, items.length - 1).toInt();
        return BottomNavigationBar(
          currentIndex: safeIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.purple,
          unselectedItemColor: Colors.grey,
          items: items,
        );
      }),
    );
  }

  List<BottomNavigationBarItem> _navBarsItems() {
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.search),
        label: 'Ara',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.search_off),
        label: 'Detaylı Ara',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.bar_chart_outlined),
        label: 'Raporlar',
      ),
    ];

   

    return items;
  }

  List<Widget> _buildScreens() {
    final screens = <Widget>[
      Ara(),
      const DetayliAra(),
      const RaporlarPage(),
    ];

    

    _ensureSelectedIndexValid(screens.length);
    return screens;
  }

  void _ensureSelectedIndexValid(int length) {
    if (length <= 0) {
      return;
    }
    if (_selectedIndex >= length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _selectedIndex = length - 1;
        });
      });
    }
  }
}
