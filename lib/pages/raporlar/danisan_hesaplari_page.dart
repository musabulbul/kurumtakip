import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/institution_controller.dart';

class DanisanHesaplariPage extends StatefulWidget {
  const DanisanHesaplariPage({super.key});

  @override
  State<DanisanHesaplariPage> createState() => _DanisanHesaplariPageState();
}

class _DanisanHesaplariPageState extends State<DanisanHesaplariPage> {
  static const String _allFilter = 'Tümü';

  static const String _accountSortBalance = 'Bakiye (Büyükten küçüğe)';
  static const String _accountSortDebt = 'Borç (Büyükten küçüğe)';
  static const String _accountSortPayment = 'Ödeme (Büyükten küçüğe)';
  static const List<String> _accountSortOptions = [
    _accountSortBalance,
    _accountSortDebt,
    _accountSortPayment,
  ];

  static const String _packageFilterActive = 'Aktif Paket Var';
  static const String _packageFilterInactive = 'Aktif Paket Yok';

  final InstitutionController _institution = Get.find<InstitutionController>();

  String _selectedAccountSort = _accountSortBalance;
  String _selectedPackageFilter = _allFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final institutionId = (_institution.data['kurumkodu'] ?? '').toString();
    if (institutionId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Kurum bilgisi bulunamadı.')),
      );
    }

    final packageFilterOptions = [
      _allFilter,
      _packageFilterActive,
      _packageFilterInactive,
    ];
    final selectedSort = _accountSortOptions.contains(_selectedAccountSort)
        ? _selectedAccountSort
        : _accountSortBalance;
    final selectedPackageFilter = packageFilterOptions.contains(_selectedPackageFilter)
        ? _selectedPackageFilter
        : _allFilter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Danışan Hesapları'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Danışan Hesapları',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            label: 'Sıralama',
            value: selectedSort,
            options: _accountSortOptions,
            onChanged: (value) {
              setState(() {
                _selectedAccountSort = value;
              });
            },
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            label: 'Aktif Paket',
            value: selectedPackageFilter,
            options: packageFilterOptions,
            onChanged: (value) {
              setState(() {
                _selectedPackageFilter = value;
              });
            },
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('kurumlar')
                .doc(institutionId)
                .collection('danisanlar')
                .snapshots(),
            builder: (context, studentSnapshot) {
              if (studentSnapshot.hasError) {
                return const Text('Danışanlar yüklenemedi.');
              }
              if (!studentSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final studentDocs = studentSnapshot.data!.docs;

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collectionGroup('odemeler')
                    .snapshots(),
                builder: (context, paymentSnapshot) {
                  if (paymentSnapshot.hasError) {
                    return const Text('Ödemeler yüklenemedi.');
                  }
                  if (!paymentSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final paymentTotals = _buildPaymentTotals(
                    paymentSnapshot.data!.docs,
                    institutionId,
                  );

                  return FutureBuilder<Map<String, _PackageSummary>>(
                    future: _loadPackageSummaries(institutionId, studentDocs),
                    builder: (context, packageSnapshot) {
                      if (packageSnapshot.hasError) {
                        return const Text('Paketler yüklenemedi.');
                      }
                      if (!packageSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final packageSummaries = packageSnapshot.data ?? {};

                      final accounts = <_StudentAccountEntry>[];
                      for (final doc in studentDocs) {
                        final data = doc.data();
                        final name = _buildStudentName(data);
                        final balance = _readAmount(data['bakiye']);
                        final payments = paymentTotals[doc.id] ?? 0;
                        final debt = balance + payments;
                        final summary = packageSummaries[doc.id];
                        final hasActivePackage = summary?.hasActivePackage ?? false;
                        final sessionLabel = _formatPackageSessions(summary);

                        if (selectedPackageFilter == _packageFilterActive &&
                            !hasActivePackage) {
                          continue;
                        }
                        if (selectedPackageFilter == _packageFilterInactive &&
                            hasActivePackage) {
                          continue;
                        }

                        accounts.add(
                          _StudentAccountEntry(
                            id: doc.id,
                            name: name,
                            debt: debt,
                            payments: payments,
                            balance: balance,
                            sessionLabel: sessionLabel,
                            hasActivePackage: hasActivePackage,
                          ),
                        );
                      }

                      accounts.sort((a, b) {
                        switch (selectedSort) {
                          case _accountSortDebt:
                            return b.debt.compareTo(a.debt);
                          case _accountSortPayment:
                            return b.payments.compareTo(a.payments);
                          case _accountSortBalance:
                          default:
                            return b.balance.compareTo(a.balance);
                        }
                      });

                      final totalBalance = accounts.fold<double>(
                        0,
                        (sum, entry) => sum + entry.balance,
                      );

                      return Column(
                        children: [
                          _buildAccountSummaryCard(accounts.length, totalBalance),
                          const SizedBox(height: 12),
                          if (accounts.isEmpty)
                            const Center(
                              child: Text('Filtrelere uygun danışan bulunamadı.'),
                            )
                          else
                            ...accounts.map(_buildStudentAccountCard),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
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

  Map<String, double> _buildPaymentTotals(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String institutionId,
  ) {
    final totals = <String, double>{};
    for (final doc in docs) {
      final instId = doc.reference.parent.parent?.parent?.parent?.id ?? '';
      if (instId != institutionId) {
        continue;
      }
      final studentId = doc.reference.parent.parent?.id ?? '';
      if (studentId.isEmpty) {
        continue;
      }
      final amount = _readAmount(doc.data()['amount']);
      totals[studentId] = (totals[studentId] ?? 0) + amount;
    }
    return totals;
  }

  Future<Map<String, _PackageSummary>> _loadPackageSummaries(
    String institutionId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> studentDocs,
  ) async {
    final summaries = <String, _PackageSummary>{};
    for (final doc in studentDocs) {
      final studentId = doc.id;
      if (studentId.isEmpty) {
        continue;
      }
      final snapshot = await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(institutionId)
          .collection('danisanlar')
          .doc(studentId)
          .collection('paketler')
          .where('durum', isEqualTo: 'aktif')
          .get();
      if (snapshot.docs.isEmpty) {
        continue;
      }
      final summary = summaries.putIfAbsent(studentId, () => _PackageSummary());
      _accumulatePackageSummary(summary, snapshot.docs);
    }
    return summaries;
  }

  void _accumulatePackageSummary(
    _PackageSummary summary,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    for (final doc in docs) {
      final data = doc.data();
      final status = (data['durum'] ?? '').toString().trim();
      if (status != 'aktif') {
        continue;
      }
      summary.activePackageCount += 1;
      final operations = data['islemler'];
      if (operations is! List) {
        continue;
      }
      for (final entry in operations) {
        final map =
            entry is Map ? Map<String, dynamic>.from(entry) : <String, dynamic>{};
        final unlimited = (map['sinirsiz'] ?? false) == true;
        if (unlimited) {
          summary.hasUnlimited = true;
          continue;
        }
        final totalSessions = _readInt(map['seansSayisi']);
        final doneSessions = _readInt(map['yapilanSeans']);
        final remainingSessions = _readInt(map['kalanSeans']);
        final hasRemaining = map.containsKey('kalanSeans');
        final resolvedTotal = totalSessions > 0 ? totalSessions : 0;
        final resolvedRemaining =
            hasRemaining ? remainingSessions : (resolvedTotal - doneSessions);
        summary.totalSessions += resolvedTotal;
        summary.remainingSessions += resolvedRemaining > 0 ? resolvedRemaining : 0;
      }
    }
  }

  String _formatPackageSessions(_PackageSummary? summary) {
    if (summary == null || !summary.hasActivePackage) {
      return '';
    }
    if (summary.hasUnlimited) {
      return 'Sınırsız';
    }
    if (summary.totalSessions <= 0) {
      return '';
    }
    return '${summary.remainingSessions}/${summary.totalSessions}';
  }

  int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _readAmount(dynamic value) {
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

  String _buildStudentName(Map<String, dynamic> data) {
    final name = (data['adi'] ?? '').toString().trim();
    final surname = (data['soyadi'] ?? '').toString().trim();
    final fullName = [name, surname].where((part) => part.isNotEmpty).join(' ');
    return fullName.isNotEmpty ? fullName : '-';
  }

  Widget _buildAccountSummaryCard(int count, double totalBalance) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Danışan: $count',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              'Toplam Bakiye: ${_formatPrice(totalBalance)} TL',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentAccountCard(_StudentAccountEntry entry) {
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
                  entry.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${_formatPrice(entry.balance)} TL',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Borç: ${_formatPrice(entry.debt)} TL',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            'Ödeme: ${_formatPrice(entry.payments)} TL',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            'Bakiye: ${_formatPrice(entry.balance)} TL',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (entry.sessionLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Seans: ${entry.sessionLabel}',
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

class _StudentAccountEntry {
  const _StudentAccountEntry({
    required this.id,
    required this.name,
    required this.debt,
    required this.payments,
    required this.balance,
    required this.sessionLabel,
    required this.hasActivePackage,
  });

  final String id;
  final String name;
  final double debt;
  final double payments;
  final double balance;
  final String sessionLabel;
  final bool hasActivePackage;
}

class _PackageSummary {
  _PackageSummary({
    this.hasUnlimited = false,
    this.totalSessions = 0,
    this.remainingSessions = 0,
    this.activePackageCount = 0,
  });

  bool hasUnlimited;
  int totalSessions;
  int remainingSessions;
  int activePackageCount;

  bool get hasActivePackage => activePackageCount > 0;
}
