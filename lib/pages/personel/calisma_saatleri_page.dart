import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../widgets/home_icon_button.dart';

class _CalismaGunu {
  bool aktif;
  TimeOfDay baslangic;
  TimeOfDay bitis;

  _CalismaGunu({
    required this.aktif,
    required this.baslangic,
    required this.bitis,
  });

  Map<String, dynamic> toMap() => {
        'aktif': aktif,
        'baslangic':
            '${baslangic.hour.toString().padLeft(2, '0')}:${baslangic.minute.toString().padLeft(2, '0')}',
        'bitis':
            '${bitis.hour.toString().padLeft(2, '0')}:${bitis.minute.toString().padLeft(2, '0')}',
      };

  factory _CalismaGunu.fromMap(Map<dynamic, dynamic> map) {
    return _CalismaGunu(
      aktif: (map['aktif'] as bool?) ?? false,
      baslangic: _parseTime((map['baslangic'] as String?) ?? '09:00'),
      bitis: _parseTime((map['bitis'] as String?) ?? '18:00'),
    );
  }

  static TimeOfDay _parseTime(String s) {
    final parts = s.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts[0] : '9') ?? 9,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
  }
}

class CalismaSaatleriPage extends StatefulWidget {
  const CalismaSaatleriPage({
    super.key,
    required this.userId,
    required this.personelAdi,
  });

  final String userId;
  final String personelAdi;

  @override
  State<CalismaSaatleriPage> createState() => _CalismaSaatleriPageState();
}

class _CalismaSaatleriPageState extends State<CalismaSaatleriPage> {
  static const _gunAdlari = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  late List<_CalismaGunu> _gunler;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _gunler = List.generate(
      7,
      (i) => _CalismaGunu(
        aktif: i < 5,
        baslangic: const TimeOfDay(hour: 9, minute: 0),
        bitis: const TimeOfDay(hour: 18, minute: 0),
      ),
    );
    _load();
  }

  Future<void> _load() async {
    final doc = await FirebaseFirestore.instance
        .collection('kullanicilar')
        .doc(widget.userId)
        .get();
    if (!mounted) return;
    final raw = doc.data()?['calismaGunleri'];
    if (raw is Map) {
      setState(() {
        _gunler = List.generate(7, (i) {
          final key = i.toString();
          if (raw.containsKey(key) && raw[key] is Map) {
            return _CalismaGunu.fromMap(raw[key] as Map);
          }
          return _gunler[i];
        });
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final map = {
        for (var i = 0; i < 7; i++) i.toString(): _gunler[i].toMap()
      };
      await FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(widget.userId)
          .update({'calismaGunleri': map});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Çalışma saatleri kaydedildi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kayıt hatası: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(int index, bool isStart) async {
    final current =
        isStart ? _gunler[index].baslangic : _gunler[index].bitis;
    final picked =
        await showTimePicker(context: context, initialTime: current);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _gunler[index].baslangic = picked;
      } else {
        _gunler[index].bitis = picked;
      }
    });
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.personelAdi} — Çalışma Saatleri'),
        actions: [
          const HomeIconButton(),
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            onPressed: _saving ? null : _save,
            tooltip: 'Kaydet',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: 7,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final gun = _gunler[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          _gunAdlari[i],
                          style: const TextStyle(
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      Switch(
                        value: gun.aktif,
                        onChanged: (v) =>
                            setState(() => gun.aktif = v),
                      ),
                      if (gun.aktif) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _pickTime(i, true),
                          child: Text(_fmtTime(gun.baslangic)),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('—'),
                        ),
                        OutlinedButton(
                          onPressed: () => _pickTime(i, false),
                          child: Text(_fmtTime(gun.bitis)),
                        ),
                      ] else
                        const Text('Çalışmıyor',
                            style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
