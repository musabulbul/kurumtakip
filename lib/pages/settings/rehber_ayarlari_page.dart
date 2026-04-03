import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/institution_controller.dart';
import '../../controllers/user_controller.dart';
import '../../utils/text_utils.dart';
import '../../widgets/home_icon_button.dart';

const _kPrefPrefix = 'contact_name_prefix';
const _kPrefSuffix = 'contact_name_suffix';

class RehberAyarlariPage extends StatefulWidget {
  const RehberAyarlariPage({super.key});

  @override
  State<RehberAyarlariPage> createState() => _RehberAyarlariPageState();
}

class _RehberAyarlariPageState extends State<RehberAyarlariPage> {
  final _prefixController = TextEditingController();
  final _suffixController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _prefixController.addListener(() => setState(() {}));
    _suffixController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _suffixController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefixController.text = prefs.getString(_kPrefPrefix) ?? '';
      _suffixController.text = prefs.getString(_kPrefSuffix) ?? '';
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefPrefix, _prefixController.text);
    await prefs.setString(_kPrefSuffix, _suffixController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ayarlar kaydedildi')),
    );
  }

  String get _previewName {
    final prefix = _prefixController.text;
    final suffix = _suffixController.text;
    return '${prefix}Ahmet Yılmaz$suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Telefon Rehberi Ayarları'),
        actions: const [HomeIconButton()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kayıt Formatı',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Danışan telefon rehberine eklenirken ismin başına veya sonuna eklenecek metni belirleyin.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _prefixController,
                          decoration: const InputDecoration(
                            labelText: 'Önek',
                            hintText: 'örn: D - ',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _suffixController,
                          decoration: const InputDecoration(
                            labelText: 'Sonek',
                            hintText: 'örn:  (Danışan)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Önizleme',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _previewName,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _saveSettings,
                            child: const Text('Kaydet'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.contacts_outlined,
                          color: kIsWeb ? Colors.grey : null,
                        ),
                        title: Text(
                          'Rehberden Toplu İçe Aktar',
                          style: kIsWeb
                              ? TextStyle(color: Colors.grey[600])
                              : null,
                        ),
                        subtitle: const Text(
                            'Telefon rehberindeki kişileri danışan olarak aktar'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: kIsWeb
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const _ContactImportPage()),
                                );
                              },
                      ),
                      if (kIsWeb)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 14, color: Colors.orange[700]),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Bu özellik yalnızca Android ve iOS uygulamasında kullanılabilir.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Rehberden Toplu Aktarım Sayfası ─────────────────────────────────────────

class _ContactImportPage extends StatefulWidget {
  const _ContactImportPage();

  @override
  State<_ContactImportPage> createState() => _ContactImportPageState();
}

class _ContactImportPageState extends State<_ContactImportPage> {
  final InstitutionController _kurum = Get.find<InstitutionController>();
  final UserController _user = Get.find<UserController>();

