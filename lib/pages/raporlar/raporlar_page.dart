import 'package:flutter/material.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import 'islemler_raporu_page.dart';
import 'odemeler_raporu_page.dart';
import 'giderler_raporu_page.dart';
import 'danisan_hesaplari_page.dart';
import '../stok/stok_page.dart';

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
              title: const Text('Gelirler'),
              subtitle: const Text('Tüm gelirleri görüntüle ve filtrele'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OdemelerRaporuPage()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.trending_down_outlined),
              title: const Text('Giderler'),
              subtitle: const Text('Giderleri görüntüle ve filtrele'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GiderlerRaporuPage()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Danışan Hesapları'),
              subtitle: const Text('Borç, ödeme ve bakiye özetleri'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DanisanHesaplariPage()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Stok'),
              subtitle: const Text('Stok yönetimi'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StokPage()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
