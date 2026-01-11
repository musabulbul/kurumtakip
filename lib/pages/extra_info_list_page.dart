import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import '../controllers/institution_controller.dart';
import 'danisan_profil.dart';

class ExtraInfoListPage extends StatefulWidget {
  const ExtraInfoListPage({super.key});

  @override
  State<ExtraInfoListPage> createState() => _ExtraInfoListPageState();
}

class _ExtraInfoListPageState extends State<ExtraInfoListPage> {
  final InstitutionController kurum = Get.find<InstitutionController>();

  final ValueNotifier<Set<String>> _selectedKeys = ValueNotifier(<String>{});
  List<ExtraInfoRecord> _latestRecords = const [];
  bool _isExporting = false;

  @override
  void dispose() {
    _selectedKeys.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final institutionId = (kurum.data['kurumkodu'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ek Bilgiler'),
        actions: [
          ValueListenableBuilder<Set<String>>(
            valueListenable: _selectedKeys,
            builder: (context, selected, _) {
              return IconButton(
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Excel\'e Aktar',
                onPressed: _isExporting ? null : () => _exportToExcel(selected),
              );
            },
          ),
          const HomeIconButton(),
        ],
      ),
      body: institutionId.isEmpty
          ? const Center(child: Text('Kurum bilgisi bulunamadı.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collectionGroup('ekbilgiler')
                  .where('institutionId', isEqualTo: institutionId)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  final message = snapshot.error.toString();
                  if (message.contains('requires an index') ||
                      message.contains('FAILED_PRECONDITION')) {
                    return const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        'Verileri görüntülemek için Firestore endeksi gerekli. '
                        'Lütfen yönetici ile iletişime geçiniz.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text('Ek bilgiler yüklenirken hata oluştu: $message'),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? const [];
                final records = docs.map(ExtraInfoRecord.fromDoc).toList();
                _latestRecords = records;

                final validKeys = records.map((record) => record.key).toSet();
                final currentSelection = _selectedKeys.value;
                final filteredSelection =
                    currentSelection.where(validKeys.contains).toSet();
                if (!setEquals(currentSelection, filteredSelection)) {
                  _selectedKeys.value = filteredSelection;
                }

                if (records.isEmpty) {
                  return const Center(child: Text('Henüz ek bilgi eklenmemiş.'));
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: ValueListenableBuilder<Set<String>>(
                        valueListenable: _selectedKeys,
                        builder: (context, selected, _) {
                          return Row(
                            children: [
                              Text('Toplam: ${records.length}'),
                              const SizedBox(width: 16),
                              Text('Seçili: ${selected.length}'),
                              const Spacer(),
                              TextButton(
                                onPressed: selected.length == records.length
                                    ? null
                                    : () => _toggleSelectAll(records),
                                child: const Text('Tümünü Seç'),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: selected.isEmpty
                                    ? null
                                    : () => _selectedKeys.value = <String>{},
                                child: const Text('Temizle'),
                              )
                            ],
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 960),
                            child: ValueListenableBuilder<Set<String>>(
                              valueListenable: _selectedKeys,
                              builder: (context, selected, _) {
                                return SingleChildScrollView(
                                  child: DataTable(
                                    showCheckboxColumn: true,
                                    columns: const [
                                      DataColumn(label: Text('Adı')),
                                      DataColumn(label: Text('Soyadı')),
                                      DataColumn(label: Text('Telefon')),
                                      DataColumn(label: Text('Ek Bilgi')),
                                      DataColumn(label: Text('Ekleyen')),
                                      DataColumn(label: Text('Tarih')),
                                      DataColumn(label: Text('Saat')),
                                    ],
                                    rows: records.map((record) {
                                      final isSelected = selected.contains(record.key);
                                      return DataRow(
                                        selected: isSelected,
                                        onSelectChanged: (value) =>
                                            _toggleSelection(record.key, value),
                                        cells: [
                                          DataCell(
                                            InkWell(
                                              onTap: () => _openDanisanProfile(record.danisanId),
                                              child: Text(record.danisanFirstName.isEmpty
                                                  ? '-'
                                                  : record.danisanFirstName),
                                            ),
                                          ),
                                          DataCell(Text(
                                              record.danisanLastName.isEmpty
                                                  ? '-'
                                                  : record.danisanLastName)),
                                          DataCell(Text(
                                              record.danisanPhone.isEmpty
                                                  ? '-'
                                                  : record.danisanPhone)),
                                          DataCell(Text(
                                              record.extraInfo.isEmpty
                                                  ? '-'
                                                  : record.extraInfo)),
                                          DataCell(Text(
                                              record.author.isEmpty ? '-' : record.author)),
                                          DataCell(Text(record.formattedDate ?? '-')),
                                          DataCell(Text(record.formattedTime ?? '-')),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  void _toggleSelection(String key, bool? value) {
    final updated = <String>{..._selectedKeys.value};
    if (value == true) {
      updated.add(key);
    } else {
      updated.remove(key);
    }
    _selectedKeys.value = updated;
  }

  void _toggleSelectAll(List<ExtraInfoRecord> records) {
    _selectedKeys.value = records.map((record) => record.key).toSet();
  }

  Future<void> _exportToExcel(Set<String> selected) async {
    final records = selected.isEmpty
        ? _latestRecords
        : _latestRecords.where((record) => selected.contains(record.key)).toList();

    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dışa aktarılacak kayıt seçilmedi.')),
      );
      return;
    }

    setState(() => _isExporting = true);
    try {
      final excel = Excel.createExcel();
      if (kIsWeb) {
        excel['EkBilgiler'];
      } else {
        try {
          excel.rename('Sheet1', 'EkBilgiler');
        } catch (_) {
          excel['EkBilgiler'];
        }
        try {
          if (excel.sheets.containsKey('Sheet1')) {
            excel.delete('Sheet1');
          }
        } catch (_) {}
      }
      excel.setDefaultSheet('EkBilgiler');
      final sheet = excel['EkBilgiler'];
      sheet.appendRow(<String>[
        'Adı',
        'Soyadı',
        'Telefon',
        'Ek Bilgi',
        'Ekleyen',
        'Tarih',
        'Saat',
      ]);

      for (final record in records) {
        sheet.appendRow(<String>[
          record.danisanFirstName,
          record.danisanLastName,
          record.danisanPhone,
          record.extraInfo,
          record.author,
          record.formattedDate ?? '',
          record.formattedTime ?? '',
        ]);
      }

      await excel.save(fileName: 'ek_bilgiler.xlsx');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${records.length} kayıt dışa aktarıldı.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Excel oluşturulamadı: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _openDanisanProfile(String danisanId) async {
    if (danisanId.isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DanisanProfil(id: danisanId)),
    );
  }
}

class ExtraInfoRecord {
  ExtraInfoRecord({
    required this.id,
    required this.key,
    required this.reference,
    required this.danisanId,
    required this.danisanFirstName,
    required this.danisanLastName,
    required this.danisanPhone,
    required this.extraInfo,
    required this.author,
    required this.createdAt,
  })  : formattedDate = createdAt != null ? DateFormat('dd.MM.yyyy').format(createdAt) : null,
        formattedTime = createdAt != null ? DateFormat('HH:mm').format(createdAt) : null;

  factory ExtraInfoRecord.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = _toDateTime(data['createdAt']) ?? _toDateTime(data['createdat']);
    return ExtraInfoRecord(
      id: doc.id,
      key: doc.reference.path,
      reference: doc.reference,
      danisanId: (data['danisanId'] ?? data['ogrenciid'] ?? data['studentId'] ?? '').toString(),
      danisanFirstName: (data['danisanAdi'] ?? data['studentFirstName'] ?? '').toString(),
      danisanLastName: (data['danisanSoyadi'] ?? data['studentLastName'] ?? '').toString(),
      danisanPhone:
          (data['danisanTelefon'] ?? data['telefon'] ?? data['studentNumber'] ?? '').toString(),
      extraInfo: (data['ekbilgi'] ?? '').toString(),
      author: (data['createdByShortName'] ?? data['yazan'] ?? '').toString(),
      createdAt: createdAt,
    );
  }

  final String id;
  final String key;
  final DocumentReference<Map<String, dynamic>> reference;
  final String danisanId;
  final String danisanFirstName;
  final String danisanLastName;
  final String danisanPhone;
  final String extraInfo;
  final String author;
  final DateTime? createdAt;
  final String? formattedDate;
  final String? formattedTime;

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
