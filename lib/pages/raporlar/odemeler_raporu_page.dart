import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/institution_controller.dart';

class OdemelerRaporuPage extends StatefulWidget {
  const OdemelerRaporuPage({super.key});

  @override
  State<OdemelerRaporuPage> createState() => _OdemelerRaporuPageState();
}

class _OdemelerRaporuPageState extends State<OdemelerRaporuPage> {
  static const String _allFilter = 'Tümü';

  final InstitutionController _institution = Get.find<InstitutionController>();

  String _selectedType = _allFilter;
  String _selectedReceiver = _allFilter;
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
        title: const Text('Gelir Raporu'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collectionGroup('odemeler').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Gelirler yüklenemedi.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data!.docs
              .map((doc) => _PaymentReportEntry.fromSnapshot(doc))
              .where((entry) => entry.institutionId == institutionId)
              .toList();

          final typeOptions = _buildFilterOptions(
            entries.map((entry) => entry.typeLabel).toList(),
          );
          final receiverOptions = _buildFilterOptions(
            entries.map((entry) => entry.receivedByName).toList(),
          );

          final selectedType =
              typeOptions.contains(_selectedType) ? _selectedType : _allFilter;
          final selectedReceiver =
              receiverOptions.contains(_selectedReceiver) ? _selectedReceiver : _allFilter;

          final filtered = entries.where((entry) {
            if (selectedType != _allFilter && entry.typeLabel != selectedType) {
              return false;
            }
            if (selectedReceiver != _allFilter &&
                entry.receivedByName != selectedReceiver) {
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
                receiverOptions: receiverOptions,
                selectedType: selectedType,
                selectedReceiver: selectedReceiver,
              ),
              const SizedBox(height: 12),
              _buildSummaryCard(filtered.length, totalAmount),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                const Center(child: Text('Filtrelere uygun gelir yok.'))
              else
                ...filtered.map(_buildPaymentCard),
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
    required List<String> typeOptions,
    required List<String> receiverOptions,
    required String selectedType,
    required String selectedReceiver,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDateQuickActions(),
        const SizedBox(height: 12),
        _buildDateRangeInputs(),
        const SizedBox(height: 12),
        _buildDropdown(
          label: 'Gelir Türü',
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
          label: 'Geliri Alan',
          value: selectedReceiver,
          options: receiverOptions,
          onChanged: (value) {
            setState(() {
              _selectedReceiver = value;
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

  Widget _buildPaymentCard(_PaymentReportEntry entry) {
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
                  entry.typeLabel,
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
            'Ödeyen: ${entry.paidByName.isNotEmpty ? entry.paidByName : '-'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            'Alan: ${entry.receivedByName.isNotEmpty ? entry.receivedByName : '-'}',
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

  String _formatPrice(double price) {
    if (price % 1 == 0) {
      return price.toStringAsFixed(0);
    }
    return price.toStringAsFixed(2);
  }
}

class _PaymentReportEntry {
  const _PaymentReportEntry({
    required this.id,
    required this.institutionId,
    required this.typeLabel,
    required this.receivedByName,
    required this.paidByName,
    required this.amount,
    required this.createdAt,
    required this.note,
  });

  final String id;
  final String institutionId;
  final String typeLabel;
  final String receivedByName;
  final String paidByName;
  final double amount;
  final DateTime? createdAt;
  final String note;

  factory _PaymentReportEntry.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final institutionId =
        snapshot.reference.parent.parent?.parent?.parent?.id ?? '';
    final type = (data['type'] ?? '').toString().trim();
    return _PaymentReportEntry(
      id: snapshot.id,
      institutionId: institutionId,
      typeLabel: _resolveTypeLabel(type),
      receivedByName: (data['receivedByName'] ?? '').toString().trim(),
      paidByName: (data['paidByName'] ?? '').toString().trim(),
      amount: _readAmount(data['amount']),
      createdAt: _readTimestamp(data['createdAt']),
      note: (data['note'] ?? '').toString().trim(),
    );
  }

  static String _resolveTypeLabel(String raw) {
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
