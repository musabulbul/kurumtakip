import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import '../../controllers/institution_controller.dart';
import '../../controllers/user_controller.dart';
import '../../utils/permission_utils.dart';

class IslemlerPage extends StatefulWidget {
  const IslemlerPage({super.key});

  @override
  State<IslemlerPage> createState() => _IslemlerPageState();
}

class _IslemlerPageState extends State<IslemlerPage> {
  final UserController _user = Get.find<UserController>();
  final InstitutionController _institution = Get.find<InstitutionController>();

  final EdgeInsets _pagePadding = const EdgeInsets.symmetric(horizontal: 16);

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  List<_MekanForIslem> _mekanlar = [];
  List<_PersonelForIslem> _personeller = [];

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
      _loadMekanlar();
    });
  }

  String _currentInstitutionId() =>
      (_institution.data['kurumkodu'] ?? '').toString();

  CollectionReference<Map<String, dynamic>> _categoryRef() =>
      FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(_currentInstitutionId())
          .collection('islemKategorileri');

  Future<void> _loadMekanlar() async {
    final id = _currentInstitutionId();
    if (id.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('kurumlar')
            .doc(id)
            .collection('mekanlar')
            .get(),
        FirebaseFirestore.instance
            .collection('kullanicilar')
            .where('kurumkodu', isEqualTo: id)
            .get(),
      ]);
      if (!mounted) return;

      final mekanSnap = results[0];
      final mekanlar = mekanSnap.docs
          .map((doc) {
            final data = doc.data();
            return _MekanForIslem(
              id: doc.id,
              name: (data['adi'] ?? '').toString().trim(),
              sequence: _parseInt(data['siraNo']),
            );
          })
          .where((m) => m.name.isNotEmpty)
          .toList()
        ..sort((a, b) {
          final sa = a.sequence > 0 ? a.sequence : 1 << 30;
          final sb = b.sequence > 0 ? b.sequence : 1 << 30;
          return sa != sb ? sa.compareTo(sb) : a.name.compareTo(b.name);
        });

      final personelSnap = results[1];
      final personeller = personelSnap.docs
          .map((doc) {
            final data = doc.data();
            final durum = (data['durum'] ?? 'aktif').toString();
            if (durum == 'ayrildi') return null;
            final adi = (data['adi'] ?? '').toString().trim();
            final soyadi = (data['soyadi'] ?? '').toString().trim();
            final ad = [adi, soyadi].where((s) => s.isNotEmpty).join(' ');
            if (ad.isEmpty) return null;
            return _PersonelForIslem(id: doc.id, name: ad);
          })
          .whereType<_PersonelForIslem>()
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      setState(() {
        _mekanlar = mekanlar;
        _personeller = personeller;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _parseInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  // ─── Category CRUD ────────────────────────────────────────────────────────

  Future<void> _openCategoryDialog({_IslemCategory? category}) async {
    if (_isSaving) return;
    final result = await _showCategoryDialog(category: category);
    if (result == null) return;
    if (category == null) {
      await _createCategory(result);
    } else {
      await _updateCategory(category, result);
    }
  }

  Future<_CategoryFormResult?> _showCategoryDialog(
      {_IslemCategory? category}) async {
    final nameController =
        TextEditingController(text: category?.name ?? '');
    return showDialog<_CategoryFormResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(category == null ? 'Kategori Ekle' : 'Kategori Güncelle'),
        content: TextField(
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Kategori adı',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                _showSnack('Kategori adı boş bırakılamaz.');
                return;
              }
              Navigator.of(context)
                  .pop(_CategoryFormResult(name: name));
            },
            child: Text(category == null ? 'Ekle' : 'Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _createCategory(_CategoryFormResult result) async {
    final id = _currentInstitutionId();
    if (id.isEmpty) {
      _showSnack('Kurum bilgisine ulaşılamadı.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _categoryRef().add({
        'adi': result.name,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _showSnack('Kategori eklendi.');
    } catch (e) {
      _showSnack('Kategori eklenemedi: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _updateCategory(
      _IslemCategory category, _CategoryFormResult result) async {
    setState(() => _isSaving = true);
    try {
      await _categoryRef().doc(category.id).set(
            {'adi': result.name, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
      _showSnack('Kategori güncellendi.');
    } catch (e) {
      _showSnack('Kategori güncellenemedi: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteCategory(_IslemCategory category) async {
    if (_isSaving) return;
    final ok = await _confirmDialog(
        'Kategori Silinsin mi?',
        '${category.name} kategorisi ve içindeki tüm işlemler silinecek. Emin misiniz?');
    if (ok != true) return;
    setState(() => _isSaving = true);
    try {
      await _deleteCategoryWithItems(category);
      _showSnack('Kategori silindi.');
    } catch (e) {
      _showSnack('Kategori silinemedi: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteCategoryWithItems(_IslemCategory category) async {
    final ref =
        _categoryRef().doc(category.id).collection('islemler');
    final snap = await ref.get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_categoryRef().doc(category.id));
    await batch.commit();
  }

  // ─── İşlem CRUD ───────────────────────────────────────────────────────────

  Future<void> _openOperationDialog({
    required _IslemCategory category,
    _IslemItem? item,
  }) async {
    if (_isSaving) return;
    final result = await _showOperationDialog(item: item);
    if (result == null) return;
    if (item == null) {
      await _createOperation(category, result);
    } else {
      await _updateOperation(category, item, result);
    }
  }

  Future<_OperationFormResult?> _showOperationDialog(
      {_IslemItem? item}) async {
    final nameController =
        TextEditingController(text: item?.name ?? '');
    final priceController = TextEditingController(
        text: item == null ? '' : _formatPrice(item.price));
    final sessionController =
        TextEditingController(text: item?.sessionCount.toString() ?? '');
    final durationController = TextEditingController(
        text: item?.durationMinutes == 0
            ? ''
            : (item?.durationMinutes.toString() ?? ''));

    final selectedMekanIds = <String>{...(item?.mekanIds ?? const [])};
    final selectedPersonelIds = <String>{...(item?.personelIds ?? const [])};
    var onlineActive = item?.onlineActive ?? true;
    var malzemeKullan = item?.malzemeKullan ?? false;
    final malzemeler = <Map<String, dynamic>>[...(item?.malzemeler ?? const [])];

    return showDialog<_OperationFormResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(item == null ? 'İşlem Ekle' : 'İşlem Güncelle'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'İşlem adı',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Fiyat (TL)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: sessionController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Seans sayısı',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Süre (dakika) — Online randevu için',
                      hintText: 'ör: 30',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Online randevuda aktif'),
                    subtitle: const Text(
                        'Danışanlar bu hizmeti online randevuda seçebilir'),
                    value: onlineActive,
                    onChanged: (v) =>
                        setDialogState(() => onlineActive = v),
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Malzeme Kullan'),
                    subtitle: const Text('İşlem yapıldığında seçilen malzemeler stoktan düşülür'),
                    value: malzemeKullan,
                    onChanged: (v) => setDialogState(() => malzemeKullan = v),
                  ),
                  if (malzemeKullan) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Malzeme Listesi', style: Theme.of(ctx).textTheme.labelLarge),
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Ekle'),
                          onPressed: () async {
                            final kurumkodu = _currentInstitutionId();
                            if (kurumkodu.isEmpty) return;
                            try {
                              final snap = await FirebaseFirestore.instance
                                  .collection('kurumlar')
                                  .doc(kurumkodu)
                                  .collection('tuketimUrunler')
                                  .orderBy('ad')
                                  .get();
                              final urunler = snap.docs
                                  .map((d) {
                                    final data = d.data();
                                    return <String, dynamic>{
                                      'id': d.id,
                                      'ad': (data['ad'] ?? '').toString(),
                                      'cikisUnit': (data['cikisUnit'] ?? '').toString(),
                                      'icerikMiktari': (data['icerikMiktari'] is num
                                          ? (data['icerikMiktari'] as num).toDouble()
                                          : 1.0),
                                    };
                                  })
                                  .where((u) => (u['ad'] as String).isNotEmpty)
                                  .toList();
                              if (!ctx.mounted) return;
                              if (urunler.isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('Henüz tüketim ürünü tanımlanmamış.')),
                                );
                                return;
                              }
                              final result = await showDialog<Map<String, dynamic>>(
                                context: ctx,
                                builder: (innerCtx) {
                                  Map<String, dynamic>? selected = urunler.first;
                                  final qtyController = TextEditingController();
                                  return StatefulBuilder(
                                    builder: (ic, setInner) => AlertDialog(
                                      title: const Text('Malzeme Ekle'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          DropdownButtonFormField<Map<String, dynamic>>(
                                            value: selected,
                                            items: urunler
                                                .map((u) => DropdownMenuItem(
                                                      value: u,
                                                      child: Text((u['ad'] as String)),
                                                    ))
                                                .toList(),
                                            onChanged: (v) => setInner(() => selected = v),
                                            decoration: const InputDecoration(
                                              labelText: 'Malzeme',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller: qtyController,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: InputDecoration(
                                              labelText: 'Miktar',
                                              suffixText: selected?['cikisUnit']?.toString() ?? '',
                                              border: const OutlineInputBorder(),
                                            ),
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(innerCtx).pop(),
                                          child: const Text('İptal'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () {
                                            if (selected == null) return;
                                            final raw = qtyController.text.trim().replaceAll(',', '.');
                                            final qty = double.tryParse(raw);
                                            if (qty == null || qty <= 0) return;
                                            final res = <String, dynamic>{
                                              'urunId': selected!['id'],
                                              'urunAdi': selected!['ad'],
                                              'cikisUnit': selected!['cikisUnit'],
                                              'icerikMiktari': selected!['icerikMiktari'],
                                              'miktar': qty,
                                            };
                                            qtyController.dispose();
                                            Navigator.of(innerCtx).pop(res);
                                          },
                                          child: const Text('Ekle'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                              if (result != null) {
                                setDialogState(() => malzemeler.add(result));
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text('Malzemeler yüklenemedi: $e')),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    if (malzemeler.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Henüz malzeme eklenmedi.',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      )
                    else
                      ...malzemeler.asMap().entries.map((e) {
                        final idx = e.key;
                        final m = e.value;
                        final miktarStr = (m['miktar'] is num)
                            ? (m['miktar'] as num).toStringAsFixed(2)
                            : '-';
                        final unit = (m['cikisUnit'] ?? '').toString();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text((m['urunAdi'] ?? '').toString()),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$miktarStr $unit',
                                  style: Theme.of(ctx).textTheme.bodySmall),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                iconSize: 18,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setDialogState(() => malzemeler.removeAt(idx)),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                  if (_mekanlar.isNotEmpty) ...[
                    const Divider(height: 24),
                    Text(
                      'Geçerli Mekanlar',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    ..._mekanlar.map((mekan) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(mekan.name),
                          value: selectedMekanIds.contains(mekan.id),
                          onChanged: (v) => setDialogState(() {
                            if (v == true) {
                              selectedMekanIds.add(mekan.id);
                            } else {
                              selectedMekanIds.remove(mekan.id);
                            }
                          }),
                        )),
                    const SizedBox(height: 4),
                    Text(
                      selectedMekanIds.isEmpty
                          ? 'Seçili mekan yok — tüm mekanlarda geçerli'
                          : '${selectedMekanIds.length} mekan seçili',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                  if (_personeller.isNotEmpty) ...[
                    const Divider(height: 24),
                    Text(
                      'Geçerli Personel',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    ..._personeller.map((p) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(p.name),
                          value: selectedPersonelIds.contains(p.id),
                          onChanged: (v) => setDialogState(() {
                            if (v == true) {
                              selectedPersonelIds.add(p.id);
                            } else {
                              selectedPersonelIds.remove(p.id);
                            }
                          }),
                        )),
                    const SizedBox(height: 4),
                    Text(
                      selectedPersonelIds.isEmpty
                          ? 'Seçili personel yok — tüm personel geçerli'
                          : '${selectedPersonelIds.length} personel seçili',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('İptal')),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  _showSnack('İşlem adı boş bırakılamaz.');
                  return;
                }
                final rawPrice = priceController.text.trim();
                final double? parsedPrice =
                    rawPrice.isEmpty ? 0.0 : _tryParsePrice(rawPrice);
                if (parsedPrice == null || parsedPrice < 0) {
                  _showSnack(
                      'Fiyat boş, 0 veya pozitif bir değer olmalı.');
                  return;
                }
                final sessionCount =
                    int.tryParse(sessionController.text.trim()) ?? 0;
                if (sessionCount <= 0) {
                  _showSnack('Seans sayısı 1 veya daha büyük olmalı.');
                  return;
                }
                final durationMinutes =
                    int.tryParse(durationController.text.trim()) ?? 0;
                Navigator.of(context).pop(_OperationFormResult(
                  name: name,
                  price: parsedPrice,
                  sessionCount: sessionCount,
                  durationMinutes: durationMinutes,
                  onlineActive: onlineActive,
                  mekanIds: selectedMekanIds.toList(),
                  personelIds: selectedPersonelIds.toList(),
                  malzemeKullan: malzemeKullan,
                  malzemeler: List<Map<String, dynamic>>.from(malzemeler),
                ));
              },
              child: Text(item == null ? 'Ekle' : 'Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createOperation(
      _IslemCategory category, _OperationFormResult result) async {
    setState(() => _isSaving = true);
    try {
      await _categoryRef()
          .doc(category.id)
          .collection('islemler')
          .add({
        'adi': result.name,
        'fiyat': result.price,
        'seansSayisi': result.sessionCount,
        'sureDakika': result.durationMinutes,
        'onlineAktif': result.onlineActive,
        'mekanIds': result.mekanIds,
        'personelIds': result.personelIds,
        'malzemeKullan': result.malzemeKullan,
        'malzemeler': result.malzemeler,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _showSnack('İşlem eklendi.');
    } catch (e) {
      _showSnack('İşlem eklenemedi: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _updateOperation(
      _IslemCategory category,
      _IslemItem item,
      _OperationFormResult result) async {
    setState(() => _isSaving = true);
    try {
      await _categoryRef()
          .doc(category.id)
          .collection('islemler')
          .doc(item.id)
          .set(
            {
              'adi': result.name,
              'fiyat': result.price,
              'seansSayisi': result.sessionCount,
              'sureDakika': result.durationMinutes,
              'onlineAktif': result.onlineActive,
              'mekanIds': result.mekanIds,
              'personelIds': result.personelIds,
              'malzemeKullan': result.malzemeKullan,
              'malzemeler': result.malzemeler,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
      _showSnack('İşlem güncellendi.');
    } catch (e) {
      _showSnack('İşlem güncellenemedi: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteOperation(
      _IslemCategory category, _IslemItem item) async {
    if (_isSaving) return;
    final ok = await _confirmDialog(
        'İşlem Silinsin mi?',
        '${item.name} işlemini silmek istediğinize emin misiniz?');
    if (ok != true) return;
    setState(() => _isSaving = true);
    try {
      await _categoryRef()
          .doc(category.id)
          .collection('islemler')
          .doc(item.id)
          .delete();
      _showSnack('İşlem silindi.');
    } catch (e) {
      _showSnack('İşlem silinemedi: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  Future<bool?> _confirmDialog(String title, String content) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Vazgeç')),
            ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sil')),
          ],
        ),
      );

  double _parsePrice(String value) => _tryParsePrice(value) ?? 0;

  double? _tryParsePrice(String value) {
    final normalized = value.replaceAll(',', '.').trim();
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  String _formatPrice(double price) {
    if (price % 1 == 0) return price.toStringAsFixed(0);
    return price.toStringAsFixed(2);
  }

  String _mekanName(String id) {
    for (final m in _mekanlar) {
      if (m.id == id) return m.name;
    }
    return id;
  }

  String _personelName(String id) {
    for (final p in _personeller) {
      if (p.id == id) return p.name;
    }
    return id;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('İşlemler'),
        actions: const [HomeIconButton()],
      ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _isSaving ? null : () => _openCategoryDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Kategori Ekle'),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: _pagePadding,
          child: Text(_errorMessage!, textAlign: TextAlign.center),
        ),
      );
    }

    final institutionId = _currentInstitutionId();
    if (institutionId.isEmpty) {
      return const Center(
          child: Text('Kurum bilgisine ulaşılamadı.',
              textAlign: TextAlign.center));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _categoryRef().orderBy('adi').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Kategoriler yüklenemedi.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final categories = snapshot.data!.docs
            .map((doc) => _IslemCategory(
                  id: doc.id,
                  name: (doc.data()['adi'] ?? '').toString(),
                ))
            .toList();

        if (categories.isEmpty) {
          return ListView(
            padding: _pagePadding.copyWith(top: 48, bottom: 24),
            children: const [
              Icon(Icons.category_outlined, size: 48),
              SizedBox(height: 16),
              Text('Henüz kategori eklenmedi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text(
                  'Yeni kategori eklemek için sağ alttaki butonu kullanabilirsiniz.',
                  textAlign: TextAlign.center),
            ],
          );
        }

        return ListView.separated(
          padding: _pagePadding.copyWith(top: 16, bottom: 80),
          itemCount: categories.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final category = categories[index];
            return Card(
              child: ExpansionTile(
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(category.name.isEmpty
                    ? 'İsimsiz Kategori'
                    : category.name),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'İşlem ekle',
                      onPressed: _isSaving
                          ? null
                          : () => _openOperationDialog(
                              category: category),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Kategoriyi düzenle',
                      onPressed: _isSaving
                          ? null
                          : () => _openCategoryDialog(
                              category: category),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Kategoriyi sil',
                      onPressed: _isSaving
                          ? null
                          : () => _deleteCategory(category),
                    ),
                  ],
                ),
                children: [_buildOperationList(category)],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOperationList(_IslemCategory category) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _categoryRef()
          .doc(category.id)
          .collection('islemler')
          .orderBy('adi')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
              padding: EdgeInsets.all(16),
              child: Text('İşlemler yüklenemedi.'));
        }
        if (!snapshot.hasData) {
          return const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(minHeight: 2));
        }

        final items = snapshot.data!.docs.map((doc) {
          final data = doc.data();
          final rawMekanIds = data['mekanIds'];
          final rawPersonelIds = data['personelIds'];
          return _IslemItem(
            id: doc.id,
            name: (data['adi'] ?? '').toString(),
            price: _parsePriceValue(data['fiyat']),
            sessionCount: _parseIntValue(data['seansSayisi']),
            durationMinutes: _parseIntValue(data['sureDakika']),
            onlineActive: data['onlineAktif'] != false,
            mekanIds: rawMekanIds is List
                ? rawMekanIds.whereType<String>().toList()
                : const [],
            personelIds: rawPersonelIds is List
                ? rawPersonelIds.whereType<String>().toList()
                : const [],
            malzemeKullan: data['malzemeKullan'] == true,
            malzemeler: _parseIslemMalzemeList(data['malzemeler']),
          );
        }).toList();

        if (items.isEmpty) {
          return const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Bu kategoride işlem yok.'));
        }

        return Column(
          children: items.map((item) {
            return ListTile(
              title: Row(
                children: [
                  Expanded(
                      child: Text(item.name.isEmpty
                          ? 'İsimsiz İşlem'
                          : item.name)),
                  if (item.onlineActive)
                    Tooltip(
                      message: 'Online randevuda aktif',
                      child: Icon(Icons.language_rounded,
                          size: 16, color: cs.primary),
                    )
                  else
                    Tooltip(
                      message: 'Online randevuda pasif',
                      child: Icon(Icons.language_outlined,
                          size: 16,
                          color: cs.onSurfaceVariant
                              .withValues(alpha: 0.4)),
                    ),
                  if (item.malzemeKullan) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: '${item.malzemeler.length} malzeme tanımlı',
                      child: Icon(Icons.science_outlined,
                          size: 16, color: cs.secondary),
                    ),
                  ],
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      '${_formatPrice(item.price)} TL',
                      '${item.sessionCount} seans',
                      if (item.durationMinutes > 0)
                        '${item.durationMinutes} dk',
                    ].join(' • '),
                  ),
                  if (_mekanlar.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: item.mekanIds.isEmpty
                          ? [
                              _MekanChip(
                                  label: 'Tüm Mekanlar',
                                  isAll: true,
                                  cs: cs),
                            ]
                          : item.mekanIds
                              .map((id) => _MekanChip(
                                  label: _mekanName(id),
                                  isAll: false,
                                  cs: cs))
                              .toList(),
                    ),
                  ],
                  if (_personeller.isNotEmpty && item.personelIds.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: item.personelIds
                          .map((id) => _MekanChip(
                              label: _personelName(id),
                              isAll: false,
                              cs: cs))
                          .toList(),
                    ),
                  ],
                ],
              ),
              isThreeLine: _mekanlar.isNotEmpty || item.personelIds.isNotEmpty,
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'İşlemi düzenle',
                    onPressed: _isSaving
                        ? null
                        : () => _openOperationDialog(
                            category: category, item: item),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'İşlemi sil',
                    onPressed: _isSaving
                        ? null
                        : () => _deleteOperation(category, item),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  double _parsePriceValue(dynamic value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    return _parsePrice(value?.toString() ?? '');
  }

  int _parseIntValue(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<Map<String, dynamic>> _parseIslemMalzemeList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}

// ─── Widgets ─────────────────────────────────────────────────────────────────

class _MekanChip extends StatelessWidget {
  const _MekanChip(
      {required this.label, required this.isAll, required this.cs});

  final String label;
  final bool isAll;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isAll
            ? cs.surfaceContainerHighest
            : cs.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              isAll ? cs.outlineVariant : cs.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: isAll ? cs.onSurfaceVariant : cs.onPrimaryContainer,
        ),
      ),
    );
  }
}

// ─── Data classes ─────────────────────────────────────────────────────────────

class _MekanForIslem {
  const _MekanForIslem(
      {required this.id, required this.name, required this.sequence});

  final String id;
  final String name;
  final int sequence;
}

class _PersonelForIslem {
  const _PersonelForIslem({required this.id, required this.name});

  final String id;
  final String name;
}

class _IslemCategory {
  const _IslemCategory({required this.id, required this.name});

  final String id;
  final String name;
}

class _IslemItem {
  const _IslemItem({
    required this.id,
    required this.name,
    required this.price,
    required this.sessionCount,
    required this.durationMinutes,
    required this.onlineActive,
    required this.mekanIds,
    this.personelIds = const [],
    this.malzemeKullan = false,
    this.malzemeler = const [],
  });

  final String id;
  final String name;
  final double price;
  final int sessionCount;
  final int durationMinutes;
  final bool onlineActive;
  final List<String> mekanIds;
  final List<String> personelIds;
  final bool malzemeKullan;
  final List<Map<String, dynamic>> malzemeler;
}

class _CategoryFormResult {
  const _CategoryFormResult({required this.name});

  final String name;
}

class _OperationFormResult {
  const _OperationFormResult({
    required this.name,
    required this.price,
    required this.sessionCount,
    required this.durationMinutes,
    required this.onlineActive,
    required this.mekanIds,
    this.personelIds = const [],
    this.malzemeKullan = false,
    this.malzemeler = const [],
  });

  final String name;
  final double price;
  final int sessionCount;
  final int durationMinutes;
  final bool onlineActive;
  final List<String> mekanIds;
  final List<String> personelIds;
  final bool malzemeKullan;
  final List<Map<String, dynamic>> malzemeler;
}