  List<Contact> _contacts = [];
  final Set<String> _selected = {};
  String _search = '';
  bool _loading = true;
  bool _importing = false;
  String? _permissionError;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _loading = true;
      _permissionError = null;
    });

    if (kIsWeb) {
      setState(() {
        _permissionError = 'Telefon rehberi erişimi web tarayıcısında desteklenmiyor.';
        _loading = false;
      });
      return;
    }

    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _permissionError = 'Rehber izni verilmedi. Ayarlardan izin verin.';
        _loading = false;
      });
      return;
    }

    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final withPhone = contacts.where((c) => c.phones.isNotEmpty).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    if (!mounted) return;
    setState(() {
      _contacts = withPhone;
      _loading = false;
    });
  }

  List<Contact> get _filtered {
    if (_search.isEmpty) return _contacts;
    final q = _search.toLowerCase();
    return _contacts.where((c) => c.displayName.toLowerCase().contains(q)).toList();
  }

  Future<void> _import() async {
    if (_selected.isEmpty) return;

    final kurumKodu = (_kurum.data['kurumkodu'] ?? '').toString();
    if (kurumKodu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kurum bilgisi alınamadı')),
      );
      return;
    }

    setState(() => _importing = true);

    final toImport = _contacts.where((c) => _selected.contains(c.id)).toList();
    final ekleyenAdi =
        '${_user.data['adi'] ?? ''} ${_user.data['soyadi'] ?? ''}'.trim();
    final ref = FirebaseFirestore.instance
        .collection('kurumlar')
        .doc(kurumKodu)
        .collection('danisanlar');

    int added = 0;
    int skipped = 0;
    int failed = 0;

    for (final contact in toImport) {
      try {
        final rawPhone = contact.phones.first.number;
        final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
        var normalized = digits;
        if (normalized.startsWith('90') && normalized.length == 12) {
          normalized = normalized.substring(2);
        } else if (normalized.startsWith('0') && normalized.length == 11) {
          normalized = normalized.substring(1);
        }

        if (normalized.isEmpty) {
          skipped++;
          continue;
        }

        final candidates = [
          normalized,
          '0$normalized',
          '90$normalized',
          '+90$normalized',
        ];

        final existing =
            await ref.where('telefon', whereIn: candidates).limit(1).get();
        if (existing.docs.isNotEmpty) {
          skipped++;
          continue;
        }

        final nameParts = contact.displayName
            .trim()
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .toList();
        String firstName = contact.displayName.trim();
        String lastName = '';
        if (nameParts.length >= 2) {
          lastName = toTitleCaseTr(nameParts.removeLast());
          firstName = toTitleCaseTr(nameParts.join(' '));
        } else {
          firstName = toTitleCaseTr(firstName);
        }

        final docRef = ref.doc();
        await docRef.set({
          'id': docRef.id,
          'adi': firstName,
          'soyadi': lastName,
          'telefon': '+90$normalized',
          'adres': '',
          'kurumkodu': kurumKodu,
          if (ekleyenAdi.isNotEmpty) 'ekleyen': ekleyenAdi,
          'kayittarihi': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'olusturulmaZamani': Timestamp.now(),
        });

        added++;
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() => _importing = false);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aktarım Tamamlandı'),
        content: Text([
          '$added danışan eklendi',
          if (skipped > 0) '$skipped kişi zaten kayıtlıydı, atlandı',
          if (failed > 0) '$failed kişi aktarılamadı',
        ].join('\n')),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (added > 0) Navigator.of(context).pop();
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final allSelected =
        filtered.isNotEmpty && filtered.every((c) => _selected.contains(c.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selected.isEmpty
              ? 'Rehberden İçe Aktar'
              : '${_selected.length} kişi seçildi',
        ),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: _importing ? null : _import,
              child: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Aktar (${_selected.length})'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _permissionError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.contacts_outlined,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _permissionError!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadContacts,
                          child: const Text('Tekrar Dene'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Kişi ara...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            '${filtered.length} kişi',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                if (allSelected) {
                                  _selected.removeAll(
                                      filtered.map((c) => c.id));
                                } else {
                                  _selected
                                      .addAll(filtered.map((c) => c.id));
                                }
                              });
                            },
                            child: Text(
                                allSelected ? 'Seçimi Kaldır' : 'Tümünü Seç'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final contact = filtered[i];
                          final isSelected =
                              _selected.contains(contact.id);
                          final phone = contact.phones.isNotEmpty
                              ? contact.phones.first.number
                              : '';
                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: _importing
                                ? null
                                : (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selected.add(contact.id);
                                      } else {
                                        _selected.remove(contact.id);
                                      }
                                    });
                                  },
                            title: Text(contact.displayName),
                            subtitle: phone.isNotEmpty ? Text(phone) : null,
                            secondary: CircleAvatar(
                              child: Text(
                                contact.displayName.isNotEmpty
                                    ? contact.displayName[0].toUpperCase()
                                    : '?',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
