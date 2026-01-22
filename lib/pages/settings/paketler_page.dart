import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import '../../controllers/institution_controller.dart';
import '../../controllers/user_controller.dart';
import '../../utils/permission_utils.dart';

class PaketlerPage extends StatefulWidget {
  const PaketlerPage({super.key});

  @override
  State<PaketlerPage> createState() => _PaketlerPageState();
}

class _PaketlerPageState extends State<PaketlerPage> {
  final UserController _user = Get.find<UserController>();
  final InstitutionController _institution = Get.find<InstitutionController>();

  final EdgeInsets _pagePadding = const EdgeInsets.symmetric(horizontal: 16);

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  List<_OperationOption> _operationOptions = [];

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
      _loadOperations();
    });
  }

  String _currentInstitutionId() {
    return (_institution.data['kurumkodu'] ?? '').toString();
  }

  CollectionReference<Map<String, dynamic>> _packagesRef() {
    return FirebaseFirestore.instance
        .collection('kurumlar')
        .doc(_currentInstitutionId())
        .collection('paketler');
  }

  CollectionReference<Map<String, dynamic>> _categoriesRef() {
    return FirebaseFirestore.instance
        .collection('kurumlar')
        .doc(_currentInstitutionId())
        .collection('islemKategorileri');
  }

  Future<void> _loadOperations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final institutionId = _currentInstitutionId();
    if (institutionId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Kurum bilgisine ulaşılamadı.';
      });
      return;
    }

    try {
      final options = await _fetchOperationOptions();
      if (!mounted) {
        return;
      }
      setState(() {
        _operationOptions = options;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'İşlem listesi yüklenemedi: $error';
      });
    }
  }

  Future<List<_OperationOption>> _fetchOperationOptions() async {
    final categoriesSnapshot = await _categoriesRef().get();
    final options = <_OperationOption>[];

    for (final categoryDoc in categoriesSnapshot.docs) {
      final categoryData = categoryDoc.data();
      final categoryName = (categoryData['adi'] ?? '').toString().trim();
      final operationsSnapshot =
          await _categoriesRef().doc(categoryDoc.id).collection('islemler').get();

      for (final operationDoc in operationsSnapshot.docs) {
        final data = operationDoc.data();
        final name = (data['adi'] ?? '').toString().trim();
        if (name.isEmpty) {
          continue;
        }
        options.add(
          _OperationOption(
            id: operationDoc.id,
            name: name,
            categoryId: categoryDoc.id,
            categoryName: categoryName,
          ),
        );
      }
    }

    options.sort((a, b) => a.label.compareTo(b.label));
    return options;
  }

  Future<void> _openPackageDialog({_PackageItem? item}) async {
    if (_isSaving) {
      return;
    }
    final result = await _showPackageDialog(item: item);
    if (result == null) {
      return;
    }
    if (item == null) {
      await _createPackage(result);
    } else {
      await _updatePackage(item, result);
    }
  }

  Future<_PackageFormResult?> _showPackageDialog({_PackageItem? item}) async {
    final now = DateTime.now();
    final nameController = TextEditingController(text: item?.name ?? '');
    final descriptionController = TextEditingController(text: item?.description ?? '');
    final initialStart = item?.startDate ?? DateTime(now.year, now.month, now.day);
    final initialEnd =
        item?.endDate ?? DateTime(initialStart.year + 1, initialStart.month, initialStart.day);
    final startController = TextEditingController(
      text: _formatDate(initialStart),
    );
    final endController = TextEditingController(
      text: _formatDate(initialEnd),
    );
    final priceController = TextEditingController(
      text: item == null ? '' : _formatPrice(item.price),
    );

    DateTime startDate = initialStart;
    DateTime endDate = initialEnd;
    final selectedOperations = item == null
        ? <_PackageOperation>[]
        : item.operations.map((operation) => operation.copy()).toList();

    return showDialog<_PackageFormResult>(
      context: context,
      barrierDismissible: !_isSaving,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> pickDate({
              required bool isStart,
            }) async {
              final current = isStart ? startDate : endDate;
              final picked = await showDatePicker(
                context: context,
                initialDate: current,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                helpText: isStart ? 'Başlama tarihi seçin' : 'Bitiş tarihi seçin',
              );
              if (picked == null) {
                return;
              }
              setState(() {
                if (isStart) {
                  startDate = DateTime(picked.year, picked.month, picked.day);
                  startController.text = _formatDate(startDate);
                  if (item == null) {
                    endDate = DateTime(startDate.year + 1, startDate.month, startDate.day);
                  } else if (endDate.isBefore(startDate)) {
                    endDate = startDate;
                  }
                  endController.text = _formatDate(endDate);
                } else {
                  endDate = DateTime(picked.year, picked.month, picked.day);
                  endController.text = _formatDate(endDate);
                }
              });
            }

            Future<void> addOrEditOperation({_PackageOperation? existing}) async {
              if (_operationOptions.isEmpty) {
                _showSnack('İşlem listesi bulunamadı.');
                return;
              }
              final result = await _showOperationPicker(
                options: _operationOptions,
                existing: existing,
                usedIds: selectedOperations
                    .where((operation) => operation != existing)
                    .map((operation) => operation.operationId)
                    .toSet(),
              );
              if (result == null) {
                return;
              }
              setState(() {
                if (existing == null) {
                  selectedOperations.add(result);
                } else {
                  final index =
                      selectedOperations.indexWhere((op) => op.operationId == existing.operationId);
                  if (index != -1) {
                    selectedOperations[index] = result;
                  }
                }
              });
            }

            return AlertDialog(
              title: Text(item == null ? 'Paket Ekle' : 'Paket Güncelle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Paket adı',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama (opsiyonel)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: startController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Başlama tarihi',
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      onTap: () => pickDate(isStart: true),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: endController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Bitiş tarihi',
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      onTap: () => pickDate(isStart: false),
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
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'İşlemler',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _isSaving ? null : () => addOrEditOperation(),
                          icon: const Icon(Icons.add),
                          label: const Text('Ekle'),
                        ),
                      ],
                    ),
                    if (selectedOperations.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4, bottom: 12),
                        child: Text('Henüz işlem eklenmedi.'),
                      )
                    else
                      Column(
                        children: selectedOperations.map((operation) {
                          final sessionLabel = operation.unlimited
                              ? 'Sınırsız'
                              : '${operation.sessionCount} seans';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(operation.label),
                            subtitle: Text(sessionLabel),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: 'İşlemi düzenle',
                                  onPressed:
                                      _isSaving ? null : () => addOrEditOperation(existing: operation),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'İşlemi sil',
                                  onPressed: _isSaving
                                      ? null
                                      : () {
                                          setState(() {
                                            selectedOperations.remove(operation);
                                          });
                                        },
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Vazgeç'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      _showSnack('Paket adı boş bırakılamaz.');
                      return;
                    }
                    final rawPrice = priceController.text.trim();
                    final price = _parsePrice(rawPrice);
                    if (price <= 0) {
                      _showSnack('Fiyat 0\'dan büyük olmalı.');
                      return;
                    }
                    if (endDate.isBefore(startDate)) {
                      _showSnack('Bitiş tarihi başlama tarihinden önce olamaz.');
                      return;
                    }
                    if (selectedOperations.isEmpty) {
                      _showSnack('En az bir işlem ekleyin.');
                      return;
                    }
                    Navigator.of(context).pop(
                      _PackageFormResult(
                        name: name,
                        description: descriptionController.text.trim(),
                        startDate: startDate,
                        endDate: endDate,
                        price: price,
                        operations: List.from(selectedOperations),
                      ),
                    );
                  },
                  child: Text(item == null ? 'Ekle' : 'Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<_PackageOperation?> _showOperationPicker({
    required List<_OperationOption> options,
    required Set<String> usedIds,
    _PackageOperation? existing,
  }) async {
    _OperationOption? selectedOption;
    if (existing != null) {
      selectedOption = options.firstWhere(
        (option) => option.id == existing.operationId,
        orElse: () => options.first,
      );
    }
    final sessionController = TextEditingController(
      text: existing == null || existing.unlimited ? '' : existing.sessionCount.toString(),
    );
    bool unlimited = existing?.unlimited ?? false;

    return showDialog<_PackageOperation>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(existing == null ? 'İşlem Ekle' : 'İşlem Güncelle'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<_OperationOption>(
                    value: selectedOption,
                    items: options
                        .map(
                          (option) => DropdownMenuItem<_OperationOption>(
                            value: option,
                            child: Text(option.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => selectedOption = value),
                    decoration: const InputDecoration(
                      labelText: 'İşlem',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: unlimited,
                    onChanged: (value) {
                      setState(() {
                        unlimited = value;
                        if (unlimited) {
                          sessionController.text = '';
                        }
                      });
                    },
                    title: const Text('Sınırsız'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: sessionController,
                    keyboardType: TextInputType.number,
                    enabled: !unlimited,
                    decoration: const InputDecoration(
                      labelText: 'Seans sayısı',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Vazgeç'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final option = selectedOption;
                    if (option == null) {
                      _showSnack('Lütfen bir işlem seçin.');
                      return;
                    }
                    if (usedIds.contains(option.id)) {
                      _showSnack('Bu işlem zaten eklendi.');
                      return;
                    }
                    int sessionCount = 0;
                    if (!unlimited) {
                      sessionCount = int.tryParse(sessionController.text.trim()) ?? 0;
                      if (sessionCount <= 0) {
                        _showSnack('Seans sayısı 1 veya daha büyük olmalı.');
                        return;
                      }
                    }
                    Navigator.of(context).pop(
                      _PackageOperation(
                        operationId: option.id,
                        operationName: option.name,
                        categoryId: option.categoryId,
                        categoryName: option.categoryName,
                        sessionCount: sessionCount,
                        unlimited: unlimited,
                      ),
                    );
                  },
                  child: Text(existing == null ? 'Ekle' : 'Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createPackage(_PackageFormResult result) async {
    final institutionId = _currentInstitutionId();
    if (institutionId.isEmpty) {
      _showSnack('Kurum bilgisine ulaşılamadı.');
      return;
    }
    final packageCode = _generatePackageCode();
    setState(() {
      _isSaving = true;
    });
    try {
      await _packagesRef().add({
        'paketKodu': packageCode,
        'baslamaTarihi': Timestamp.fromDate(result.startDate),
        'bitisTarihi': Timestamp.fromDate(result.endDate),
        'adi': result.name,
        if (result.description.isNotEmpty) 'aciklama': result.description,
        'fiyat': result.price,
        'islemler': result.operations.map((operation) => operation.toMap()).toList(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _showSnack('Paket eklendi.');
    } catch (error) {
      _showSnack('Paket eklenemedi: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _updatePackage(_PackageItem item, _PackageFormResult result) async {
    setState(() {
      _isSaving = true;
    });
    try {
      final packageCode = item.code.isEmpty ? _generatePackageCode() : item.code;
      await _packagesRef().doc(item.id).set(
        {
          'paketKodu': packageCode,
          'baslamaTarihi': Timestamp.fromDate(result.startDate),
          'bitisTarihi': Timestamp.fromDate(result.endDate),
          'adi': result.name,
          'aciklama': result.description,
          'fiyat': result.price,
          'islemler': result.operations.map((operation) => operation.toMap()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      _showSnack('Paket güncellendi.');
    } catch (error) {
      _showSnack('Paket güncellenemedi: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deletePackage(_PackageItem item) async {
    if (_isSaving) {
      return;
    }
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Paket Silinsin mi?'),
          content: const Text('Paketi silmek istediğinize emin misiniz?'),
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
      await _packagesRef().doc(item.id).delete();
      _showSnack('Paket silindi.');
    } catch (error) {
      _showSnack('Paket silinemedi: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd.MM.yyyy').format(date);
  }

  String _formatPrice(double price) {
    if (price % 1 == 0) {
      return price.toStringAsFixed(0);
    }
    return price.toStringAsFixed(2);
  }

  double _parsePrice(String value) {
    final normalized = value.replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  String _generatePackageCode() {
    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMddHHmmss').format(now);
    final seed = now.microsecondsSinceEpoch.toString().padLeft(16, '0');
    final suffix = seed.substring(seed.length - 6);
    return 'PKG-$stamp-$suffix';
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
        title: const Text('Paketler'),
        actions: const [HomeIconButton()],
      ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _isSaving ? null : () => _openPackageDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Paket Ekle'),
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
      stream: _packagesRef().orderBy('baslamaTarihi', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: _pagePadding,
              child: const Text(
                'Paketler yüklenemedi.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = snapshot.data!.docs.map((doc) {
          final data = doc.data();
          final startDate = _parseTimestamp(data['baslamaTarihi']) ?? DateTime.now();
          final endDate = _parseTimestamp(data['bitisTarihi']) ?? startDate;
          final price = _parsePrice((data['fiyat'] ?? '').toString());
          final code = (data['paketKodu'] ?? '').toString();
          final name = (data['adi'] ?? '').toString();
          final description = (data['aciklama'] ?? '').toString();
          final operations = _parsePackageOperations(data['islemler']);
          return _PackageItem(
            id: doc.id,
            startDate: startDate,
            endDate: endDate,
            price: price,
            code: code,
            name: name,
            description: description,
            operations: operations,
          );
        }).toList();

        if (items.isEmpty) {
          return ListView(
            padding: _pagePadding.copyWith(top: 48, bottom: 24),
            children: const [
              Icon(Icons.inventory_2_outlined, size: 48),
              SizedBox(height: 16),
              Text(
                'Henüz paket eklenmedi.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Yeni paket eklemek için sağ alttaki butonu kullanabilirsiniz.',
                textAlign: TextAlign.center,
              ),
            ],
          );
        }

        return ListView.separated(
          padding: _pagePadding.copyWith(top: 16, bottom: 80),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final item = items[index];
            final dateLabel =
                '${_formatDate(item.startDate)} - ${_formatDate(item.endDate)}';
            final operationsSummary = item.operations.map((operation) {
              final sessionLabel = operation.unlimited
                  ? 'Sınırsız'
                  : '${operation.sessionCount} seans';
              final name = operation.operationName.trim().isEmpty
                  ? operation.label
                  : operation.operationName;
              return '$name ($sessionLabel)';
            }).join(', ');
            return Card(
              child: ExpansionTile(
                title: Text(item.name.isEmpty ? 'Paket' : item.name),
                subtitle: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        dateLabel,
                        if (item.description.isNotEmpty) item.description,
                        'Fiyat: ${_formatPrice(item.price)} TL',
                      ].join(' • '),
                    ),
                    if (operationsSummary.isNotEmpty)
                      Text(
                        operationsSummary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Paket düzenle',
                      onPressed: _isSaving ? null : () => _openPackageDialog(item: item),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Paket sil',
                      onPressed: _isSaving ? null : () => _deletePackage(item),
                    ),
                  ],
                ),
                children: item.operations.map((operation) {
                  final sessionLabel = operation.unlimited
                      ? 'Sınırsız'
                      : '${operation.sessionCount} seans';
                  return ListTile(
                    title: Text(operation.label),
                    subtitle: Text(sessionLabel),
                  );
                }).toList(),
              ),
            );
          },
        );
      },
    );
  }

  List<_PackageOperation> _parsePackageOperations(dynamic raw) {
    if (raw is! List) {
      return [];
    }
    return raw
        .map((entry) {
          final map = entry is Map ? entry : <String, dynamic>{};
          final sessionCount = int.tryParse((map['seansSayisi'] ?? '').toString()) ?? 0;
          final unlimited = (map['sinirsiz'] ?? false) == true;
          return _PackageOperation(
            operationId: (map['operationId'] ?? '').toString(),
            operationName: (map['operationName'] ?? '').toString(),
            categoryId: (map['categoryId'] ?? '').toString(),
            categoryName: (map['categoryName'] ?? '').toString(),
            sessionCount: sessionCount,
            unlimited: unlimited,
          );
        })
        .where((operation) => operation.operationId.isNotEmpty)
        .toList();
  }
}

class _OperationOption {
  const _OperationOption({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.categoryName,
  });

  final String id;
  final String name;
  final String categoryId;
  final String categoryName;

  String get label {
    final category = categoryName.trim();
    if (category.isEmpty) {
      return name;
    }
    return '$category • $name';
  }
}

class _PackageItem {
  const _PackageItem({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.price,
    required this.code,
    required this.name,
    required this.description,
    required this.operations,
  });

  final String id;
  final DateTime startDate;
  final DateTime endDate;
  final double price;
  final String code;
  final String name;
  final String description;
  final List<_PackageOperation> operations;
}

class _PackageOperation {
  const _PackageOperation({
    required this.operationId,
    required this.operationName,
    required this.categoryId,
    required this.categoryName,
    required this.sessionCount,
    required this.unlimited,
  });

  final String operationId;
  final String operationName;
  final String categoryId;
  final String categoryName;
  final int sessionCount;
  final bool unlimited;

  String get label {
    final category = categoryName.trim();
    if (category.isEmpty) {
      return operationName;
    }
    return '$category • $operationName';
  }

  Map<String, dynamic> toMap() {
    return {
      'operationId': operationId,
      'operationName': operationName,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'seansSayisi': sessionCount,
      'sinirsiz': unlimited,
    };
  }

  _PackageOperation copy() {
    return _PackageOperation(
      operationId: operationId,
      operationName: operationName,
      categoryId: categoryId,
      categoryName: categoryName,
      sessionCount: sessionCount,
      unlimited: unlimited,
    );
  }
}

class _PackageFormResult {
  const _PackageFormResult({
    required this.name,
    required this.description,
    required this.startDate,
    required this.endDate,
    required this.price,
    required this.operations,
  });

  final String name;
  final String description;
  final DateTime startDate;
  final DateTime endDate;
  final double price;
  final List<_PackageOperation> operations;
}
