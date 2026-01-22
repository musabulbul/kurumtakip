import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/institution_controller.dart';
import '../../controllers/user_controller.dart';

class GiderlerRaporuPage extends StatefulWidget {
  const GiderlerRaporuPage({super.key});

  @override
  State<GiderlerRaporuPage> createState() => _GiderlerRaporuPageState();
}

class _GiderlerRaporuPageState extends State<GiderlerRaporuPage> {
  static const String _allFilter = 'Tümü';

  static const List<String> _defaultExpenseTypes = [
    'Kira',
    'Fatura',
    'Tamir-Bakım',
    'Personel',
    'Makine -Techizat',
    'Tüketim Malzemesi',
    'Gıda',
    'Satış Ürünü',
    'Ulaşım',
    'Diğer',
  ];

  static const Map<String, String> _paymentTypeLabels = {
    'cash': 'Nakit',
    'card': 'Kredi Kartı',
    'transfer': 'Havale/EFT',
  };

  final InstitutionController _institution = Get.find<InstitutionController>();
  final UserController _user = Get.find<UserController>();

  String _selectedExpenseType = _allFilter;
  String _selectedPaymentType = _allFilter;
  String _selectedPaidBy = _allFilter;
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _startDate = today;
    _endDate = today;
  }

  @override
  Widget build(BuildContext context) {
    final institutionId = (_institution.data['kurumkodu'] ?? '').toString();
    if (institutionId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Kurum bilgisi bulunamadı.')),
      );
    }

    final typesStream = FirebaseFirestore.instance
        .collection('kurumlar')
        .doc(institutionId)
        .collection('giderTurleri')
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Giderler'),
        actions: [
          IconButton(
            tooltip: 'Gider Türü Ekle',
            onPressed: () => _openExpenseTypeDialog(institutionId),
            icon: const Icon(Icons.playlist_add_outlined),
          ),
        ],
      ),
      floatingActionButton: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: typesStream,
        builder: (context, snapshot) {
          final customTypes = snapshot.hasData
              ? snapshot.data!.docs
                  .map((doc) => (doc.data()['name'] ?? '').toString().trim())
                  .where((name) => name.isNotEmpty)
                  .toList()
              : <String>[];
          final expenseTypes = _mergeExpenseTypes(customTypes);
          return FloatingActionButton.extended(
            onPressed: () => _openExpenseDialog(institutionId, expenseTypes),
            icon: const Icon(Icons.add_outlined),
            label: const Text('Gider Ekle'),
          );
        },
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: typesStream,
        builder: (context, typeSnapshot) {
          if (typeSnapshot.hasError) {
            return const Center(child: Text('Gider türleri yüklenemedi.'));
          }
          if (!typeSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final customTypes = typeSnapshot.data!.docs
              .map((doc) => (doc.data()['name'] ?? '').toString().trim())
              .where((name) => name.isNotEmpty)
              .toList();
          final expenseTypes = _mergeExpenseTypes(customTypes);

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('kurumlar')
                .doc(institutionId)
                .collection('giderler')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Giderler yüklenemedi.'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final entries = snapshot.data!.docs
                  .map((doc) => _ExpenseEntry.fromSnapshot(doc))
                  .where((entry) => entry.institutionId == institutionId)
                  .toList();

              final typeOptions = _buildFilterOptions(expenseTypes);
              final paymentOptions = _buildFilterOptions(
                _paymentTypeLabels.values.toList(),
              );
              final paidByOptions = _buildFilterOptions(
                entries.map((entry) => entry.paidByName).toList(),
              );

              final selectedType =
                  typeOptions.contains(_selectedExpenseType) ? _selectedExpenseType : _allFilter;
              final selectedPayment = paymentOptions.contains(_selectedPaymentType)
                  ? _selectedPaymentType
                  : _allFilter;
              final selectedPaidBy =
                  paidByOptions.contains(_selectedPaidBy) ? _selectedPaidBy : _allFilter;

              final filtered = entries.where((entry) {
                if (selectedType != _allFilter && entry.typeLabel != selectedType) {
                  return false;
                }
                if (selectedPayment != _allFilter &&
                    entry.paymentTypeLabel != selectedPayment) {
                  return false;
                }
                if (selectedPaidBy != _allFilter && entry.paidByName != selectedPaidBy) {
                  return false;
                }
                final createdAt = entry.createdAt;
                if (createdAt == null) {
                  return false;
                }
                final day = DateUtils.dateOnly(createdAt);
                if (day.isBefore(_startDate) || day.isAfter(_endDate)) {
                  return false;
                }
                return true;
              }).toList();

              final totalAmount =
                  filtered.fold<double>(0, (sum, item) => sum + item.amount);

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildFilterSection(
                    typeOptions: typeOptions,
                    paymentOptions: paymentOptions,
                    paidByOptions: paidByOptions,
                    selectedType: selectedType,
                    selectedPayment: selectedPayment,
                    selectedPaidBy: selectedPaidBy,
                  ),
                  const SizedBox(height: 12),
                  _buildSummaryCard(filtered.length, totalAmount),
                  const SizedBox(height: 12),
                  if (filtered.isEmpty)
                    const Center(child: Text('Filtrelere uygun gider yok.'))
                  else
                    ...filtered.map(_buildExpenseCard),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<String> _mergeExpenseTypes(List<String> customTypes) {
    final merged = <String>{};
    for (final type in _defaultExpenseTypes) {
      merged.add(type);
    }
    for (final type in customTypes) {
      merged.add(type);
    }
    return merged.toList()..sort();
  }

  List<String> _buildFilterOptions(List<String> values) {
    final options = values.where((value) => value.isNotEmpty).toSet().toList()
      ..sort();
    return [_allFilter, ...options];
  }

  Widget _buildFilterSection({
    required List<String> typeOptions,
    required List<String> paymentOptions,
    required List<String> paidByOptions,
    required String selectedType,
    required String selectedPayment,
    required String selectedPaidBy,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDateQuickActions(),
        const SizedBox(height: 12),
        _buildDateRangeInputs(),
        const SizedBox(height: 12),
        _buildDropdown(
          label: 'Gider Türü',
          value: selectedType,
          options: typeOptions,
          onChanged: (value) {
            setState(() {
              _selectedExpenseType = value;
            });
          },
        ),
        const SizedBox(height: 12),
        _buildDropdown(
          label: 'Ödeme Çeşidi',
          value: selectedPayment,
          options: paymentOptions,
          onChanged: (value) {
            setState(() {
              _selectedPaymentType = value;
            });
          },
        ),
        const SizedBox(height: 12),
        _buildDropdown(
          label: 'Ödemeyi Yapan',
          value: selectedPaidBy,
          options: paidByOptions,
          onChanged: (value) {
            setState(() {
              _selectedPaidBy = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      items: options
          .map(
            (option) => DropdownMenuItem(
              value: option,
              child: Text(option),
            ),
          )
          .toList(),
      onChanged: (selected) {
        if (selected == null) {
          return;
        }
        onChanged(selected);
      },
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      isExpanded: true,
    );
  }

  Widget _buildDateQuickActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: _setYesterdayRange,
          child: const Text('Dün'),
        ),
        OutlinedButton(
          onPressed: _setTodayRange,
          child: const Text('Bugün'),
        ),
        OutlinedButton(
          onPressed: _setThisMonthRange,
          child: const Text('Bu Ay'),
        ),
        OutlinedButton(
          onPressed: _setLastMonthRange,
          child: const Text('Geçen Ay'),
        ),
        OutlinedButton(
          onPressed: _setThisYearRange,
          child: const Text('Bu Yıl'),
        ),
        OutlinedButton(
          onPressed: _setLastYearRange,
          child: const Text('Geçen Yıl'),
        ),
      ],
    );
  }

  Widget _buildDateRangeInputs() {
    final startLabel = DateFormat('dd.MM.yyyy').format(_startDate);
    final endLabel = DateFormat('dd.MM.yyyy').format(_endDate);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickDate(isStart: true),
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(startLabel),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickDate(isStart: false),
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(endLabel),
          ),
        ),
      ],
    );
  }

  void _setTodayRange() {
    final today = DateUtils.dateOnly(DateTime.now());
    setState(() {
      _startDate = today;
      _endDate = today;
    });
  }

  void _setYesterdayRange() {
    final yesterday = DateUtils.dateOnly(DateTime.now().subtract(const Duration(days: 1)));
    setState(() {
      _startDate = yesterday;
      _endDate = yesterday;
    });
  }

  void _setThisMonthRange() {
    final now = DateTime.now();
    final start = DateUtils.dateOnly(DateTime(now.year, now.month, 1));
    final end = DateUtils.dateOnly(DateTime(now.year, now.month + 1, 0));
    setState(() {
      _startDate = start;
      _endDate = end;
    });
  }

  void _setLastMonthRange() {
    final now = DateTime.now();
    final start = DateUtils.dateOnly(DateTime(now.year, now.month - 1, 1));
    final end = DateUtils.dateOnly(DateTime(now.year, now.month, 0));
    setState(() {
      _startDate = start;
      _endDate = end;
    });
  }

  void _setThisYearRange() {
    final now = DateTime.now();
    final start = DateUtils.dateOnly(DateTime(now.year, 1, 1));
    final end = DateUtils.dateOnly(DateTime(now.year, 12, 31));
    setState(() {
      _startDate = start;
      _endDate = end;
    });
  }

  void _setLastYearRange() {
    final now = DateTime.now();
    final start = DateUtils.dateOnly(DateTime(now.year - 1, 1, 1));
    final end = DateUtils.dateOnly(DateTime(now.year - 1, 12, 31));
    setState(() {
      _startDate = start;
      _endDate = end;
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      if (isStart) {
        _startDate = DateUtils.dateOnly(picked);
        if (_startDate.isAfter(_endDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = DateUtils.dateOnly(picked);
        if (_endDate.isBefore(_startDate)) {
          _startDate = _endDate;
        }
      }
    });
  }

  Widget _buildSummaryCard(int count, double totalAmount) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Adet: $count',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              'Toplam: ${_formatPrice(totalAmount)} TL',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseCard(_ExpenseEntry entry) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.title.isNotEmpty ? entry.title : 'Gider',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${_formatPrice(entry.amount)} TL',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tür: ${entry.typeLabel}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            'Ödeme Çeşidi: ${entry.paymentTypeLabel}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            'Ödemeyi Yapan: ${entry.paidByName.isNotEmpty ? entry.paidByName : '-'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (entry.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Açıklama: ${entry.note}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (entry.createdAt != null) ...[
            const SizedBox(height: 4),
            Text(
              DateFormat('dd.MM.yyyy HH:mm').format(entry.createdAt!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openExpenseTypeDialog(String institutionId) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Gider Türü Ekle'),
          content: TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Gider Türü',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  return;
                }
                Navigator.of(dialogContext).pop(name);
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (result == null || result.trim().isEmpty) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(institutionId)
          .collection('giderTurleri')
          .add({
        'name': result.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gider türü eklendi.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gider türü eklenemedi: $error')),
        );
      }
    }
  }

  Future<void> _openExpenseDialog(
    String institutionId,
    List<String> expenseTypes,
  ) async {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final availableTypes = expenseTypes.isNotEmpty ? expenseTypes : _defaultExpenseTypes;
    var selectedType =
        availableTypes.contains('Diğer') ? 'Diğer' : availableTypes.first;
    var selectedPaymentType = 'cash';
    final paidByName = _resolveUserDisplayName(_user.data);
    final paidByController = TextEditingController(text: paidByName);

    final result = await showDialog<_ExpenseFormResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text('Gider Ekle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Gider',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Gider Türü',
                        border: OutlineInputBorder(),
                      ),
                      items: availableTypes
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          selectedType = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedPaymentType,
                      decoration: const InputDecoration(
                        labelText: 'Ödeme Çeşidi',
                        border: OutlineInputBorder(),
                      ),
                      items: _paymentTypeLabels.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          selectedPaymentType = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Tutar',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: paidByController,
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: 'Ödemeyi Yapan',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () {
                    final amount = _parseAmount(amountController.text);
                    if (amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tutar geçerli olmalı.')),
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _ExpenseFormResult(
                        title: titleController.text.trim(),
                        type: selectedType,
                        paymentType: selectedPaymentType,
                        amount: amount,
                        note: noteController.text.trim(),
                        paidByName: paidByName,
                      ),
                    );
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    amountController.dispose();
    noteController.dispose();
    paidByController.dispose();

    if (result == null) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(institutionId)
          .collection('giderler')
          .add({
        'title': result.title,
        'type': result.type,
        'paymentType': result.paymentType,
        'amount': result.amount,
        'note': result.note,
        'paidByName': result.paidByName,
        'createdAt': FieldValue.serverTimestamp(),
        'createdById': (_user.data['email'] ?? _user.data['uid'] ?? '').toString(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gider kaydedildi.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gider kaydedilemedi: $error')),
        );
      }
    }
  }

  String _resolveUserDisplayName(Map<dynamic, dynamic> userData) {
    final shortName = (userData['kisaad'] ?? '').toString().trim();
    if (shortName.isNotEmpty) {
      return shortName;
    }
    final first = (userData['adi'] ?? '').toString().trim();
    final last = (userData['soyadi'] ?? '').toString().trim();
    final fullName = [first, last].where((part) => part.isNotEmpty).join(' ');
    if (fullName.isNotEmpty) {
      return fullName;
    }
    return (userData['email'] ?? '').toString().trim();
  }

  double _parseAmount(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return 0;
    }
    return double.tryParse(normalized) ?? 0;
  }

  String _formatPrice(double price) {
    if (price % 1 == 0) {
      return price.toStringAsFixed(0);
    }
    return price.toStringAsFixed(2);
  }
}

class _ExpenseFormResult {
  const _ExpenseFormResult({
    required this.title,
    required this.type,
    required this.paymentType,
    required this.amount,
    required this.note,
    required this.paidByName,
  });

  final String title;
  final String type;
  final String paymentType;
  final double amount;
  final String note;
  final String paidByName;
}

class _ExpenseEntry {
  const _ExpenseEntry({
    required this.id,
    required this.institutionId,
    required this.title,
    required this.typeLabel,
    required this.paymentTypeLabel,
    required this.paidByName,
    required this.amount,
    required this.createdAt,
    required this.note,
  });

  final String id;
  final String institutionId;
  final String title;
  final String typeLabel;
  final String paymentTypeLabel;
  final String paidByName;
  final double amount;
  final DateTime? createdAt;
  final String note;

  factory _ExpenseEntry.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final institutionId = snapshot.reference.parent.parent?.id ?? '';
    final paymentType = (data['paymentType'] ?? '').toString().trim();
    return _ExpenseEntry(
      id: snapshot.id,
      institutionId: institutionId,
      title: (data['title'] ?? '').toString().trim(),
      typeLabel: (data['type'] ?? '').toString().trim(),
      paymentTypeLabel: _resolvePaymentTypeLabel(paymentType),
      paidByName: (data['paidByName'] ?? '').toString().trim(),
      amount: _readAmount(data['amount']),
      createdAt: _readTimestamp(data['createdAt']),
      note: (data['note'] ?? '').toString().trim(),
    );
  }

  static String _resolvePaymentTypeLabel(String raw) {
    switch (raw) {
      case 'card':
        return 'Kredi Kartı';
      case 'transfer':
        return 'Havale/EFT';
      case 'cash':
      default:
        return 'Nakit';
    }
  }

  static double _readAmount(dynamic value) {
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) {
      return 0;
    }
    return double.tryParse(raw.replaceAll(',', '.')) ?? 0;
  }

  static DateTime? _readTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}
