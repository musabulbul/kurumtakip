import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kurum_takip/pages/ara.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/user_controller.dart';
import '../controllers/institution_controller.dart';
import '../utils/permission_utils.dart';
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

    await userController.getUserInfo(userDocId);
    await institutionController.getInstitutionInfo(
      userKurum,
      setAsOriginal: true,
    );
    await _maybeShowSetupDialog(userKurum);
    await _maybeShowExpiryWarning(userKurum);
  }

  Future<void> _maybeShowSetupDialog(String kurumkodu) async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final prefKey = 'setup_hint_dismissed_$kurumkodu';
    if (prefs.getBool(prefKey) == true) return;

    // Sadece online kayıtlı kurumlara göster
    try {
      final doc = await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(kurumkodu)
          .get();
      final kayitTipi = (doc.data()?['kayitTipi'] ?? '').toString();
      if (kayitTipi != 'online_kayit') return;
    } catch (_) {
      return;
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SetupHintDialog(
        onDismiss: (dontShowAgain) async {
          if (dontShowAgain) {
            await prefs.setBool(prefKey, true);
          }
        },
      ),
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
      final userData = userDoc.data();
      final institutionId = (userData['kurumkodu'] ?? '').toString();
      if (institutionId.isEmpty) {
        return false;
      }
      await userController.getUserInfo(userDoc.id);
      await institutionController.getInstitutionInfo(
        institutionId,
        setAsOriginal: true,
      );
      await _maybeShowSetupDialog(institutionId);
      await _maybeShowExpiryWarning(institutionId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _maybeShowExpiryWarning(String kurumkodu) async {
    if (!mounted) return;

    // Sadece yöneticilere göster
    if (!isManagerUser(userController.data)) return;

    // Kurumun güncel Firestore verisini oku (uyarı alanları için)
    late Map<String, dynamic> kurumData;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(kurumkodu)
          .get();
      if (!doc.exists) return;
      kurumData = doc.data()!;
    } catch (_) {
      return;
    }

    // bitisTarihi'ni parse et (DD.MM.YYYY)
    final bitisTarihiStr = (kurumData['bitisTarihi'] ?? '').toString().trim();
    if (bitisTarihiStr.isEmpty) return;

    DateTime bitisTarihi;
    try {
      final parts = bitisTarihiStr.split('.');
      if (parts.length != 3) return;
      bitisTarihi = DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
    } catch (_) {
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysUntilExpiry = bitisTarihi.difference(today).inDays;

    // Sadece 7 gün veya daha az kaldıysa göster
    if (daysUntilExpiry > 7) return;

    // "Bir daha gösterme" tıklandı mı? (bitisTarihi değişmediyse geçerli)
    final uyariGizlendi = (kurumData['uyariGizlendi'] as bool?) ?? false;
    final uyariGizlendiTarih =
        (kurumData['uyariGizlendiTarih'] ?? '').toString().trim();
    if (uyariGizlendi && uyariGizlendiTarih == bitisTarihiStr) return;

    // Bugün zaten bir yöneticiye gösterildi mi?
    final todayStr =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final sonGosterimGunu =
        (kurumData['uyariSonGosterimGunu'] ?? '').toString().trim();
    if (sonGosterimGunu == todayStr) return;

    // Bugün gösterildi olarak işaretle (diğer yöneticileri engelle)
    try {
      await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(kurumkodu)
          .update({'uyariSonGosterimGunu': todayStr});
    } catch (_) {}

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ExpiryWarningDialog(
        bitisTarihiStr: bitisTarihiStr,
        kurumkodu: kurumkodu,
      ),
    );
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

class _SetupHintDialog extends StatefulWidget {
  const _SetupHintDialog({required this.onDismiss});
  final Future<void> Function(bool dontShowAgain) onDismiss;

  @override
  State<_SetupHintDialog> createState() => _SetupHintDialogState();
}

class _SetupHintDialogState extends State<_SetupHintDialog> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.settings_suggest_rounded, color: cs.primary, size: 36),
      title: const Text(
        'Kurumunuzu Ayarlayın',
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Uygulamayı kullanmadan önce sol üst köşedeki menü düğmesinden '
            'Ayarlar kısmına girerek aşağıdaki tanımlamaları yapınız:',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          _HintItem(icon: Icons.meeting_room_outlined, text: 'Mekan Ayarları'),
          _HintItem(icon: Icons.category_outlined, text: 'Kategori ve İşlem Tanımları'),
          _HintItem(icon: Icons.schedule_outlined, text: 'Saat Ayarları'),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _dontShowAgain,
                onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
              ),
              const Text('Bir daha gösterme', style: TextStyle(fontSize: 13)),
            ],
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () async {
            Navigator.of(context).pop();
            await widget.onDismiss(_dontShowAgain);
          },
          child: const Text('Tamam'),
        ),
      ],
    );
  }
}

class _HintItem extends StatelessWidget {
  const _HintItem({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _ExpiryWarningDialog extends StatelessWidget {
  const _ExpiryWarningDialog({
    required this.bitisTarihiStr,
    required this.kurumkodu,
  });

  final String bitisTarihiStr;
  final String kurumkodu;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded,
          color: Colors.orange, size: 36),
      title: const Text(
        'Sözleşme Süresi Uyarısı',
        textAlign: TextAlign.center,
      ),
      content: Text(
        'Sözleşmeniz $bitisTarihiStr tarihinde dolmaktadır.\n\n'
        'Uzatmak için müşteri temsilcinizle iletişime geçiniz.',
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(
          onPressed: () async {
            try {
              await FirebaseFirestore.instance
                  .collection('kurumlar')
                  .doc(kurumkodu)
                  .update({
                'uyariGizlendi': true,
                'uyariGizlendiTarih': bitisTarihiStr,
              });
            } catch (_) {}
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Bir daha gösterme'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tamam'),
        ),
      ],
    );
  }
}
