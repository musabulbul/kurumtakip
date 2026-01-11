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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!isManagerUser(_user.data)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu sayfaya sadece yöneticiler erişebilir.'),
          ),
        );
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        _isLoading = false;
      });
    });
  }

  String _currentInstitutionId() {
    return (_institution.data['kurumkodu'] ?? '').toString();
  }

  CollectionReference<Map<String, dynamic>> _categoryRef() {
    return FirebaseFirestore.instance
        .collection('kurumlar')
        .doc(_currentInstitutionId())
        .collection('islemKategorileri');
  }

  Future<void> _openCategoryDialog({_IslemCategory? category}) async {
    if (_isSaving) {
      return;
    }
    final result = await _showCategoryDialog(category: category);
    if (result == null) {
      return;
    }
    if (category == null) {
      await _createCategory(result);
    } else {
      await _updateCategory(category, result);
    }
  }

  Future<_CategoryFormResult?> _showCategoryDialog({_IslemCategory? category}) async {
    final nameController = TextEditingController(text: category?.name ?? '');
    return showDialog<_CategoryFormResult>(
      context: context,
      builder: (context) {
        return AlertDialog(
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
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  _showSnack('Kategori adı boş bırakılamaz.');
                  return;
                }
                Navigator.of(context).pop(_CategoryFormResult(name: name));
              },
              child: Text(category == null ? 'Ekle' : 'Kaydet'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createCategory(_CategoryFormResult result) async {
    final institutionId = _currentInstitutionId();
    if (institutionId.isEmpty) {
      _showSnack('Kurum bilgisine ulaşılamadı.');
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      await _categoryRef().add({
        'adi': result.name,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _showSnack('Kategori eklendi.');
    } catch (error) {
      _showSnack('Kategori eklenemedi: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _updateCategory(_IslemCategory category, _CategoryFormResult result) async {
    setState(() {
      _isSaving = true;
    });
    try {
      await _categoryRef().doc(category.id).set(
        {
          'adi': result.name,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      _showSnack('Kategori güncellendi.');
    } catch (error) {
      _showSnack('Kategori güncellenemedi: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteCategory(_IslemCategory category) async {
    if (_isSaving) {
      return;
    }
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kategori Silinsin mi?'),
          content: Text(
            '${category.name} kategorisini silmek istediğinize emin misiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _deleteCategoryWithItems(category);
      _showSnack('Kategori silindi.');
    } catch (error) {
      _showSnack('Kategori silinemedi: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteCategoryWithItems(_IslemCategory category) async {
    final operationsRef = _categoryRef().doc(category.id).collection('islemler');
    final snapshot = await operationsRef.get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_categoryRef().doc(category.id));
    await batch.commit();
  }

  Future<void> _openOperationDialog({
    required _IslemCategory category,
    _IslemItem? item,
  }) async {
    if (_isSaving) {
      return;
    }
    final result = await _showOperationDialog(item: item);
    if (result == null) {
      return;
    }
    if (item == null) {
      await _createOperation(category, result);
    } else {
      await _updateOperation(category, item, result);
    }
  }

  Future<_OperationFormResult?> _showOperationDialog({_IslemItem? item}) async {
    final nameController = TextEditingController(text: item?.name ?? '');
    final priceController = TextEditingController(
      text: item == null ? '' : _formatPrice(item.price),
    );
    final sessionController = TextEditingController(
      text: item?.sessionCount.toString() ?? '',
    );

    return showDialog<_OperationFormResult>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(item == null ? 'İşlem Ekle' : 'İşlem Güncelle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Fiyat (TL)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sessionController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Seans sayısı',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  _showSnack('İşlem adı boş bırakılamaz.');
                  return;
                }
                final rawPrice = priceController.text.trim();
                final parsedPrice = _parsePrice(rawPrice);
                if (parsedPrice <= 0) {
                  _showSnack('Fiyat 0\'dan büyük olmalı.');
                  return;
                }
                final sessionCount =
                    int.tryParse(sessionController.text.trim()) ?? 0;
                if (sessionCount <= 0) {
                  _showSnack('Seans sayısı 1 veya daha büyük olmalı.');
                  return;
                }
                Navigator.of(context).pop(
                  _OperationFormResult(
                    name: name,
                    price: parsedPrice,
                    sessionCount: sessionCount,
                  ),
                );
              },
              child: Text(item == null ? 'Ekle' : 'Kaydet'),
            ),
          ],
        );
      },
    );
  }

  double _parsePrice(String value) {
    final normalized = value.replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }

  String _formatPrice(double price) {
    if (price % 1 == 0) {
      return price.toStringAsFixed(0);
    }
    return price.toStringAsFixed(2);
  }

  Future<void> _createOperation(
    _IslemCategory category,
    _OperationFormResult result,
  ) async {
    setState(() {
      _isSaving = true;
    });
    try {
      await _categoryRef().doc(category.id).collection('islemler').add({
        'adi': result.name,
        'fiyat': result.price,
        'seansSayisi': result.sessionCount,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _showSnack('İşlem eklendi.');
    } catch (error) {
      _showSnack('İşlem eklenemedi: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _updateOperation(
    _IslemCategory category,
    _IslemItem item,
    _OperationFormResult result,
  ) async {
    setState(() {
      _isSaving = true;
    });
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
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      _showSnack('İşlem güncellendi.');
    } catch (error) {
      _showSnack('İşlem güncellenemedi: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteOperation(_IslemCategory category, _IslemItem item) async {
    if (_isSaving) {
      return;
    }
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('İşlem Silinsin mi?'),
          content: Text(
            '${item.name} işlemini silmek istediğinize emin misiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      await _categoryRef()
          .doc(category.id)
          .collection('islemler')
          .doc(item.id)
          .delete();
      _showSnack('İşlem silindi.');
    } catch (error) {
      _showSnack('İşlem silinemedi: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

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
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      );
    }

    final institutionId = _currentInstitutionId();
    if (institutionId.isEmpty) {
      return Center(
        child: Padding(
          padding: _pagePadding,
          child: const Text(
            'Kurum bilgisine ulaşılamadı.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _categoryRef().orderBy('adi').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: _pagePadding,
              child: const Text(
                'Kategoriler yüklenemedi.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final categories = snapshot.data!.docs
            .map(
              (doc) => _IslemCategory(
                id: doc.id,
                name: (doc.data()['adi'] ?? '').toString(),
              ),
            )
            .toList();

        if (categories.isEmpty) {
          return ListView(
            padding: _pagePadding.copyWith(top: 48, bottom: 24),
            children: const [
              Icon(Icons.category_outlined, size: 48),
              SizedBox(height: 16),
              Text(
                'Henüz kategori eklenmedi.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Yeni kategori eklemek için sağ alttaki butonu kullanabilirsiniz.',
                textAlign: TextAlign.center,
              ),
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
                title: Text(category.name.isEmpty ? 'İsimsiz Kategori' : category.name),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'İşlem ekle',
                      onPressed: _isSaving
                          ? null
                          : () => _openOperationDialog(category: category),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Kategoriyi düzenle',
                      onPressed: _isSaving
                          ? null
                          : () => _openCategoryDialog(category: category),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Kategoriyi sil',
                      onPressed:
                          _isSaving ? null : () => _deleteCategory(category),
                    ),
                  ],
                ),
                children: [
                  _buildOperationList(category),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOperationList(_IslemCategory category) {
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
            child: Text('İşlemler yüklenemedi.'),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }

        final items = snapshot.data!.docs
            .map(
              (doc) => _IslemItem(
                id: doc.id,
                name: (doc.data()['adi'] ?? '').toString(),
                price: _parsePriceValue(doc.data()['fiyat']),
                sessionCount: _parseSessionCount(doc.data()['seansSayisi']),
              ),
            )
            .toList();

        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Bu kategoride işlem yok.'),
          );
        }

        return Column(
          children: items.map((item) {
            return ListTile(
              title: Text(item.name.isEmpty ? 'İsimsiz İşlem' : item.name),
              subtitle: Text(
                'Fiyat: ${_formatPrice(item.price)} TL • Seans: ${item.sessionCount}',
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'İşlemi düzenle',
                    onPressed: _isSaving
                        ? null
                        : () => _openOperationDialog(category: category, item: item),
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
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    return _parsePrice(value?.toString() ?? '');
  }

  int _parseSessionCount(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _IslemCategory {
  const _IslemCategory({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

class _IslemItem {
  const _IslemItem({
    required this.id,
    required this.name,
    required this.price,
    required this.sessionCount,
  });

  final String id;
  final String name;
  final double price;
  final int sessionCount;
}

class _CategoryFormResult {
  const _CategoryFormResult({
    required this.name,
  });

  final String name;
}

class _OperationFormResult {
  const _OperationFormResult({
    required this.name,
    required this.price,
    required this.sessionCount,
  });

  final String name;
  final double price;
  final int sessionCount;
}
