import 'dart:async';

import 'package:characters/characters.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../controllers/institution_controller.dart';
import '../controllers/user_controller.dart';
import '../services/sms_service.dart';
import '../utils/export_utils.dart';
import '../utils/phone_utils.dart';
import '../utils/student_utils.dart';
import '../utils/text_utils.dart';
import '../widgets/home_icon_button.dart';
import 'danisan_profil.dart';

class DetayliAra extends StatefulWidget {
  const DetayliAra({super.key});

  @override
  State<DetayliAra> createState() => _DetayliAraState();
}

class _DetayliAraState extends State<DetayliAra> {
  final InstitutionController kurum = Get.find<InstitutionController>();
  final UserController _user = Get.find<UserController>();

  final TextEditingController _searchController = TextEditingController();
  final List<Map<String, dynamic>> _allDanisanlar = [];
  final List<Map<String, dynamic>> _filteredDanisanlar = [];
  final Set<String> _studentsWithActivePackages = <String>{};
  final Set<String> _selectedStudentIds = <String>{};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  Worker? _institutionWorker;
  String _selectedGender = _genderAll;
  String _searchMode = _searchModeName;
  String _sortMode = _sortByLastOperation;
  String _packageFilter = _packageAll;

  static const String _genderAll = 'Tümü';
  static const String _genderFemale = 'Kadın';
  static const String _genderMale = 'Erkek';
  static const String _searchModeName = 'İsme göre';
  static const String _searchModePhone = 'Telefona göre';
  static const String _sortByLastOperation = 'Son işlem';
  static const String _sortByRegisterDate = 'Kayıt tarihi';
  static const String _packageAll = 'Paket: Tümü';
  static const String _packageActive = 'Paket: Aktif var';
  static const String _packageInactive = 'Paket: Aktif yok';
  static const String _smsTypeInfo = 'bilgi';
  static const String _smsTypeCommercial = 'ticari';
  static const int _smsTurkceLimit = 155;

