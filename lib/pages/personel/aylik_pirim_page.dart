import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pirim_model.dart';
import '../../services/pirim_service.dart';
import '../../widgets/home_icon_button.dart';

class AylikPirimPage extends StatefulWidget {
  const AylikPirimPage({
    super.key,
    required this.userId,
    required this.personelAdi,
    required this.onaylayanAdi,
  });

  final String userId;
  final String personelAdi;
  final String onaylayanAdi;

  @override
  State<AylikPirimPage> createState() => _AylikPirimPageState();
}

class _AylikPirimPageState extends State<AylikPirimPage> {
  final _service = PirimService();
  final _currencyFmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

  late int _yil;
  late int _ay;
  AylikPirim? _pirim;
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _yil = now.year;
    _ay = now.month;
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    final kayit = await _service.getAylikPirim(widget.userId, _yil, _ay);
    if (!mounted) return;
    setState(() {
      _pirim = kayit;
      _loading = false;
    });
  }

  Future<void> _hesapla() async {
    setState(() => _loading = true);
    try {
      final pirim =
          await _service.hesaplaAylikPirim(widget.userId, _yil, _ay);
      if (!mounted) return;
      setState(() => _pirim = pirim);
    } catch (e) {
      if (!mounted) return;
      debugPrint('PirimHesaplaHata: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hesaplama hatası: $e'),
          duration: const Duration(seconds: 30),
          action: SnackBarAction(label: 'Kapat', onPressed: () {}),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _kaydet() async {
    final pirim = _pirim;
    if (pirim == null) return;
    setState(() => _saving = true);
    try {
      await _service.saveAylikPirim(pirim);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pirim kaydedildi.')));
      await _loadExisting();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Kaydetme hatası: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onayla() async {
    setState(() => _saving = true);
    try {
      await _service.onaylaAylikPirim(
          widget.userId, _yil, _ay, widget.onaylayanAdi);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pirim onaylandı.')));
      await _loadExisting();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _odemeYapildi() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ödeme Yapıldı'),
        content: Text(
            '${_currencyFmt.format(_pirim?.toplamPirim ?? 0)} tutarında ödeme yapıldı olarak işaretlensin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Evet')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    try {
      await _service.odemeYapildi(widget.userId, _yil, _ay);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ödeme yapıldı olarak işaretlendi.')));
      await _loadExisting();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _prevMonth() {
    setState(() {
      _ay = _ay == 1 ? 12 : _ay - 1;
      if (_ay == 12) _yil--;
      _pirim = null;
    });
    _loadExisting();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_yil == now.year && _ay == now.month) return;
    setState(() {
      _ay = _ay == 12 ? 1 : _ay + 1;
      if (_ay == 1) _yil++;
      _pirim = null;
    });
    _loadExisting();
  }

  static const _months = [
    '', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];

  String get _monthLabel => '${_months[_ay]} $_yil';

  @override
  Widget build(BuildContext context) {
    final pirim = _pirim;
    final now = DateTime.now();
    final isCurrentMonth = _yil == now.year && _ay == now.month;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.personelAdi} — Aylık Pirim'),
        actions: const [HomeIconButton()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                    _monthLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: (_loading || isCurrentMonth) ? null : _nextMonth,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (pirim == null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calculate_outlined,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text('Bu ay için kayıtlı pirim yok.'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _hesapla,
                      icon: const Icon(Icons.calculate_outlined),
                      label: const Text('Hesapla'),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildDurumBadge(pirim.durum),
                  const SizedBox(height: 16),

                  // Toplam
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Toplam Pirim',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(
                            _currencyFmt.format(pirim.toplamPirim),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Kategori detayları
                  if (pirim.kalemler.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Bu ay için işlem kaydı bulunamadı.',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Kategori Detayları',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            const SizedBox(height: 8),
                            const Divider(),
                            ...pirim.kalemler.map(_buildKalemRow),
                          ],
                        ),
                      ),
                    ),

                  // Onay bilgisi
                  if (pirim.onaylayan != null) ...[
                    const SizedBox(height: 8),
                    Card(
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: Colors.green, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Onaylayan: ${pirim.onaylayan}'
                                '${pirim.onayTarihi != null ? '\n${DateFormat('dd.MM.yyyy').format(pirim.onayTarihi!)}' : ''}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  _buildActions(pirim),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKalemRow(AylikPirimKalemi k) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            k.isSatis
                ? Icons.shopping_cart_outlined
                : Icons.medical_services_outlined,
            size: 18,
            color: k.isSatis ? Colors.blue : Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k.kategoriAdi,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(
                  '${_currencyFmt.format(k.toplam)} × %${_fmtOran(k.oran)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Text(
            _currencyFmt.format(k.pirim),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurumBadge(String durum) {
    final (label, color, icon) = switch (durum) {
      'onaylandi' => ('Onaylandı', Colors.blue, Icons.thumb_up_outlined),
      'odendi' => ('Ödendi', Colors.green, Icons.payments_outlined),
      _ => ('Onay Bekliyor', Colors.orange, Icons.hourglass_empty),
    };
    return Center(
      child: Chip(
        avatar: Icon(icon, size: 16, color: color),
        label: Text(label,
            style:
                TextStyle(color: color, fontWeight: FontWeight.w600)),
        backgroundColor: color.withAlpha(25),
        side: BorderSide(color: color.withAlpha(80)),
      ),
    );
  }

  Widget _buildActions(AylikPirim pirim) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (pirim.durum == 'bekliyor') ...[
          OutlinedButton.icon(
            onPressed: _saving ? null : _hesapla,
            icon: const Icon(Icons.refresh),
            label: const Text('Yeniden Hesapla'),
          ),
          OutlinedButton.icon(
            onPressed: _saving ? null : _kaydet,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Kaydet'),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _onayla,
            icon: const Icon(Icons.thumb_up_outlined),
            label: const Text('Onayla'),
          ),
        ] else if (pirim.durum == 'onaylandi') ...[
          FilledButton.icon(
            onPressed: _saving ? null : _odemeYapildi,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Ödeme Yapıldı'),
          ),
        ] else ...[
          Text('Ödeme tamamlandı.',
              style: TextStyle(color: Colors.green.shade700)),
        ],
      ],
    );
  }

  String _fmtOran(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
}
