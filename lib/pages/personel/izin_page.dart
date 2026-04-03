import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../widgets/home_icon_button.dart';

const _izinTurleri = {
  'yillik': 'Yıllık İzin',
  'mazeret': 'Mazeret İzni',
  'ucretsiz': 'Ücretsiz İzin',
  'rapor': 'Hastalık / Rapor',
};

class IzinPage extends StatelessWidget {
  const IzinPage({
    super.key,
    required this.userId,
    required this.personelAdi,
  });

  final String userId;
  final String personelAdi;

  CollectionReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(userId)
          .collection('izinler');

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd.MM.yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text('$personelAdi — İzin Takibi'),
        actions: const [HomeIconButton()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _ref.orderBy('baslangic', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Hata: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.beach_access_outlined,
                      size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('İzin kaydı bulunmuyor.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _showAddDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('İzin Ekle'),
                  ),
                ],
              ),
            );
          }

          // Yıllık izin toplamı
          final yillikGun = docs
              .where((d) => (d.data()['tur'] as String?) == 'yillik')
              .fold<int>(
                  0, (s, d) => s + ((d.data()['gun'] as int?) ?? 1));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Toplam Yıllık İzin',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('$yillikGun gün',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...docs.map((doc) {
                final data = doc.data();
                final tur = (data['tur'] as String?) ?? 'yillik';
                final bas = _toDate(data['baslangic']);
                final bit = _toDate(data['bitis']);
                final gun = (data['gun'] as int?) ?? 1;
                final not = (data['not'] as String?) ?? '';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          _turColor(tur).withAlpha(40),
                      child: Icon(_turIcon(tur),
                          color: _turColor(tur), size: 20),
                    ),
                    title: Text(_izinTurleri[tur] ?? tur),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (bas != null && bit != null)
                          Text(
                            bas.isAtSameMomentAs(bit)
                                ? '${dateFmt.format(bas)} (1 gün)'
                                : '${dateFmt.format(bas)} — ${dateFmt.format(bit)} ($gun gün)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (not.isNotEmpty)
                          Text(not,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    isThreeLine: not.isNotEmpty,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(context, doc.id),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    String tur = 'yillik';
    DateTime baslangic = DateTime.now();
    DateTime bitis = DateTime.now();
    final notCtrl = TextEditingController();
    final dateFmt = DateFormat('dd.MM.yyyy');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('İzin Ekle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: tur,
                  decoration: const InputDecoration(
                      labelText: 'İzin Türü',
                      border: OutlineInputBorder()),
                  items: _izinTurleri.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => set(() => tur = v!),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final r = await showDateRangePicker(
                      context: ctx,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDateRange:
                          DateTimeRange(start: baslangic, end: bitis),
                    );
                    if (r != null) {
                      set(() {
                        baslangic = r.start;
                        bitis = r.end;
                      });
                    }
                  },
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    baslangic.isAtSameMomentAs(bitis)
                        ? dateFmt.format(baslangic)
                        : '${dateFmt.format(baslangic)} — ${dateFmt.format(bitis)}',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Not (opsiyonel)',
                      border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Kaydet')),
          ],
        ),
      ),
    );

    notCtrl.dispose();
    if (result != true) return;

    final gun = bitis.difference(baslangic).inDays + 1;
    try {
      await _ref.add({
        'tur': tur,
        'baslangic': Timestamp.fromDate(baslangic),
        'bitis': Timestamp.fromDate(bitis),
        'gun': gun,
        'not': notCtrl.text.trim(),
        'olusturmaTarihi': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İzin kaydedildi.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kayıt hatası: $e')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('İzni Sil'),
        content: const Text('Bu izin kaydı silinecek.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (confirm != true) return;
    await _ref.doc(docId).delete();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İzin silindi.')),
      );
    }
  }

  DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  IconData _turIcon(String tur) => switch (tur) {
        'yillik' => Icons.beach_access_outlined,
        'mazeret' => Icons.event_busy_outlined,
        'ucretsiz' => Icons.money_off_outlined,
        'rapor' => Icons.local_hospital_outlined,
        _ => Icons.calendar_today_outlined,
      };

  Color _turColor(String tur) => switch (tur) {
        'yillik' => Colors.blue,
        'mazeret' => Colors.orange,
        'ucretsiz' => Colors.red,
        'rapor' => Colors.purple,
        _ => Colors.grey,
      };
}