  @override
  void initState() {
    super.initState();
    _listenDanisanlar();
    _institutionWorker = ever(kurum.data, (_) => _listenDanisanlar());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _institutionWorker?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _listenDanisanlar() {
    final institutionId = (kurum.data['kurumkodu'] ?? '').toString();
    if (institutionId.isEmpty) {
      _subscription?.cancel();
      _allDanisanlar.clear();
      _filteredDanisanlar.clear();
      _studentsWithActivePackages.clear();
      _selectedStudentIds.clear();
      setState(() {});
      return;
    }
    _subscription?.cancel();
    _subscription = FirebaseFirestore.instance
        .collection('kurumlar')
        .doc(institutionId)
        .collection('danisanlar')
        .orderBy('adi')
        .snapshots()
        .listen((snapshot) {
      _allDanisanlar
        ..clear()
        ..addAll(snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }));
      unawaited(_refreshActivePackageStudents(institutionId, snapshot.docs));
      _applyFilters();
    }, onError: (error) {
      // ignore: avoid_print
      print('[detayli_ara] danisan listen error | $error');
    });
  }

  Future<void> _refreshActivePackageStudents(
    String institutionId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> studentDocs,
  ) async {
    final activeStudents = <String>{};
    for (final studentDoc in studentDocs) {
      try {
        final packages = await FirebaseFirestore.instance
            .collection('kurumlar')
            .doc(institutionId)
            .collection('danisanlar')
            .doc(studentDoc.id)
            .collection('paketler')
            .where('durum', isEqualTo: 'aktif')
            .limit(1)
            .get();
        if (packages.docs.isNotEmpty) {
          activeStudents.add(studentDoc.id);
        }
      } catch (error) {
        // ignore: avoid_print
        print(
          '[detayli_ara] aktif paket sorgu hatasi | studentId=${studentDoc.id} | error=$error',
        );
      }
    }
    if (!mounted) {
      return;
    }
    _studentsWithActivePackages
      ..clear()
      ..addAll(activeStudents);
    _applyFilters();
  }

  void _applyFilters() {
    final query = _searchController.text.trim();
    final normalizedQuery = normalizeTr(query);
    final digitsQuery = _digitsOnly(query);
    final genderFilter = _selectedGender;
    _filteredDanisanlar
      ..clear()
      ..addAll(_allDanisanlar.where((danisan) {
        final id = resolveStudentId(danisan);
        final name = normalizeTr((danisan['adi'] ?? '').toString());
        final surname = normalizeTr((danisan['soyadi'] ?? '').toString());
        final phoneDigits = _digitsOnly(_resolvePhone(danisan));
        final gender = normalizeTr((danisan['cinsiyet'] ?? '').toString());
        final hasActivePackage = _studentsWithActivePackages.contains(id);

        final matchesSearch = query.isEmpty ||
            (_searchMode == _searchModeName &&
                (name.contains(normalizedQuery) || surname.contains(normalizedQuery))) ||
            (_searchMode == _searchModePhone &&
                digitsQuery.isNotEmpty &&
                phoneDigits.contains(digitsQuery));

        final matchesGender = genderFilter == _genderAll ||
            (genderFilter == _genderFemale && gender == 'kadın') ||
            (genderFilter == _genderMale && gender == 'erkek');

        final matchesPackage = _packageFilter == _packageAll ||
            (_packageFilter == _packageActive && hasActivePackage) ||
            (_packageFilter == _packageInactive && !hasActivePackage);

        return matchesSearch && matchesGender && matchesPackage;
      }));

    _filteredDanisanlar.sort((a, b) {
      final firstDate = _sortMode == _sortByRegisterDate
          ? _readRegistrationDate(a)
          : _readLastOperationDate(a);
      final secondDate = _sortMode == _sortByRegisterDate
          ? _readRegistrationDate(b)
          : _readLastOperationDate(b);

      if (firstDate == null && secondDate == null) {
        final firstName =
            '${(a['adi'] ?? '').toString()} ${(a['soyadi'] ?? '').toString()}'.trim();
        final secondName =
            '${(b['adi'] ?? '').toString()} ${(b['soyadi'] ?? '').toString()}'.trim();
        return normalizeTr(firstName).compareTo(normalizeTr(secondName));
      }
      if (firstDate == null) {
        return 1;
      }
      if (secondDate == null) {
        return -1;
      }
      return secondDate.compareTo(firstDate);
    });

    final allById = <String, Map<String, dynamic>>{
      for (final student in _allDanisanlar) resolveStudentId(student): student,
    };
    _selectedStudentIds.removeWhere((id) {
      final student = allById[id];
      if (student == null) {
        return true;
      }
      return _resolvePhone(student).isEmpty;
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detaylı Danışan Arama'),
        actions: const [HomeIconButton()],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _buildSearchField(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: _buildSearchModeFilter(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: _buildGenderFilter(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _buildSortAndPackageFilters(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _buildSummaryRow(),
            ),
            const Divider(height: 1),
            if (_filteredDanisanlar.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Eşleşen danışan bulunamadı.'),
              )
            else
              ListView.builder(
                padding: const EdgeInsets.all(16),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _filteredDanisanlar.length,
                itemBuilder: (context, index) {
                  final danisan = _filteredDanisanlar[index];
                  return _buildDanisanCard(danisan);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => _applyFilters(),
      decoration: InputDecoration(
        hintText: _searchMode == _searchModePhone
            ? 'Telefon numarasına göre ara...'
            : 'İsme göre ara...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  _applyFilters();
                },
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSearchModeFilter() {
    final theme = Theme.of(context);
    final selectedBg = theme.colorScheme.primary.withOpacity(0.18);
    final unselectedBg = theme.colorScheme.surface;
    final selectedBorder = theme.colorScheme.primary;
    final unselectedBorder = theme.colorScheme.outlineVariant;
    final options = [_searchModeName, _searchModePhone];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = _searchMode == option;
        return ChoiceChip(
          label: Text(option),
          selected: isSelected,
          showCheckmark: false,
          backgroundColor: unselectedBg,
          selectedColor: selectedBg,
          side: BorderSide(
            color: isSelected ? selectedBorder : unselectedBorder,
            width: isSelected ? 1.6 : 1.0,
          ),
          labelStyle: theme.textTheme.titleSmall?.copyWith(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
          ),
          onSelected: (_) {
            setState(() {
              _searchMode = option;
            });
            _applyFilters();
          },
        );
      }).toList(),
    );
  }

  Widget _buildGenderFilter() {
    final theme = Theme.of(context);
    final selectedBg = theme.colorScheme.primary.withOpacity(0.18);
    final unselectedBg = theme.colorScheme.surface;
    final selectedBorder = theme.colorScheme.primary;
    final unselectedBorder = theme.colorScheme.outlineVariant;
    final options = [_genderAll, _genderFemale, _genderMale];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = option == _selectedGender;
        return ChoiceChip(
          label: Text(option),
          selected: isSelected,
          showCheckmark: false,
          backgroundColor: unselectedBg,
          selectedColor: selectedBg,
          side: BorderSide(
            color: isSelected ? selectedBorder : unselectedBorder,
            width: isSelected ? 1.6 : 1.0,
          ),
          labelStyle: theme.textTheme.titleSmall?.copyWith(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
          ),
          onSelected: (_) {
            setState(() => _selectedGender = option);
            _applyFilters();
          },
        );
      }).toList(),
    );
  }

  Widget _buildSortAndPackageFilters() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        final sortDropdown = DropdownButtonFormField<String>(
          value: _sortMode,
          items: const [
            DropdownMenuItem(
              value: _sortByLastOperation,
              child: Text('Son işlem'),
            ),
            DropdownMenuItem(
              value: _sortByRegisterDate,
              child: Text('Kayıt tarihi'),
            ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _sortMode = value;
            });
            _applyFilters();
          },
          decoration: const InputDecoration(
            labelText: 'Sıralama',
            border: OutlineInputBorder(),
          ),
        );

        final packageDropdown = DropdownButtonFormField<String>(
          value: _packageFilter,
          items: const [
            DropdownMenuItem(
              value: _packageAll,
              child: Text('Paket: Tümü'),
            ),
            DropdownMenuItem(
              value: _packageActive,
              child: Text('Paket: Aktif var'),
            ),
            DropdownMenuItem(
              value: _packageInactive,
              child: Text('Paket: Aktif yok'),
            ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _packageFilter = value;
            });
            _applyFilters();
          },
          decoration: const InputDecoration(
            labelText: 'Paket filtresi',
            border: OutlineInputBorder(),
          ),
        );

        if (compact) {
          return Column(
            children: [
              sortDropdown,
              const SizedBox(height: 10),
              packageDropdown,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: sortDropdown),
            const SizedBox(width: 12),
            Expanded(child: packageDropdown),
          ],
        );
      },
    );
  }

  Widget _buildSummaryRow() {
    final activeCount = _allDanisanlar.where((danisan) {
      final id = resolveStudentId(danisan);
      return _studentsWithActivePackages.contains(id);
    }).length;
    final isAdmin = (_user.data['rol'] ?? '').toString() == 'YÖNETİCİ';
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Toplam: ${_allDanisanlar.length}'),
        Text('Aktif paketli: $activeCount'),
        Text('Listelenen: ${_filteredDanisanlar.length}'),
        OutlinedButton(
          onPressed: _filteredDanisanlar.isEmpty ? null : _selectAllVisibleWithPhone,
          child: const Text('Tümünü Seç'),
        ),
        OutlinedButton(
          onPressed: _selectedStudentIds.isEmpty ? null : _clearSelections,
          child: const Text('Temizle'),
        ),
        FilledButton.icon(
          onPressed: _selectedStudentIds.isEmpty ? null : _openBulkSmsDialog,
          icon: const Icon(Icons.sms_outlined),
          label: Text('SMS Gönder (${_selectedStudentIds.length})'),
        ),
        if (isAdmin) ...[
          OutlinedButton.icon(
            onPressed: _filteredDanisanlar.isEmpty ? null : () => _exportExcel(context),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Excel'),
          ),
          OutlinedButton.icon(
            onPressed: _filteredDanisanlar.isEmpty ? null : () => _exportPdf(context),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF'),
          ),
        ],
      ],
    );
  }

  void _exportExcel(BuildContext context) {
    final sortLabel = _sortMode == _sortByRegisterDate ? 'Kayıt Tarihi' : 'Son İşlem';
    ExportUtils.shareExcel(
      context: context,
      fileBaseName: 'danisan_listesi',
      headers: ['Ad Soyad', 'Telefon', 'Cinsiyet', sortLabel, 'Aktif Paket'],
      rows: _filteredDanisanlar.map((d) {
        final name =
            '${(d['adi'] ?? '').toString()} ${(d['soyadi'] ?? '').toString()}'.trim();
        final phone = _resolvePhone(d);
        final gender = (d['cinsiyet'] ?? '').toString();
        final id = resolveStudentId(d);
        final date = _sortMode == _sortByRegisterDate
            ? _readRegistrationDate(d)
            : _readLastOperationDate(d);
        return [
          name.isEmpty ? 'İsimsiz' : name,
          phone.isEmpty ? '-' : phone,
          gender.isEmpty ? '-' : gender,
          _formatDateLabel(date),
          _studentsWithActivePackages.contains(id) ? 'Var' : 'Yok',
        ];
      }).toList(),
    );
  }

  void _exportPdf(BuildContext context) {
    final sortLabel = _sortMode == _sortByRegisterDate ? 'Kayıt' : 'Son İşlem';
    ExportUtils.sharePdf(
      context: context,
      title: 'Danışan Listesi',
      headers: ['Ad Soyad', 'Telefon', 'Cinsiyet', sortLabel, 'Paket'],
      rows: _filteredDanisanlar.map((d) {
        final name =
            '${(d['adi'] ?? '').toString()} ${(d['soyadi'] ?? '').toString()}'.trim();
        final phone = _resolvePhone(d);
        final gender = (d['cinsiyet'] ?? '').toString();
        final id = resolveStudentId(d);
        final date = _sortMode == _sortByRegisterDate
            ? _readRegistrationDate(d)
            : _readLastOperationDate(d);
        return [
          name.isEmpty ? 'İsimsiz' : name,
          phone.isEmpty ? '-' : phone,
          gender.isEmpty ? '-' : gender,
          _formatDateLabel(date),
          _studentsWithActivePackages.contains(id) ? 'Var' : 'Yok',
        ];
      }).toList(),
    );
  }

  Widget _buildDanisanCard(Map<String, dynamic> danisan) {
    final adi = (danisan['adi'] ?? '').toString();
    final soyadi = (danisan['soyadi'] ?? '').toString();
    final phone = _resolvePhone(danisan);
    final gender = (danisan['cinsiyet'] ?? '').toString();
    final id = resolveStudentId(danisan);
    final isSelected = _selectedStudentIds.contains(id);
    final hasActivePackage = _studentsWithActivePackages.contains(id);
    final lastOperationDate = _readLastOperationDate(danisan);
    final registerDate = _readRegistrationDate(danisan);
    final dateLabel = _sortMode == _sortByRegisterDate
        ? _formatDateLabel(registerDate)
        : _formatDateLabel(lastOperationDate);
    final dateTitle = _sortMode == _sortByRegisterDate ? 'Kayıt' : 'Son işlem';
    final firstInitial = adi.isNotEmpty ? adi.characters.first.toUpperCase() : '';
    final secondInitial = soyadi.isNotEmpty ? soyadi.characters.first.toUpperCase() : '';
    final initials = (firstInitial + secondInitial).padRight(2, '?').substring(0, 2);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () {
          final id = resolveStudentId(danisan);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DanisanProfil(id: id)),
          );
        },
        leading: CircleAvatar(
          backgroundColor: Colors.purple.shade100,
          child: Text(initials),
        ),
        title: Text(
          "$adi $soyadi".trim().isEmpty ? 'İsimsiz Danışan' : "$adi $soyadi",
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(phone.isEmpty ? '-' : phone),
            Text('$dateTitle: $dateLabel'),
            if (gender.isNotEmpty)
              Text(
                gender,
                style: const TextStyle(color: Colors.black54),
              ),
            Text(
              hasActivePackage ? 'Aktif paket: Var' : 'Aktif paket: Yok',
              style: TextStyle(
                color: hasActivePackage ? Colors.green.shade700 : Colors.black54,
              ),
            ),
          ],
        ),
        trailing: phone.isEmpty
            ? Checkbox(
                value: false,
                onChanged: null,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.phone, color: Colors.green),
                    onPressed: () => _launchDialer(phone),
                  ),
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelection(id),
                  ),
                ],
              ),
      ),
    );
  }

  void _toggleSelection(String studentId) {
    setState(() {
      if (_selectedStudentIds.contains(studentId)) {
        _selectedStudentIds.remove(studentId);
      } else {
        _selectedStudentIds.add(studentId);
      }
    });
  }

  void _selectAllVisibleWithPhone() {
    setState(() {
      for (final student in _filteredDanisanlar) {
        final phone = _resolvePhone(student);
        if (phone.isEmpty) {
          continue;
        }
        final id = resolveStudentId(student);
        if (id.isNotEmpty) {
          _selectedStudentIds.add(id);
        }
      }
    });
  }

  void _clearSelections() {
    setState(() {
      _selectedStudentIds.clear();
    });
  }

  Future<void> _openBulkSmsDialog() async {
    final institutionId = (kurum.data['kurumkodu'] ?? '').toString().trim();
    if (institutionId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
      );
      return;
    }

    final selectedStudents = _allDanisanlar.where((student) {
      final id = resolveStudentId(student);
      return _selectedStudentIds.contains(id);
    }).toList();
    final phones = selectedStudents
        .map(_resolvePhone)
        .where((phone) => phone.trim().isNotEmpty)
        .toSet()
        .toList();
    if (phones.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seçilen kişilerde geçerli telefon numarası yok.')),
      );
      return;
    }

    final messageController = TextEditingController();
    var smsType = _smsTypeInfo;
    var isSending = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !isSending,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final charCount = messageController.text.characters.length;
            final overLimit = charCount > _smsTurkceLimit;
            return AlertDialog(
              title: const Text('SMS Gönder'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: smsType,
                      items: const [
                        DropdownMenuItem(
                          value: _smsTypeInfo,
                          child: Text('bilgi'),
                        ),
                        DropdownMenuItem(
                          value: _smsTypeCommercial,
                          child: Text('ticari'),
                        ),
                      ],
                      onChanged: isSending
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              setDialogState(() {
                                smsType = value;
                              });
                            },
                      decoration: const InputDecoration(
                        labelText: 'SMS Türü',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: messageController,
                      minLines: 4,
                      maxLines: 8,
                      enabled: !isSending,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Mesaj',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '$charCount/$_smsTurkceLimit',
                        style: TextStyle(
                          color: overLimit ? Colors.red : Colors.black54,
                          fontWeight: overLimit ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSending ? null : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          final message = messageController.text.trim();
                          if (message.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Mesaj boş olamaz.')),
                            );
                            return;
                          }

                          final confirmed = await _confirmBulkSmsSend(phones.length);
                          if (!confirmed) {
                            return;
                          }

                          setDialogState(() {
                            isSending = true;
                          });
                          final sendResult = await SmsService().sendSms(
                            kurumId: institutionId,
                            phones: phones,
                            message: message,
                            providerId: (kurum.data['smsProviderId'] ?? '').toString().trim(),
                            messageContentType: smsType,
                          );
                          if (!mounted || !dialogContext.mounted) {
                            return;
                          }
                          setDialogState(() {
                            isSending = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(sendResult.message)),
                          );
                          if (sendResult.success) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        },
                  child: isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Gönder'),
                ),
              ],
            );
          },
        );
      },
    );

    messageController.dispose();

    if (result == true && mounted) {
      setState(() {
        _selectedStudentIds.clear();
      });
    }
  }

  Future<bool> _confirmBulkSmsSend(int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Onay'),
          content: Text('Mesaj $count kişiye gönderilecek, emin misiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Hayır'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Evet'),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  String _resolvePhone(Map<String, dynamic> data) {
    final primary = normalizePhone((data['telefon'] ?? '').toString());
    if (primary.isNotEmpty) {
      return primary;
    }
    return normalizePhone((data['ogrencitel'] ?? '').toString());
  }

  DateTime? _readRegistrationDate(Map<String, dynamic> danisan) {
    return _readDateValue(
          danisan['kayittarihi'],
        ) ??
        _readDateValue(danisan['olusturulmaZamani']) ??
        _readDateValue(danisan['olusturulmazamani']) ??
        _readDateValue(danisan['createdAt']);
  }

  DateTime? _readLastOperationDate(Map<String, dynamic> danisan) {
    return _readDateValue(danisan['sonislemtarihi']) ??
        _readDateValue(danisan['sonIslemTarihi']) ??
        _readRegistrationDate(danisan);
  }

  DateTime? _readDateValue(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    final value = raw.toString().trim();
    if (value.isEmpty) {
      return null;
    }
    final normalized = value.contains('T') ? value : value.replaceAll('.', '-');
    return DateTime.tryParse(normalized);
  }

  String _formatDateLabel(DateTime? date) {
    if (date == null) {
      return '-';
    }
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day.$month.$year';
  }

  String _digitsOnly(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9]'), '');
  }

  Future<void> _launchDialer(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await launcher.canLaunchUrl(uri)) {
      await launcher.launchUrl(uri);
    }
  }
}
