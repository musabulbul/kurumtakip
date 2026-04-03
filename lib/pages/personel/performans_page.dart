import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../widgets/home_icon_button.dart';

class PerformansPage extends StatefulWidget {
  const PerformansPage({
    super.key,
    required this.userId,
    required this.personelAdi,
  });

  final String userId;
  final String personelAdi;

  @override
  State<PerformansPage> createState() => _PerformansPageState();
}

class _PerformansPageState extends State<PerformansPage> {
  final _fmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

  late int _yil;
  late int _ay;
  bool _loading = false;

  int _islemSayisi = 0;
  double _toplamCiro = 0;
  List<MapEntry<String, _KatData>> _kategoriler = [];

  static const _months = [
    '',
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _yil = now.year;
    _ay = now.month;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final start = DateTime(_yil, _ay);
      final end = DateTime(_yil, _ay + 1);

      final snap = await FirebaseFirestore.instance
          .collectionGroup('islemler')
          .where('performedById', isEqualTo: widget.userId)
          .where('completedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('completedAt', isLessThan: Timestamp.fromDate(end))
          .get();

      int count = 0;
      double ciro = 0;
      final kat = <String, _KatData>{};

      for (final doc in snap.docs) {
        final data = doc.data();
        final price =
            (data['operationPrice'] as num?)?.toDouble() ?? 0;
        if (price <= 0) continue;
        count++;
        ciro += price;

        final entryType = (data['entryType'] as String?) ?? '';
        final catId = entryType == 'satis'
            ? '__satis__'
            : ((data['operationCategoryId'] ?? data['categoryId'])
                    as String? ??
                '');
        final catName = entryType == 'satis'
            ? 'Satış'
            : ((data['operationCategoryName'] ?? data['categoryName'])
                        as String?)
                    ?.trim() ??
                'Kategorisiz';

        kat.putIfAbsent(catId, () => _KatData(catName));
        kat[catId]!.count++;
        kat[catId]!.ciro += price;
      }

      if (!mounted) return;
      final sorted = kat.entries.toList()
        ..sort((a, b) => b.value.ciro.compareTo(a.value.ciro));

      setState(() {
        _islemSayisi = count;
        _toplamCiro = ciro;
        _kategoriler = sorted;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yükleme hatası: $e')),
      );
    }
  }

  void _prevMonth() {
    setState(() {
      _ay = _ay == 1 ? 12 : _ay - 1;
      if (_ay == 12) _yil--;
    });
    _load();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_yil == now.year && _ay == now.month) return;
    setState(() {
      _ay = _ay == 12 ? 1 : _ay + 1;
      if (_ay == 1) _yil++;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = _yil == now.year && _ay == now.month;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.personelAdi} — Performans'),
        actions: const [HomeIconButton()],
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _loading ? null : _prevMonth,
                ),
                SizedBox(
                  width: 160,
                  child: Text(
                    '${_months[_ay]} $_yil',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed:
                      (_loading || isCurrentMonth) ? null : _nextMonth,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'İşlem Sayısı',
                          _islemSayisi.toString(),
                          Icons.receipt_long_outlined,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'Toplam Ciro',
                          _fmt.format(_toplamCiro),
                          Icons.attach_money,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_kategoriler.isNotEmpty) ...[
                    const Text(
                      'Kategori Dağılımı',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: _kategoriler
                              .map((e) => _buildKatRow(e.value))
                              .toList(),
                        ),
                      ),
                    ),
                  ] else
                    const Center(
                      child: Text(
                        'Bu ay işlem kaydı bulunamadı.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18)),
            Text(label,
                style: const TextStyle(
                    color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildKatRow(_KatData k) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500)),
                Text('${k.count} işlem',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Text(
            _fmt.format(k.ciro),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _KatData {
  final String name;
  int count = 0;
  double ciro = 0;

  _KatData(this.name);
}
