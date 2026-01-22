import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import '../../controllers/user_controller.dart';
import '../../utils/permission_utils.dart';
import 'islemler_page.dart';
import 'mekanlar_page.dart';
import 'paketler_page.dart';
import 'saatler_page.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  final UserController _user = Get.find<UserController>();

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!isManagerUser(_user.data)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu sayfaya sadece yöneticiler erişebilir.'),
          ),
        );
        Navigator.of(context).maybePop();
        return;
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yönetici Ayarları'),
        actions: const [HomeIconButton()],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.meeting_room_outlined),
                    title: const Text('Mekanlar'),
                    subtitle:
                        const Text('Mekan ekle, güncelle, kullanıcı ata'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openMekanlarPage,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('Saatler'),
                    subtitle: const Text('Günlük seans saatlerini ayarla'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openSaatlerPage,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: const Text('İşlemler'),
                    subtitle: const Text('Kategori ve işlem yönetimi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openIslemlerPage,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: const Text('Paketler'),
                    subtitle: const Text('Paket tanımları ve içerikleri'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openPaketlerPage,
                  ),
                ),
              ],
            ),
    );
  }

  void _openMekanlarPage() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MekanlarPage()),
    );
  }

  void _openSaatlerPage() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SaatlerPage()),
    );
  }

  void _openIslemlerPage() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IslemlerPage()),
    );
  }

  void _openPaketlerPage() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PaketlerPage()),
    );
  }
}
