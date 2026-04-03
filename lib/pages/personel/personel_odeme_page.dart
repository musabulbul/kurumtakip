import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../widgets/home_icon_button.dart';

const _hakedisLabels = {
  'maas': 'Maaş Hakkı',
  'pirim': 'Prim Hakkı',
  'ikramiye': 'İkramiye',
  'fazla_mesai': 'Fazla Mesai',
  'diger': 'Diğer Hakediş',
};

const _odemeLabels = {
  'maas': 'Maaş',
  'avans': 'Avans',
  'pirim': 'Prim Ödemesi',
  'diger': 'Diğer',
};

const _yontemLabels = {
  'cash': 'Nakit',
  'card': 'Kredi Kartı',
  'transfer': 'Havale/EFT',
};

enum _HareketTur { hakedis, odeme }

class _Hareket {
  final String id;
  final _HareketTur tur;
  final String kategori;
  final double tutar;
  final String odemeYontemi;
  final DateTime? tarih;
  final String not;
  final String? giderDocId;

  _Hareket({
    required this.id,
    required this.tur,
    required this.kategori,
    required this.tutar,
    this.odemeYontemi = 'cash',
    this.tarih,
    this.not = '',
    this.giderDocId,
  });
}

class PersonelOdemePage extends StatefulWidget {
  const PersonelOdemePage({
    super.key,
    required this.userId,
    required this.personelAdi,
    required this.kurumKodu,
    required this.yapanAdi,
  });

  final String userId;
  final String personelAdi;
  final String kurumKodu;
  final String yapanAdi;

  @override
  State<PersonelOdemePage> createState() => _PersonelOdemePageState();
}

class _PersonelOdemePageState extends State<PersonelOdemePage> {
  final _fmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
  final _dateFmt = DateFormat('dd.MM.yyyy');

  List<_Hareket> _hakedisler = [];
  List<_Hareket> _odemeler = [];
  StreamSubscription? _hakSub;
  StreamSubscription? _odemeSub;

  CollectionReference<Map<String, dynamic>> get _hakedisRef =>
      FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(widget.userId)
          .collection('personelHakedisleri');

  CollectionReference<Map<String, dynamic>> get _odemeRef =>
      FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(widget.userId)
          .collection('personelOdemeleri');

  CollectionReference<Map<String, dynamic>> get _giderRef =>
      FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(widget.kurumKodu)
          .collection('giderler');

