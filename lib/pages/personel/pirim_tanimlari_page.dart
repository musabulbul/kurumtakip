import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/pirim_model.dart';
import '../../services/pirim_service.dart';
import '../../widgets/home_icon_button.dart';

class PirimTanimlariPage extends StatefulWidget {
  const PirimTanimlariPage({
    super.key,
    required this.userId,
    required this.kurumKodu,
    required this.personelAdi,
  });

  final String userId;
  final String kurumKodu;
  final String personelAdi;

  @override
  State<PirimTanimlariPage> createState() => _PirimTanimlariPageState();
}

class _PirimTanimlariPageState extends State<PirimTanimlariPage> {
  final _service = PirimService();
  List<PirimTanimi> _tanimlar = [];
  List<Map<String, dynamic>> _kategoriler = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _service.getPirimTanimlari(widget.userId),
      _fetchKategoriler(),
    ]);
    if (!mounted) return;
    setState(() {
      _tanimlar = results[0] as List<PirimTanimi>;
      _kategoriler = results[1] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _fetchKategoriler() async {
    final snap = await FirebaseFirestore.instance
        .collection('kurumlar')
        .doc(widget.kurumKodu)
        .collection('islemKategorileri')
        .orderBy('adi')
        .get();
    final list = snap.docs
        .map((d) => {'id': d.id, 'adi': (d.data()['adi'] ?? d.id).toString()})
        .toList();
    // Satış sabit kategori olarak en sona eklenir
    list.add({
      'id': kSatisPirimKategoriId,
      'adi': kSatisPirimKategoriAdi,
    });
    return list;
  }

  List<Map<String, dynamic>> get _availableKategoriler {
    final definedIds = _tanimlar.map((t) => t.kategoriId).toSet();
    return _kategoriler.where((k) => !definedIds.contains(k['id'])).toList();
  }

  Future<void> _delete(PirimTanimi tanim) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pirim Tanımını Sil'),
        content:
            Text('${tanim.kategoriAdi} kategorisi için pirim tanımı silinecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _service.deletePirimTanimi(widget.userId, tanim.kategoriId);
    await _load();
  }

  void _showEditDialog({PirimTanimi? existing}) {
    final available = existing != null ? _kategoriler : _availableKategoriler;
    if (available.isEmpty && existing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tüm kategoriler için pirim tanımı mevcut.')),
      );
      return;
    }

    Map<String, dynamic>? selectedKat = existing != null
        ? _kategoriler.firstWhere(
            (k) => k['id'] == existing.kategoriId,
            orElse: () =>
                {'id': existing.kategoriId, 'adi': existing.kategoriAdi},
          )
        : (available.isNotEmpty ? available.first : null);

    final oranCtrl = TextEditingController(
        text: existing != null && existing.oran > 0
            ? existing.oran.toString()
            : '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null
              ? 'Pirim Tanımı Ekle'
              : 'Pirim Tanımını Düzenle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Kategori'),
              const SizedBox(height: 6),
              DropdownButtonFormField<Map<String, dynamic>>(
                value: selectedKat,
                isExpanded: true,
                decoration:
                    const InputDecoration(border: OutlineInputBorder()),
                items: (existing != null ? _kategoriler : available)
                    .map((k) => DropdownMenuItem(
                          value: k,
                          child: Row(
                            children: [
                              if (k['id'] == kSatisPirimKategoriId)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(Icons.shopping_cart_outlined,
                                      size: 16),
                                ),
                              Text(k['adi'].toString()),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: existing != null
                    ? null
                    : (v) => setDialogState(() => selectedKat = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: oranCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: selectedKat?['id'] == kSatisPirimKategoriId
                      ? 'Satış Pirim Oranı (%)'
                      : 'Pirim Oranı (%)',
                  hintText: 'örn: 10',
                  border: const OutlineInputBorder(),
                  suffixText: '%',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () async {
                final kat = selectedKat;
                if (kat == null) return;
                final oran = double.tryParse(oranCtrl.text.trim()) ?? 0;
                final tanim = PirimTanimi(
                  kategoriId: kat['id'].toString(),
                  kategoriAdi: kat['adi'].toString(),
                  oran: oran,
                );
                Navigator.pop(ctx);
                await _service.savePirimTanimi(widget.userId, tanim);
                await _load();
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.personelAdi} — Pirim Tanımları'),
        actions: const [HomeIconButton()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tanimlar.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.percent, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('Henüz pirim tanımı yok.'),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => _showEditDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Pirim Tanımı Ekle'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tanimlar.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final tanim = _tanimlar[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          tanim.isSatis
                              ? Icons.shopping_cart_outlined
                              : Icons.medical_services_outlined,
                          color: tanim.isSatis ? Colors.blue : null,
                        ),
                        title: Text(tanim.kategoriAdi),
                        subtitle: Text('Pirim Oranı: %${_fmt(tanim.oran)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Düzenle',
                              onPressed: () =>
                                  _showEditDialog(existing: tanim),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Sil',
                              onPressed: () => _delete(tanim),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
}
