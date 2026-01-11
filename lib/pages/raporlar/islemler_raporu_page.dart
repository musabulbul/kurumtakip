import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/institution_controller.dart';

class IslemlerRaporuPage extends StatefulWidget {
  const IslemlerRaporuPage({super.key});

  @override
  State<IslemlerRaporuPage> createState() => _IslemlerRaporuPageState();
}

class _IslemlerRaporuPageState extends State<IslemlerRaporuPage> {
  static const String _allFilter = 'Tümü';

  final InstitutionController _institution = Get.find<InstitutionController>();

  String _selectedLocation = _allFilter;
  String _selectedCategory = _allFilter;
  String _selectedOperation = _allFilter;
  String _selectedType = _allFilter;
  String _selectedPerformer = _allFilter;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('İşlem Raporu'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collectionGroup('islemler').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('İşlemler yüklenemedi.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data!.docs
              .map((doc) => _OperationReportEntry.fromSnapshot(doc))
              .where((entry) => entry.institutionId == institutionId)
              .toList();

          final locationOptions = _buildFilterOptions(
            entries.map((entry) => entry.locationName).toList(),
          );
          final categoryOptions = _buildFilterOptions(
            entries.map((entry) => entry.categoryName).toList(),
          );
          final operationOptions = _buildFilterOptions(
            entries.map((entry) => entry.operationName).toList(),
          );
          final typeOptions = _buildFilterOptions(
            entries.map((entry) => entry.typeLabel).toList(),
          );
          final performerOptions = _buildFilterOptions(
            entries.map((entry) => entry.performedByName).toList(),
          );

          final selectedLocation =
              locationOptions.contains(_selectedLocation) ? _selectedLocation : _allFilter;
          final selectedCategory =
              categoryOptions.contains(_selectedCategory) ? _selectedCategory : _allFilter;
          final selectedOperation =
              operationOptions.contains(_selectedOperation) ? _selectedOperation : _allFilter;
          final selectedType =
              typeOptions.contains(_selectedType) ? _selectedType : _allFilter;
          final selectedPerformer =
              performerOptions.contains(_selectedPerformer) ? _selectedPerformer : _allFilter;

          final filtered = entries.where((entry) {
            if (selectedLocation != _allFilter &&
                entry.locationName != selectedLocation) {
              return false;
            }
            if (selectedCategory != _allFilter &&
                entry.categoryName != selectedCategory) {
              return false;
            }
            if (selectedOperation != _allFilter &&
                entry.operationName != selectedOperation) {
              return false;
            }
            if (selectedType != _allFilter && entry.typeLabel != selectedType) {
              return false;
            }
            if (selectedPerformer != _allFilter &&
                entry.performedByName != selectedPerformer) {
              return false;
            }
            final completedAt = entry.completedAt;
            if (completedAt == null) {
              return false;
            }
            final day = DateUtils.dateOnly(completedAt);
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
                locationOptions: locationOptions,
                categoryOptions: categoryOptions,
                operationOptions: operationOptions,
                typeOptions: typeOptions,
                performerOptions: performerOptions,
                selectedLocation: selectedLocation,
                selectedCategory: selectedCategory,
                selectedOperation: selectedOperation,
                selectedType: selectedType,
                selectedPerformer: selectedPerformer,
              ),
              const SizedBox(height: 12),
              _buildSummaryCard(filtered.length, totalAmount),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                const Center(child: Text('Filtrelere uygun işlem yok.'))
              else
                ...filtered.map(_buildOperationCard),
            ],
          );
        },
      ),
    );
  }

  List<String> _buildFilterOptions(List<String> values) {
    final options = values.where((value) => value.isNotEmpty).toSet().toList()
      ..sort();
    return [_allFilter, ...options];
  }

  Widget _buildFilterSection({
    required List<String> locationOptions,
    required List<String> categoryOptions,
    required List<String> operationOptions,
    required List<String> typeOptions,
    required List<String> performerOptions,
    required String selectedLocation,
    required String selectedCategory,
    required String selectedOperation,
    required String selectedType,
    required String selectedPerformer,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDateQuickActions(),
        const SizedBox(height: 12),
        _buildDateRangeInputs(),
        const SizedBox(height: 12),
        _buildDropdown(
          label: 'Mekan',
          value: selectedLocation,
          options: locationOptions,
          onChanged: (value) {
            setState(() {
              _selectedLocation = value;
            });
          },
        ),
        const SizedBox(height: 12),
        _buildDropdown(
          label: 'Kategori',
          value: selectedCategory,
          options: categoryOptions,
          onChanged: (value) {
            setState(() {
              _selectedCategory = value;
            });
          },
        ),
        const SizedBox(height: 12),
        _buildDropdown(
          label: 'İşlem',
          value: selectedOperation,
          options: operationOptions,
          onChanged: (value) {
            setState(() {
              _selectedOperation = value;
            });
          },
        ),
        const SizedBox(height: 12),
        _buildDropdown(
          label: 'İşlem Türü',
          value: selectedType,
          options: typeOptions,
          onChanged: (value) {
            setState(() {
              _selectedType = value;
            });
          },
        ),
        const SizedBox(height: 12),
        _buildDropdown(
          label: 'İşlemi Yapan',
          value: selectedPerformer,
          options: performerOptions,
          onChanged: (value) {
            setState(() {
              _selectedPerformer = value;
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

  Widget _buildOperationCard(_OperationReportEntry entry) {
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
                  entry.operationName.isNotEmpty ? entry.operationName : 'İşlem',
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
            '${entry.typeLabel} • ${entry.categoryName.isNotEmpty ? entry.categoryName : '-'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Mekan: ${entry.locationName.isNotEmpty ? entry.locationName : '-'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'İşlemi yapan: ${entry.performedByName.isNotEmpty ? entry.performedByName : '-'}',
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
          if (entry.completedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              DateFormat('dd.MM.yyyy HH:mm').format(entry.completedAt!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatPrice(double price) {
    if (price % 1 == 0) {
      return price.toStringAsFixed(0);
    }
    return price.toStringAsFixed(2);
  }
}

class _OperationReportEntry {
  const _OperationReportEntry({
    required this.id,
    required this.institutionId,
    required this.operationName,
    required this.categoryName,
    required this.typeLabel,
    required this.locationName,
    required this.performedByName,
    required this.amount,
    required this.completedAt,
    required this.note,
  });

  final String id;
  final String institutionId;
  final String operationName;
  final String categoryName;
  final String typeLabel;
  final String locationName;
  final String performedByName;
  final double amount;
  final DateTime? completedAt;
  final String note;

  factory _OperationReportEntry.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final institutionId =
        snapshot.reference.parent.parent?.parent?.parent?.id ?? '';
    final entryType = (data['entryType'] ?? '').toString().trim();
    return _OperationReportEntry(
      id: snapshot.id,
      institutionId: institutionId,
      operationName: (data['operationName'] ?? '').toString().trim(),
      categoryName: (data['operationCategoryName'] ?? '').toString().trim(),
      typeLabel: _resolveTypeLabel(entryType),
      locationName: (data['locationName'] ?? '').toString().trim(),
      performedByName: (data['performedByName'] ?? '').toString().trim(),
      amount: _readAmount(data['operationPrice']),
      completedAt: _readTimestamp(data['completedAt']),
      note: (data['note'] ?? '').toString().trim(),
    );
  }

  static String _resolveTypeLabel(String entryType) {
    switch (entryType) {
      case 'sale':
        return 'Satış';
      case 'operation':
        return 'İşlem';
      case 'reservation':
        return 'Rezervasyon';
      default:
        return 'İşlem';
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