  @override
  void initState() {
    super.initState();
    _hakSub = _hakedisRef
        .orderBy('tarih', descending: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _hakedisler = snap.docs.map((d) {
          final data = d.data();
          return _Hareket(
            id: d.id,
            tur: _HareketTur.hakedis,
            kategori: (data['tur'] as String?) ?? 'diger',
            tutar: (data['tutar'] as num?)?.toDouble() ?? 0,
            tarih: _toDate(data['tarih']),
            not: (data['not'] as String?) ?? '',
          );
        }).toList();
      });
    });

    _odemeSub = _odemeRef
        .orderBy('tarih', descending: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _odemeler = snap.docs.map((d) {
          final data = d.data();
          return _Hareket(
            id: d.id,
            tur: _HareketTur.odeme,
            kategori: (data['tur'] as String?) ?? 'diger',
            tutar: (data['tutar'] as num?)?.toDouble() ?? 0,
            odemeYontemi: (data['odemeYontemi'] as String?) ?? 'cash',
            tarih: _toDate(data['tarih']),
            not: (data['not'] as String?) ?? '',
            giderDocId: data['giderDocId'] as String?,
          );
        }).toList();
      });
    });
  }

  @override
  void dispose() {
    _hakSub?.cancel();
    _odemeSub?.cancel();
    super.dispose();
  }

  double get _toplamHakedis =>
      _hakedisler.fold(0, (s, h) => s + h.tutar);
  double get _toplamOdeme => _odemeler.fold(0, (s, o) => s + o.tutar);
  double get _bakiye => _toplamHakedis - _toplamOdeme;

  List<_Hareket> get _combined {
    final all = [..._hakedisler, ..._odemeler];
    all.sort((a, b) {
      if (a.tarih == null && b.tarih == null) return 0;
      if (a.tarih == null) return 1;
      if (b.tarih == null) return -1;
      return b.tarih!.compareTo(a.tarih!);
    });
    return all;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.personelAdi} — Hesap'),
          actions: const [HomeIconButton()],
          bottom: const TabBar(
            labelColor: Colors.black,
            unselectedLabelColor: Colors.black54,
            indicatorColor: Colors.black,
            tabs: [
              Tab(text: 'Ekstresi'),
              Tab(text: 'Hakediş'),
              Tab(text: 'Ödemeler'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildEkstresiTab(),
            _buildHakedisTab(),
            _buildOdemeTab(),
          ],
        ),
      ),
    );
  }

  // ─── Özet Kartı ───────────────────────────────────────────────────────────

  Widget _buildSummaryCard() {
    final bakiye = _bakiye;
    final isAlacak = bakiye >= 0;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                      'Toplam Hakediş', _toplamHakedis, Colors.green),
                ),
                Expanded(
                  child: _buildSummaryItem(
                      'Toplam Ödeme', _toplamOdeme, Colors.red),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isAlacak ? 'Personel Alacağı' : 'Fazla Ödeme',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isAlacak
                        ? Colors.orange.shade700
                        : Colors.blue.shade700,
                  ),
                ),
                Text(
                  _fmt.format(bakiye.abs()),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isAlacak
                        ? Colors.orange.shade700
                        : Colors.blue.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, double amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          _fmt.format(amount),
          style: TextStyle(
              fontWeight: FontWeight.bold, color: color, fontSize: 15),
        ),
      ],
    );
  }

  // ─── Ekstresi Tab ─────────────────────────────────────────────────────────

  Widget _buildEkstresiTab() {
    final combined = _combined;
    if (combined.isEmpty) {
      return Column(
        children: [
          _buildSummaryCard(),
          const Expanded(
            child: Center(
              child: Text('Henüz kayıt yok.',
                  style: TextStyle(color: Colors.grey)),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      itemCount: combined.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) return _buildSummaryCard();
        return _buildHareketTile(combined[i - 1], showDelete: false);
      },
    );
  }

  Widget _buildHareketTile(_Hareket h, {bool showDelete = true}) {
    final isHakedis = h.tur == _HareketTur.hakedis;
    final label = isHakedis
        ? (_hakedisLabels[h.kategori] ?? h.kategori)
        : (_odemeLabels[h.kategori] ?? h.kategori);
    final color = isHakedis ? Colors.green : Colors.red;
    final sign = isHakedis ? '+' : '−';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withAlpha(30),
        child: Icon(
          isHakedis ? Icons.arrow_downward : Icons.arrow_upward,
          color: color,
          size: 18,
        ),
      ),
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isHakedis)
            Text(
              _yontemLabels[h.odemeYontemi] ?? h.odemeYontemi,
              style: const TextStyle(fontSize: 12),
            ),
          if (h.not.isNotEmpty)
            Text(h.not,
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey)),
          if (h.tarih != null)
            Text(_dateFmt.format(h.tarih!),
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
      isThreeLine: h.not.isNotEmpty || !isHakedis,
      trailing: Text(
        '$sign${_fmt.format(h.tutar)}',
        style: TextStyle(
            fontWeight: FontWeight.bold, color: color, fontSize: 14),
      ),
    );
  }

  // ─── Hakediş Tab ──────────────────────────────────────────────────────────

  Widget _buildHakedisTab() {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'hakedis_fab',
        onPressed: _showAddHakedisDialog,
        child: const Icon(Icons.add),
      ),
      body: _hakedisler.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_downward,
                      size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('Hakediş kaydı yok.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _showAddHakedisDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Hakediş Ekle'),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: _hakedisler.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final h = _hakedisler[i];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE8F5E9),
                      child: Icon(Icons.arrow_downward,
                          color: Colors.green, size: 18),
                    ),
                    title: Text(
                        _hakedisLabels[h.kategori] ?? h.kategori),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (h.not.isNotEmpty)
                          Text(h.not,
                              style: const TextStyle(fontSize: 12)),
                        if (h.tarih != null)
                          Text(_dateFmt.format(h.tarih!),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _fmt.format(h.tutar),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 20),
                          onPressed: () => _deleteHakedis(h.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ─── Ödeme Tab ────────────────────────────────────────────────────────────

  Widget _buildOdemeTab() {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'odeme_fab',
        onPressed: _showAddOdemeDialog,
        child: const Icon(Icons.add),
      ),
      body: _odemeler.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.payments_outlined,
                      size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('Ödeme kaydı yok.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _showAddOdemeDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Ödeme Ekle'),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: _odemeler.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final o = _odemeler[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.red.withAlpha(30),
                      child: const Icon(Icons.arrow_upward,
                          color: Colors.red, size: 18),
                    ),
                    title:
                        Text(_odemeLabels[o.kategori] ?? o.kategori),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _yontemLabels[o.odemeYontemi] ??
                              o.odemeYontemi,
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (o.not.isNotEmpty)
                          Text(o.not,
                              style: const TextStyle(fontSize: 12)),
                        if (o.tarih != null)
                          Text(_dateFmt.format(o.tarih!),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _fmt.format(o.tutar),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 20),
                          onPressed: () => _deleteOdeme(o),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ─── Dialog'lar ───────────────────────────────────────────────────────────

  Future<void> _showAddHakedisDialog() async {
    String tur = 'maas';
    DateTime tarih = DateTime.now();
    final tutarCtrl = TextEditingController();
    final notCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Hakediş Ekle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: tur,
                  decoration: const InputDecoration(
                      labelText: 'Hakediş Türü',
                      border: OutlineInputBorder()),
                  items: _hakedisLabels.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => set(() => tur = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tutarCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Tutar',
                      border: OutlineInputBorder(),
                      suffixText: '₺'),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final p = await showDatePicker(
                      context: ctx,
                      initialDate: tarih,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (p != null) set(() => tarih = p);
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(_dateFmt.format(tarih)),
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

    final tutar =
        double.tryParse(tutarCtrl.text.trim().replaceAll(',', '.')) ??
            0;
    final notText = notCtrl.text.trim();
    tutarCtrl.dispose();
    notCtrl.dispose();

    if (result != true || tutar <= 0) return;

    try {
      await _hakedisRef.add({
        'tur': tur,
        'tutar': tutar,
        'tarih': Timestamp.fromDate(tarih),
        'not': notText,
        'olusturmaTarihi': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hakediş eklendi.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  Future<void> _deleteHakedis(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hakediş Sil'),
        content: const Text('Bu hakediş kaydı silinecek.'),
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
    await _hakedisRef.doc(docId).delete();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Silindi.')));
    }
  }

  Future<void> _showAddOdemeDialog() async {
    String tur = 'maas';
    String yontem = 'cash';
    DateTime tarih = DateTime.now();
    final tutarCtrl = TextEditingController();
    final notCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Ödeme Ekle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: tur,
                  decoration: const InputDecoration(
                      labelText: 'Ödeme Türü',
                      border: OutlineInputBorder()),
                  items: _odemeLabels.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => set(() => tur = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tutarCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Tutar',
                      border: OutlineInputBorder(),
                      suffixText: '₺'),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: yontem,
                  decoration: const InputDecoration(
                      labelText: 'Ödeme Yöntemi',
                      border: OutlineInputBorder()),
                  items: _yontemLabels.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => set(() => yontem = v!),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final p = await showDatePicker(
                      context: ctx,
                      initialDate: tarih,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (p != null) set(() => tarih = p);
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(_dateFmt.format(tarih)),
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

    final tutar =
        double.tryParse(tutarCtrl.text.trim().replaceAll(',', '.')) ??
            0;
    final notText = notCtrl.text.trim();
    tutarCtrl.dispose();
    notCtrl.dispose();

    if (result != true || tutar <= 0) return;

    final batch = FirebaseFirestore.instance.batch();
    final odemeDoc = _odemeRef.doc();
    final giderDoc = _giderRef.doc();
    final turLabel = _odemeLabels[tur] ?? tur;

    batch.set(odemeDoc, {
      'tur': tur,
      'tutar': tutar,
      'odemeYontemi': yontem,
      'tarih': Timestamp.fromDate(tarih),
      'not': notText,
      'giderDocId': giderDoc.id,
    });
    batch.set(giderDoc, {
      'title': '${widget.personelAdi} — $turLabel',
      'type': 'Personel',
      'paymentType': yontem,
      'amount': tutar,
      'note': notText,
      'paidByName': widget.yapanAdi,
      'createdAt': Timestamp.fromDate(tarih),
      'createdById': widget.userId,
      'personelUserId': widget.userId,
    });

    try {
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ödeme kaydedildi.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  Future<void> _deleteOdeme(_Hareket o) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ödemeyi Sil'),
        content: const Text('Ödeme ve ilgili gider kaydı silinecek.'),
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

    final batch = FirebaseFirestore.instance.batch();
    batch.delete(_odemeRef.doc(o.id));
    if (o.giderDocId != null && o.giderDocId!.isNotEmpty) {
      batch.delete(_giderRef.doc(o.giderDocId!));
    }

    try {
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Silindi.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}
