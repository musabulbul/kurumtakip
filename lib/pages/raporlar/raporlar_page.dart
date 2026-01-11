import 'package:flutter/material.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import 'islemler_raporu_page.dart';
import 'odemeler_raporu_page.dart';

class RaporlarPage extends StatelessWidget {
  const RaporlarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raporlar'),
        actions: const [HomeIconButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('İşlemler'),
              subtitle: const Text('Tüm işlemleri görüntüle ve filtrele'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const IslemlerRaporuPage()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Ödemeler'),
              subtitle: const Text('Tüm ödemeleri görüntüle ve filtrele'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OdemelerRaporuPage()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Stok'),
              subtitle: const Text('Yakında'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Stok raporu yakında.')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
