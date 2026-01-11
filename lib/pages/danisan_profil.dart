import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../controllers/institution_controller.dart';
import '../controllers/user_controller.dart';
import '../widgets/home_icon_button.dart';
import '../utils/image_utils.dart';
import '../utils/phone_utils.dart';

enum _ProfileMenuAction { delete }

enum _ReservationMenuAction { delete }

enum _PaymentType { cash, card, transfer }

class DanisanProfil extends StatefulWidget {
  const DanisanProfil({super.key, required this.id});

  final String id;

  @override
  State<DanisanProfil> createState() => _DanisanProfilState();
}

class _DanisanProfilState extends State<DanisanProfil> {
  static const bool _enableReservationLogs = true;

  final UserController user = Get.find<UserController>();
  final InstitutionController kurum = Get.find<InstitutionController>();
  Map<String, dynamic>? _danisanData;
  bool _photoInitialized = false;
  bool _photoLoading = false;
  String? _photoUrl;
  bool _isDeletingStudent = false;
  bool _showPastReservations = false;
  late Future<DocumentSnapshot<Map<String, dynamic>>> _profileFuture;

  DocumentReference<Map<String, dynamic>> get _danisanDoc =>
      FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(kurum.data['kurumkodu'])
          .collection('danisanlar')
          .doc(widget.id);

  CollectionReference<Map<String, dynamic>> get _extraInfoCollection =>
      _danisanDoc.collection('ekbilgiler');

  CollectionReference<Map<String, dynamic>> get _reservationCollection =>
      FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(kurum.data['kurumkodu'])
          .collection('rezervasyonlar');

  CollectionReference<Map<String, dynamic>> get _mekanCollection =>
      FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(kurum.data['kurumkodu'])
          .collection('mekanlar');

  CollectionReference<Map<String, dynamic>> get _paymentCollection =>
      _danisanDoc.collection('odemeler');

  CollectionReference<Map<String, dynamic>> get _operationCategoryCollection =>
      FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(kurum.data['kurumkodu'])
          .collection('islemKategorileri');

  bool get _canEdit => (user.data['rol'] ?? '').toString().toUpperCase() == 'YÖNETİCİ';

  void _logReservation(String message, [Object? details]) {
    if (!_enableReservationLogs) {
      return;
    }
    final suffix = details == null ? '' : ' | $details';
    debugPrint('[reservation] $message$suffix');
  }

  Future<void> _disposeReservationDrafts(
    List<_ReservationOperationDraft> entries,
    List<_ReservationOperationDraft> removedEntries,
  ) async {
    if (entries.isEmpty && removedEntries.isEmpty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    for (final entry in entries) {
      entry.dispose();
    }
    for (final entry in removedEntries) {
      entry.dispose();
    }
  }

  Future<void> _disposeControllers(List<TextEditingController> controllers) async {
    if (controllers.isEmpty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    _profileFuture = _danisanDoc.get();
  }

  Widget _buildAppBarMenu() {
    if (_isDeletingStudent) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return PopupMenuButton<_ProfileMenuAction>(
      onSelected: (value) {
        if (value == _ProfileMenuAction.delete) {
          _confirmDeleteStudent();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _ProfileMenuAction.delete,
          child: Text('Danışanı Sil'),
        ),
      ],
      icon: const Icon(Icons.more_vert),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danışan Profili'),
        actions: [
          if (_canEdit) _buildAppBarMenu(),
          const HomeIconButton(),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Danışan bilgisi alınamadı: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Danışan bulunamadı.'));
          }

          final fetchedData = snapshot.data!.data() ?? {};
          _danisanData ??= fetchedData;
          final data = _danisanData!;
          if (!_photoInitialized) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              _ensurePhotoInitialized(data);
            });
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildPhotoHeader(data),
              const SizedBox(height: 12),
              _buildBalanceSection(data),
              const SizedBox(height: 16),
              _buildReservationsSection(data),
              const SizedBox(height: 16),
              _buildCompletedOperationsSection(),
            ],
          );
        },
      ),
    );
  }

  void _ensurePhotoInitialized(Map<String, dynamic> data) {
    if (_photoInitialized) {
      return;
    }
    _photoInitialized = true;
    _loadPhoto(data);
  }

  Future<void> _loadPhoto(Map<String, dynamic> data) async {
    if (_photoLoading) {
      return;
    }
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    if (kurumkodu.isEmpty) {
      return;
    }
    setState(() {
      _photoLoading = true;
    });
    try {
      final url = await _tryFetchPhotoUrl(kurumkodu, data);
      if (!mounted) {
        return;
      }
      setState(() {
        _photoUrl = url;
      });
    } catch (error, stackTrace) {
      debugPrint('Photo load failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf yüklenirken bir hata oluştu.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _photoLoading = false;
        });
      }
    }
  }

  Future<String?> _tryFetchPhotoUrl(String kurumkodu, Map<String, dynamic> data) async {
    final storageRef = FirebaseStorage.instance.ref('$kurumkodu/danisanlar');
    final candidates = <String>{
      widget.id,
      (data['id'] ?? '').toString(),
      (data['adi'] ?? '').toString(),
      
    }.where((element) => element.trim().isNotEmpty).toList();
    const extensions = ['jpg', 'jpeg', 'png', 'JPG', 'JPEG', 'PNG'];

    for (final candidate in candidates) {
      for (final ext in extensions) {
        try {
          final url = await storageRef.child('${candidate.trim()}.$ext').getDownloadURL();
          return url;
        } on FirebaseException catch (error) {
          if (error.code == 'object-not-found') {
            continue;
          }
          rethrow;
        }
      }
    }
    return null;
  }

  Widget _buildPhotoHeader(Map<String, dynamic> data) {
    final name = (data['adi'] ?? '').toString().trim();
    final surname = (data['soyadi'] ?? '').toString().trim();
    final fullName = [name, surname].where((e) => e.isNotEmpty).join(' ').trim();
    final createdAt = _parseDate(data['kayittarihi']) ?? _parseTimestamp(data['olusturulmaZamani']);
    final formattedDate = createdAt != null ? DateFormat('dd.MM.yyyy').format(createdAt) : '-';

    final gender = (data['cinsiyet'] ?? '').toString().trim();
    final phone = _resolvePhone(data);
    final address = (data['adres'] ?? '').toString().trim();
    final note = (data['aciklama'] ?? '').toString().trim();

    return _buildSectionCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;
          final theme = Theme.of(context);

          final photoAvatar = Stack(
            alignment: Alignment.center,
            children: [
              GestureDetector(
                onTap: _photoUrl == null ? null : _showPhotoDialog,
                child: Hero(
                  tag: 'danisan-photo-${widget.id}',
                  child: _buildProfileAvatar(radius: isWide ? 84 : 56),
                ),
              ),
              if (_canEdit)
                Positioned(
                  top: -6,
                  left: -6,
                  child: _buildPhotoPickerButton(),
                ),
            ],
          );

          final photoColumn = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              photoAvatar,
            ],
          );

          final infoColumn = Column(
            crossAxisAlignment: isWide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      fullName.isEmpty ? 'İsimsiz Danışan' : fullName,
                      textAlign: isWide ? TextAlign.start : TextAlign.center,
                      style: TextStyle(
                        fontSize: isWide ? 20 : 18,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_canEdit)
                    IconButton(
                      tooltip: 'Danışanı güncelle',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showEditDetailsDialog(data),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Kayıt Tarihi: $formattedDate',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 12),
              _buildInfoGrid(
                context,
                [
                  MapEntry('Cinsiyet', gender.isEmpty ? '-' : gender),
                  MapEntry('Adres', address.isEmpty ? '-' : address),
                  MapEntry('Açıklama', note.isEmpty ? '-' : note),
                ],
              ),
              const SizedBox(height: 8),
              _buildPhoneInfoRow(phone),
            ],
          );

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                photoColumn,
                const SizedBox(width: 32),
                Expanded(child: infoColumn),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  photoAvatar,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                fullName.isEmpty ? 'İsimsiz Danışan' : fullName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_canEdit)
                              IconButton(
                                tooltip: 'Danışanı güncelle',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _showEditDetailsDialog(data),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kayıt Tarihi: $formattedDate',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildPhoneInfoRow(phone),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 4),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: Text(
                  'Detaylar',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: [
                  _buildInfoGrid(
                    context,
                    [
                      MapEntry('Cinsiyet', gender.isEmpty ? '-' : gender),
                      MapEntry('Adres', address.isEmpty ? '-' : address),
                      MapEntry('Açıklama', note.isEmpty ? '-' : note),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBalanceSection(Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final balanceValue = _parsePriceValue(data['bakiye']);
    final balanceLabel = '${_formatPrice(balanceValue)} TL';
    return _buildSectionCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bakiye',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  balanceLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _openPaymentDialog(data),
                child: const Text('Ödeme'),
              ),
              OutlinedButton.icon(
                onPressed: _openPaymentHistoryDialog,
                icon: const Icon(Icons.history),
                label: const Text('Geçmiş'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openPaymentDialog(Map<String, dynamic> data) async {
    final balanceValue = _parsePriceValue(data['bakiye']);
    final amountController = TextEditingController(
      text: balanceValue > 0 ? _formatPrice(balanceValue) : '',
    );
    final noteController = TextEditingController();
    var selectedType = _PaymentType.cash;
    var isSaving = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !isSaving,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Ödeme Al'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Tutar (TL)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<_PaymentType>(
                      value: selectedType,
                      items: _PaymentType.values
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(_paymentTypeLabel(type)),
                            ),
                          )
                          .toList(),
                      onChanged: isSaving
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                selectedType = value;
                              });
                            },
                      decoration: const InputDecoration(
                        labelText: 'Ödeme Türü',
                        border: OutlineInputBorder(),
                      ),
                      isExpanded: true,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama (opsiyonel)',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final amount =
                              _parsePrice(amountController.text.trim());
                          if (amount <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Geçerli bir tutar girin.'),
                              ),
                            );
                            return;
                          }
                          setState(() {
                            isSaving = true;
                          });
                          final saved = await _savePayment(
                            data: data,
                            amount: amount,
                            type: selectedType,
                            note: noteController.text.trim(),
                          );
                          if (!mounted || !dialogContext.mounted) {
                            return;
                          }
                          setState(() {
                            isSaving = false;
                          });
                          if (saved) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Tamamlandı'),
                ),
              ],
            );
          },
        );
      },
    );

    await _disposeControllers([amountController, noteController]);

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ödeme kaydedildi.')),
      );
    }
  }

  void _openPaymentHistoryDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ödeme Geçmişi'),
          content: SizedBox(
            width: 420,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _paymentCollection.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Ödemeler yüklenemedi.');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Text('Henüz ödeme bulunmuyor.');
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final amount = _readDouble(data['amount']) ?? 0;
                    final type = _parsePaymentType(data['type']?.toString());
                    final createdAt = _formatDateTime(_readTimestamp(data['createdAt']));
                    final paidBy = (data['paidByName'] ?? '').toString().trim();
                    final receivedBy = (data['receivedByName'] ?? '').toString().trim();
                    final note = (data['note'] ?? '').toString().trim();
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withOpacity(0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _paymentTypeLabel(type),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text(
                                '${_formatPrice(amount)} TL',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          if (createdAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              createdAt,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Ödeyen: ${paidBy.isNotEmpty ? paidBy : '-'}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          Text(
                            'Alan: ${receivedBy.isNotEmpty ? receivedBy : '-'}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Açıklama: $note',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Kapat'),
            ),
          ],
        );
      },
    );
  }

  void _openManualOperationDialog() {
    _openOperationEntryDialog(title: 'İşlem Ekle', entryType: 'operation');
  }

  void _openManualSaleDialog() {
    _openOperationEntryDialog(title: 'Satış Ekle', entryType: 'sale');
  }

  Future<void> _openOperationEntryDialog({
    required String title,
    required String entryType,
  }) async {
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    if (kurumkodu.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
        );
      }
      return;
    }

    final locations = await _fetchMekanOptions(kurumkodu);
    final operations = await _fetchOperationOptions(kurumkodu);
    final users = _canEdit ? await _fetchUserOptions(kurumkodu) : <_UserOption>[];

    if (!mounted) {
      return;
    }
    if (locations.isEmpty || operations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İşlem bilgileri yüklenemedi.')),
      );
      return;
    }

    _MekanOption? selectedLocation = locations.first;
    _OperationOption? selectedOperation;
    final priceController = TextEditingController();
    final noteController = TextEditingController();
    final currentUserId = _currentUserId();
    final currentUserName = _currentUserDisplayName();
    _UserOption? selectedUser = _canEdit
        ? _findUserOption(users, id: currentUserId, name: currentUserName)
        : null;
    var isSaving = false;

    Future<void> applyDefaultUser(
      _OperationOption? operation,
      void Function(void Function()) setState,
    ) async {
      if (operation == null) {
        return;
      }
      if (operation.price > 0 && priceController.text.trim().isEmpty) {
        priceController.text = _formatPrice(operation.price);
      }
      if (!_canEdit) {
        return;
      }
      _UserOption? matchedUser;
      for (final user in users) {
        if (operation.defaultUserId != null &&
            operation.defaultUserId!.isNotEmpty &&
            user.id == operation.defaultUserId) {
          matchedUser = user;
          break;
        }
        if (operation.defaultUserName != null &&
            operation.defaultUserName!.isNotEmpty &&
            (user.shortLabel == operation.defaultUserName ||
                user.displayName == operation.defaultUserName)) {
          matchedUser = user;
          break;
        }
      }
      if (matchedUser != null) {
        setState(() {
          selectedUser = matchedUser;
        });
      }
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<_MekanOption>(
                      value: selectedLocation,
                      items: locations
                          .map(
                            (location) => DropdownMenuItem(
                              value: location,
                              child: Text(location.name),
                            ),
                          )
                          .toList(),
                      onChanged: isSaving
                          ? null
                          : (value) {
                              setState(() {
                                selectedLocation = value;
                              });
                            },
                      decoration: const InputDecoration(
                        labelText: 'Mekan',
                        border: OutlineInputBorder(),
                      ),
                      isExpanded: true,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<_OperationOption>(
                      value: selectedOperation,
                      items: operations
                          .map(
                            (operation) => DropdownMenuItem(
                              value: operation,
                              child: Text(operation.label),
                            ),
                          )
                          .toList(),
                      onChanged: isSaving
                          ? null
                          : (value) async {
                              setState(() {
                                selectedOperation = value;
                              });
                              await applyDefaultUser(value, setState);
                            },
                      decoration: const InputDecoration(
                        labelText: 'İşlem',
                        border: OutlineInputBorder(),
                      ),
                      isExpanded: true,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: priceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Ücret (TL)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_canEdit)
                      DropdownButtonFormField<_UserOption?>(
                        value: selectedUser,
                        items: [
                          const DropdownMenuItem<_UserOption?>(
                            value: null,
                            child: Text('Kullanıcı seç'),
                          ),
                          ...users.map(
                            (user) => DropdownMenuItem<_UserOption?>(
                              value: user,
                              child: Text(user.displayName),
                            ),
                          ),
                        ],
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  selectedUser = value;
                                });
                              },
                        decoration: const InputDecoration(
                          labelText: 'Kullanıcı',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                      )
                    else
                      TextFormField(
                        initialValue: currentUserName.isEmpty ? '-' : currentUserName,
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'Kullanıcı',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama (opsiyonel)',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (selectedLocation == null || selectedOperation == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Lütfen tüm alanları doldurun.'),
                              ),
                            );
                            return;
                          }
                          final price = _parsePrice(priceController.text.trim());
                          if (price <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Geçerli bir ücret girin.'),
                              ),
                            );
                            return;
                          }
                          setState(() {
                            isSaving = true;
                          });
                          final performerId = _canEdit
                              ? (selectedUser?.id ?? currentUserId)
                              : currentUserId;
                          final rawPerformerName = _canEdit
                              ? (selectedUser?.shortLabel ?? currentUserName)
                              : currentUserName;
                          final performerName = _shortenDisplayLabel(rawPerformerName);
                          final saved = await _saveManualOperation(
                            location: selectedLocation!,
                            operation: selectedOperation!,
                            price: price,
                            assignedUserId: performerId,
                            assignedUserName: performerName.isNotEmpty
                                ? performerName
                                : rawPerformerName,
                            performedById: performerId,
                            performedByName: performerName.isNotEmpty
                                ? performerName
                                : rawPerformerName,
                            note: noteController.text.trim(),
                            entryType: entryType,
                          );
                          if (!mounted || !dialogContext.mounted) {
                            return;
                          }
                          setState(() {
                            isSaving = false;
                          });
                          if (saved) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    await _disposeControllers([priceController, noteController]);

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İşlem kaydedildi.')),
      );
    }
  }

  Widget _buildReservationsSection(Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    final canAddReservation = kurumkodu.isNotEmpty;

    return _buildSectionCard(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _danisanDoc.collection('islemler').snapshots(),
        builder: (context, snapshot) {
          final completedByReservation = snapshot.hasData
              ? _extractCompletedOperationKeys(snapshot.data!.docs)
              : <String, Set<String>>{};
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rezervasyonlar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: canAddReservation ? () => _handleAddReservation(data) : null,
                    child: const Text('+ Ekle'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip:
                        _showPastReservations ? 'Geçmişi gizle' : 'Geçmişi göster',
                    icon: const Icon(Icons.history),
                    color: _showPastReservations
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    onPressed: () {
                      setState(() {
                        _showPastReservations = !_showPastReservations;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildReservationList(completedByReservation),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReservationList(
    Map<String, Set<String>> completedByReservation,
  ) {
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    if (kurumkodu.isEmpty) {
      return const Text('Rezervasyonlar yüklenemedi.');
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _reservationCollection.where('customerId', isEqualTo: widget.id).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Rezervasyonlar alınamadı.');
        }
        if (!snapshot.hasData) {
          return const LinearProgressIndicator(minHeight: 2);
        }

        final entries = snapshot.data!.docs
            .map((doc) => _ReservationEntry.fromSnapshot(doc))
            .toList()
          ..sort((a, b) {
            final first = a.date ?? DateTime(0);
            final second = b.date ?? DateTime(0);
            return second.compareTo(first);
          });

        final visibleEntries = entries
            .where((entry) {
              final isCompleted =
                  _isReservationCompleted(entry, completedByReservation);
              return _showPastReservations ? isCompleted : !isCompleted;
            })
            .toList();

        if (visibleEntries.isEmpty) {
          return Text(
            _showPastReservations
                ? 'Geçmiş rezervasyon bulunmuyor.'
                : 'Henüz rezervasyon bulunmuyor.',
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: visibleEntries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final entry = visibleEntries[index];
            return _buildReservationCard(entry, completedByReservation);
          },
        );
      },
    );
  }

  Widget _buildCompletedOperationsSection() {
    final theme = Theme.of(context);
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    if (kurumkodu.isEmpty) {
      return _buildSectionCard(
        child: Text(
          'İşlemler yüklenemedi.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'İşlemler',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.tonal(
                onPressed: _openManualOperationDialog,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('İşlem+'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _openManualSaleDialog,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Satış+'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _danisanDoc
                .collection('islemler')
                .orderBy('completedAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('İşlemler yüklenemedi.');
              }
              if (!snapshot.hasData) {
                return const LinearProgressIndicator(minHeight: 2);
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Text('Henüz işlem bulunmuyor.');
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final data = docs[index].data();
                  final operationName =
                      (data['operationName'] ?? '').toString().trim();
                  final performedBy =
                      (data['performedByName'] ?? '').toString().trim();
                  final performedByLabel = performedBy.isNotEmpty
                      ? _shortenDisplayLabel(performedBy)
                      : '';
                  final note = (data['note'] ?? '').toString().trim();
                  final price = _readDouble(data['operationPrice']);
                  final priceLabel =
                      price != null ? '${_formatPrice(price)} TL' : '-';
                  final completedAt = _formatDateTime(_readTimestamp(data['completedAt']));
                  final locationName =
                      (data['locationName'] ?? '').toString().trim();
                  final reservationDate =
                      _formatDateTime(_readTimestamp(data['reservationDate']));
                  final contextParts = <String>[
                    if (locationName.isNotEmpty) locationName,
                    if (reservationDate != null) reservationDate,
                  ];
                  return Container(
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
                                operationName.isNotEmpty
                                    ? operationName
                                    : 'İşlem',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              priceLabel,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (contextParts.isNotEmpty)
                          Text(
                            contextParts.join(' • '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'İşlemi yapan: '
                          '${performedByLabel.isNotEmpty ? performedByLabel : '-'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (note.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Açıklama: $note',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (completedAt != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Tamamlandı: $completedAt',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Map<String, Set<String>> _extractCompletedOperationKeys(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final result = <String, Set<String>>{};
    for (final doc in docs) {
      final data = doc.data();
      final reservationId = (data['reservationId'] ?? '').toString().trim();
      if (reservationId.isEmpty) {
        continue;
      }
      final operationId = (data['operationId'] ?? '').toString().trim();
      final operationName = (data['operationName'] ?? '').toString().trim();
      final keys = result.putIfAbsent(reservationId, () => <String>{});
      if (operationId.isNotEmpty) {
        keys.add('id:$operationId');
      }
      if (operationName.isNotEmpty) {
        keys.add('name:$operationName');
      }
    }
    return result;
  }

  bool _isOperationCompleted(
    _ReservationOperationData operation,
    Set<String> completedKeys,
  ) {
    final id = (operation.operationId ?? '').trim();
    if (id.isNotEmpty && completedKeys.contains('id:$id')) {
      return true;
    }
    final name = (operation.operationName ?? '').trim();
    if (name.isNotEmpty && completedKeys.contains('name:$name')) {
      return true;
    }
    return false;
  }

  bool _isReservationCompleted(
    _ReservationEntry entry,
    Map<String, Set<String>> completedByReservation,
  ) {
    if (entry.operations.isEmpty) {
      return false;
    }
    final completedKeys = completedByReservation[entry.id];
    if (completedKeys == null || completedKeys.isEmpty) {
      return false;
    }
    for (final operation in entry.operations) {
      if (!_isOperationCompleted(operation, completedKeys)) {
        return false;
      }
    }
    return true;
  }

  Widget _buildReservationCard(
    _ReservationEntry entry,
    Map<String, Set<String>> completedByReservation,
  ) {
    final theme = Theme.of(context);
    final dateLabel =
        entry.date != null ? DateFormat('dd.MM.yyyy').format(entry.date!) : null;
    final timeRange = entry.startMinutes != null && entry.endMinutes != null
        ? '${_formatMinutes(entry.startMinutes!)} - ${_formatMinutes(entry.endMinutes!)}'
        : null;
    final operations = entry.operations;
    final hasOperations = operations.isNotEmpty;
    final completedKeys = completedByReservation[entry.id] ?? <String>{};
    final showUpdated =
        entry.updatedAt != null || (entry.updatedByName?.isNotEmpty == true);
    final footerName = showUpdated ? entry.updatedByName : entry.createdByName;
    final footerDate =
        showUpdated ? _formatDateTime(entry.updatedAt) : _formatDateTime(entry.createdAt);
    final footerTitle = showUpdated ? 'Güncelleyen' : 'Oluşturan';
    final footerNameLabel =
        footerName?.isNotEmpty == true ? footerName! : 'Bilinmiyor';
    final footerDateLabel = footerDate ?? '-';
    final dateTimeLabel = [
      if (dateLabel != null) dateLabel,
      if (timeRange != null) timeRange,
    ].join(' • ');
    final locationLabel = entry.locationName?.isNotEmpty == true
        ? entry.locationName!
        : 'Mekan belirtilmedi';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    locationLabel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _openReservationUpdateForm(entry),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Güncelle'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<_ReservationMenuAction>(
                  onSelected: (value) {
                    if (value == _ReservationMenuAction.delete) {
                      _confirmDeleteReservation(entry);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _ReservationMenuAction.delete,
                      child: Text('Sil'),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.event_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    dateTimeLabel.isNotEmpty
                        ? dateTimeLabel
                        : 'Tarih ve saat belirtilmedi',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'İşlemler',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${operations.length} işlem',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (hasOperations)
              ...operations.map((operation) {
                final operationName = operation.operationName?.isNotEmpty == true
                    ? operation.operationName!
                    : 'İşlem';
                final operationPrice = operation.operationPrice != null
                    ? '${_formatPrice(operation.operationPrice!)} TL'
                    : '-';
                final assignedUserRaw =
                    operation.assignedUserName?.isNotEmpty == true
                        ? operation.assignedUserName!
                        : '';
                final assignedUser = assignedUserRaw.isNotEmpty
                    ? _shortenDisplayLabel(assignedUserRaw)
                    : 'Atanmadı';
                final note = operation.note?.trim() ?? '';
                final isCompleted = _isOperationCompleted(operation, completedKeys);
                final canExecute = _isOperationActionAllowed(operation);
                final mutedColor = theme.colorScheme.onSurfaceVariant.withOpacity(0.7);
                final textStyle = isCompleted
                    ? theme.textTheme.bodyMedium?.copyWith(color: mutedColor)
                    : theme.textTheme.bodyMedium;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? theme.colorScheme.surfaceVariant.withOpacity(0.18)
                        : theme.colorScheme.surfaceVariant.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              operationName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textStyle?.copyWith(
                                fontWeight:
                                    isCompleted ? FontWeight.w500 : FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              operationPrice,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: textStyle,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              assignedUser,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textStyle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'İşlem Yap',
                            onPressed: (!isCompleted && canExecute)
                                ? () => _openOperationExecutionDialog(entry, operation)
                                : null,
                            icon: const Icon(Icons.check_circle_outline),
                            iconSize: 20,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ],
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Açıklama: $note',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              })
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                  ),
                ),
                child: Text(
                  'İşlem bilgisi bulunamadı.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$footerTitle: $footerNameLabel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  footerDateLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _currentUserId() {
    return (user.data['uid'] ?? user.data['id'] ?? user.data['email'] ?? '')
        .toString()
        .trim();
  }

  String _currentUserShortName() {
    return (user.data['kisaad'] ?? '').toString().trim();
  }

  String _currentUserDisplayName() {
    return _resolveUserDisplayName(user.data).trim();
  }

  bool _isOperationActionAllowed(_ReservationOperationData operation) {
    if (_canEdit) {
      return true;
    }
    final assignedId = (operation.assignedUserId ?? '').trim();
    final assignedName = (operation.assignedUserName ?? '').trim();
    final currentId = _currentUserId();
    final currentShort = _currentUserShortName();
    final currentName = _currentUserDisplayName();
    if (assignedId.isNotEmpty && currentId.isNotEmpty && assignedId == currentId) {
      return true;
    }
    if (assignedName.isNotEmpty && currentShort.isNotEmpty && assignedName == currentShort) {
      return true;
    }
    if (assignedName.isNotEmpty && currentName.isNotEmpty && assignedName == currentName) {
      return true;
    }
    return false;
  }

  _UserOption? _findUserOption(
    List<_UserOption> users, {
    String? id,
    String? name,
  }) {
    final trimmedId = (id ?? '').trim();
    if (trimmedId.isNotEmpty) {
      for (final user in users) {
        if (user.id == trimmedId) {
          return user;
        }
      }
    }
    final trimmedName = (name ?? '').trim();
    if (trimmedName.isNotEmpty) {
      for (final user in users) {
        if (user.shortLabel == trimmedName || user.displayName == trimmedName) {
          return user;
        }
      }
    }
    return null;
  }

  Future<void> _openOperationExecutionDialog(
    _ReservationEntry entry,
    _ReservationOperationData operation,
  ) async {
    if (!_isOperationActionAllowed(operation)) {
      return;
    }
    final parentContext = context;
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    final isAdmin = _canEdit;
    final currentUserName = _currentUserDisplayName();
    final currentUserId = _currentUserId();
    final users = <_UserOption>[];
    if (isAdmin && kurumkodu.isNotEmpty) {
      users.addAll(await _fetchUserOptions(kurumkodu));
    }
    _UserOption? selectedUser = isAdmin
        ? _findUserOption(
              users,
              id: operation.assignedUserId,
              name: operation.assignedUserName,
            ) ??
            _findUserOption(users, id: currentUserId, name: currentUserName)
        : null;

    final priceController = TextEditingController(
      text: operation.operationPrice != null ? _formatPrice(operation.operationPrice!) : '',
    );
    final noteController = TextEditingController(text: operation.note ?? '');
    var isSaving = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final dateLabel = _formatDateTime(entry.date) ?? '-';
        final locationLabel =
            entry.locationName?.isNotEmpty == true ? entry.locationName! : '-';
        final assignedLabel = operation.assignedUserName?.isNotEmpty == true
            ? _shortenDisplayLabel(operation.assignedUserName!)
            : '-';
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('İşlem Yap'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      operation.operationName?.isNotEmpty == true
                          ? operation.operationName!
                          : 'İşlem',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text('Rezervasyon: $locationLabel • $dateLabel'),
                    const SizedBox(height: 12),
                    Text('Atanan: $assignedLabel'),
                    const SizedBox(height: 12),
                    if (isAdmin)
                      DropdownButtonFormField<_UserOption?>(
                        value: selectedUser,
                        items: [
                          const DropdownMenuItem<_UserOption?>(
                            value: null,
                            child: Text('İşlem yapan seç'),
                          ),
                          ...users.map(
                            (user) => DropdownMenuItem<_UserOption?>(
                              value: user,
                              child: Text(user.displayName),
                            ),
                          ),
                        ],
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  selectedUser = value;
                                });
                              },
                        decoration: const InputDecoration(
                          labelText: 'İşlemi yapan',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                      )
                    else
                      TextFormField(
                        initialValue: currentUserName.isEmpty ? '-' : currentUserName,
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'İşlemi yapan',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: priceController,
                      enabled: isAdmin && !isSaving,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Fiyat (TL)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteController,
                      enabled: !isSaving,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama (opsiyonel)',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final price =
                              _parsePrice(priceController.text.trim());
                          if (price <= 0) {
                            if (mounted) {
                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Geçerli bir fiyat girin.'),
                                ),
                              );
                            }
                            return;
                          }
                          setState(() {
                            isSaving = true;
                          });
                          final performerId = isAdmin
                              ? (selectedUser?.id ?? currentUserId)
                              : currentUserId;
                          final rawPerformerName = isAdmin
                              ? (selectedUser?.shortLabel ?? currentUserName)
                              : currentUserName;
                          final performerName = _shortenDisplayLabel(rawPerformerName);
                          final saved = await _completeReservationOperation(
                            entry: entry,
                            operation: operation,
                            price: price,
                            performedById: performerId,
                            performedByName:
                                performerName.isNotEmpty ? performerName : rawPerformerName,
                            note: noteController.text.trim(),
                          );
                          if (!mounted || !dialogContext.mounted) {
                            return;
                          }
                          if (saved) {
                            Navigator.of(dialogContext).pop(true);
                            return;
                          }
                          setState(() {
                            isSaving = false;
                          });
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Tamamladı'),
                ),
              ],
            );
          },
        );
      },
    );

    await _disposeControllers([priceController, noteController]);

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İşlem kaydedildi.')),
      );
    }
  }

  Future<bool> _completeReservationOperation({
    required _ReservationEntry entry,
    required _ReservationOperationData operation,
    required double price,
    required String performedById,
    required String performedByName,
    required String note,
  }) async {
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    if (kurumkodu.isEmpty) {
      return false;
    }

    final operationsRef = _danisanDoc.collection('islemler').doc();
    final payload = <String, dynamic>{
      'reservationId': entry.id,
      'locationName': entry.locationName,
      'operationId': operation.operationId,
      'operationName': operation.operationName,
      'operationCategoryId': operation.operationCategoryId,
      'operationCategoryName': operation.operationCategoryName,
      'operationPrice': price,
      'assignedUserId': operation.assignedUserId,
      'assignedUserName': operation.assignedUserName,
      'performedById': performedById,
      'performedByName': performedByName,
      'note': note,
      'entryType': 'reservation',
      'completedAt': FieldValue.serverTimestamp(),
    };
    if (entry.date != null) {
      payload['reservationDate'] = Timestamp.fromDate(entry.date!);
    }

    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.set(operationsRef, payload);
      batch.update(_danisanDoc, {
        'bakiye': FieldValue.increment(price),
      });
      await batch.commit();
      if (mounted && _danisanData != null) {
        setState(() {
          final currentBalance = _parsePriceValue(_danisanData?['bakiye']);
          _danisanData = {
            ...?_danisanData,
            'bakiye': currentBalance + price,
          };
        });
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem kaydedilemedi: $error')),
        );
      }
      return false;
    }
  }

  Future<void> _handleAddReservation(Map<String, dynamic> data) async {
    final selection = await _openReservationTable();
    if (!mounted || selection == null) {
      return;
    }
    await _showReservationForm(selection, data);
  }

  Future<_ReservationSelection?> _openReservationTable() async {
    final parentContext = context;
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    if (kurumkodu.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
        );
      }
      return null;
    }

    final locations = await _fetchMekanOptions(kurumkodu);
    if (!mounted) {
      return null;
    }
    if (locations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rezervasyon için mekan bulunamadı.')),
      );
      return null;
    }

    var selectedDay = DateUtils.dateOnly(DateTime.now());
    String? selectedLocationId;
    _MekanOption? selectedLocation;
    final selectedSlots = <int>{};

    return showDialog<_ReservationSelection>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            final dayStart = DateTime(
              selectedDay.year,
              selectedDay.month,
              selectedDay.day,
            );
            final dayEnd = dayStart.add(const Duration(days: 1));
            final stream = _reservationCollection
                .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
                .where('date', isLessThan: Timestamp.fromDate(dayEnd))
                .snapshots();

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.95,
                height: MediaQuery.of(context).size.height * 0.85,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Rezervasyon Tablosu',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                            tooltip: 'Kapat',
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: stream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const Center(
                              child: Text('Rezervasyonlar yüklenemedi.'),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final reservations = snapshot.data!.docs
                              .map((doc) => _ReservationSlot.fromSnapshot(doc))
                              .toList();

                          _ReservationSelection? selection;
                          if (selectedLocation != null && selectedSlots.isNotEmpty) {
                            final sortedSlots = selectedSlots.toList()..sort();
                            selection = _ReservationSelection(
                              day: selectedDay,
                              location: selectedLocation!,
                              startMinutes: sortedSlots.first,
                              endMinutes: sortedSlots.last + _slotDurationMinutes,
                            );
                          }

                          return Column(
                            children: [
                              Expanded(
                                child: _ReservationTable(
                                  selectedDay: selectedDay,
                                  locations: locations,
                                  reservations: reservations,
                                  selectedLocationId: selectedLocationId,
                                  selectedSlots: selectedSlots,
                                  onDayChanged: (day) {
                                    setState(() {
                                      selectedDay = DateUtils.dateOnly(day);
                                      selectedLocationId = null;
                                      selectedLocation = null;
                                      selectedSlots.clear();
                                    });
                                  },
                                  onSlotTapped: (location, startMinutes) {
                                    setState(() {
                                      if (selectedLocationId != location.id) {
                                        selectedLocationId = location.id;
                                        selectedLocation = location;
                                        selectedSlots
                                          ..clear()
                                          ..add(startMinutes);
                                        return;
                                      }
                                      if (selectedSlots.contains(startMinutes)) {
                                        selectedSlots.remove(startMinutes);
                                        if (selectedSlots.isEmpty) {
                                          selectedLocationId = null;
                                          selectedLocation = null;
                                        }
                                      } else {
                                        selectedSlots.add(startMinutes);
                                      }
                                    });
                                  },
                                  onReservationTap: (reservation) {
                                    Navigator.of(dialogContext).pop();
                                    if (!mounted) {
                                      return;
                                    }
                                    final customerId = reservation.customerId;
                                    if (customerId.isEmpty) {
                                      ScaffoldMessenger.of(parentContext).showSnackBar(
                                        const SnackBar(
                                          content: Text('Müşteri bilgisi bulunamadı.'),
                                        ),
                                      );
                                      return;
                                    }
                                    Navigator.of(parentContext).push(
                                      MaterialPageRoute(
                                        builder: (_) => DanisanProfil(id: customerId),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        selection == null
                                            ? 'Rezervasyon için bir hücre seçin.'
                                            : '${selection.location.name} • '
                                                '${DateFormat('dd.MM.yyyy').format(selection.day)} • '
                                                '${_formatMinutes(selection.startMinutes)} - '
                                                '${_formatMinutes(selection.endMinutes)}',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    TextButton(
                                      onPressed: selectedSlots.isEmpty
                                          ? null
                                          : () {
                                              setState(() {
                                                selectedLocationId = null;
                                                selectedLocation = null;
                                                selectedSlots.clear();
                                              });
                                            },
                                      child: const Text('Seçimi temizle'),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: selection == null
                                          ? null
                                          : () => Navigator.of(context).pop(selection),
                                      child: const Text('Devam Et'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showReservationForm(
    _ReservationSelection selection,
    Map<String, dynamic> data,
  ) async {
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    if (kurumkodu.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
        );
      }
      return;
    }
    _logReservation('open create form', {
      'day': selection.day.toIso8601String(),
      'startMinutes': selection.startMinutes,
      'endMinutes': selection.endMinutes,
      'locationId': selection.location.id,
    });

    final operations = await _fetchOperationOptions(kurumkodu);
    final users = await _fetchUserOptions(kurumkodu);

    if (!mounted) {
      return;
    }
    if (operations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İşlem bulunamadı. Önce işlem ekleyin.')),
      );
      return;
    }

    final operationEntries = <_ReservationOperationDraft>[
      _ReservationOperationDraft(),
    ];
    final removedEntries = <_ReservationOperationDraft>[];
    var isSaving = false;

    Future<void> applyDefaultUser(
      _OperationOption? operation,
      _ReservationOperationDraft entry,
      void Function(void Function()) setState,
    ) async {
      if (operation == null) {
        setState(() {
          entry.assignedUser = null;
        });
        return;
      }
      _UserOption? matchedUser;
      for (final user in users) {
        if (operation.defaultUserId != null && operation.defaultUserId!.isNotEmpty) {
          if (user.id == operation.defaultUserId) {
            matchedUser = user;
            break;
          }
        } else if (operation.defaultUserName != null &&
            operation.defaultUserName!.isNotEmpty) {
          if (user.shortLabel == operation.defaultUserName ||
              user.displayName == operation.defaultUserName) {
            matchedUser = user;
            break;
          }
        }
      }
      setState(() {
        entry.assignedUser = matchedUser;
        if (operation.price > 0) {
          entry.priceController.text = _formatPrice(operation.price);
        }
      });
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final dateLabel = DateFormat('dd.MM.yyyy').format(selection.day);
            final timeLabel =
                '${_formatMinutes(selection.startMinutes)} - ${_formatMinutes(selection.endMinutes)}';
            return AlertDialog(
              title: const Text('Rezervasyon Kartı'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tarih: $dateLabel',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text('Saat: $timeLabel'),
                    const SizedBox(height: 4),
                    Text('Mekan: ${selection.location.name}'),
                    const SizedBox(height: 16),
                    ...operationEntries.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          key: item.key,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'İşlem ${index + 1}',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (operationEntries.length > 1)
                                    IconButton(
                                      tooltip: 'İşlemi kaldır',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: isSaving
                                          ? null
                                          : () {
                                              setState(() {
                                        final removed = operationEntries.removeAt(index);
                                        removedEntries.add(removed);
                                              });
                                            },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<_OperationOption>(
                                value: item.operation,
                                items: operations
                                    .map(
                                      (operation) => DropdownMenuItem(
                                        value: operation,
                                        child: Text(operation.label),
                                      ),
                                    )
                                    .toList(),
                                onChanged: isSaving
                                    ? null
                                    : (value) async {
                                        setState(() {
                                          item.operation = value;
                                        });
                                        await applyDefaultUser(value, item, setState);
                                      },
                                decoration: const InputDecoration(
                                  labelText: 'İşlem',
                                  border: OutlineInputBorder(),
                                ),
                                isExpanded: true,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: item.priceController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'İşlem Ücreti (TL)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<_UserOption?>(
                                value: item.assignedUser,
                                items: [
                                  const DropdownMenuItem<_UserOption?>(
                                    value: null,
                                    child: Text('Çalışan atanmasın'),
                                  ),
                                  ...users.map(
                                    (user) => DropdownMenuItem<_UserOption?>(
                                      value: user,
                                      child: Text(user.displayName),
                                    ),
                                  ),
                                ],
                                onChanged: isSaving
                                    ? null
                                    : (value) {
                                        setState(() {
                                          item.assignedUser = value;
                                        });
                                      },
                                decoration: const InputDecoration(
                                  labelText: 'Çalışan (opsiyonel)',
                                  border: OutlineInputBorder(),
                                ),
                                isExpanded: true,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: item.noteController,
                                decoration: const InputDecoration(
                                  labelText: 'Açıklama (opsiyonel)',
                                  border: OutlineInputBorder(),
                                ),
                                minLines: 2,
                                maxLines: 3,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: isSaving
                            ? null
                            : () {
                                setState(() {
                                  operationEntries.add(_ReservationOperationDraft());
                                });
                              },
                        icon: const Icon(Icons.add),
                        label: const Text('İşlem Ekle'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          _logReservation('create save tapped', {
                            'operationsCount': operationEntries.length,
                          });
                          final operationsToSave = <_ReservationOperationData>[];
                          for (var index = 0; index < operationEntries.length; index += 1) {
                            final entry = operationEntries[index];
                            if (entry.operation == null) {
                              _logReservation('create validation failed: operation missing', {
                                'index': index,
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Lütfen işlem seçin.')),
                              );
                              return;
                            }
                            final price = _parsePrice(entry.priceController.text.trim());
                            if (price <= 0) {
                              _logReservation('create validation failed: invalid price', {
                                'index': index,
                                'rawPrice': entry.priceController.text.trim(),
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Geçerli bir ücret girin.')),
                              );
                              return;
                            }
                            operationsToSave.add(
                              _ReservationOperationData(
                                operationId: entry.operation!.id,
                                operationName: entry.operation!.name,
                                operationCategoryId: entry.operation!.categoryId,
                                operationCategoryName: entry.operation!.categoryName,
                                operationPrice: price,
                                assignedUserId: entry.assignedUser?.id,
                                assignedUserName: entry.assignedUser?.shortLabel,
                                note: entry.noteController.text.trim(),
                              ),
                            );
                          }
                          setState(() {
                            isSaving = true;
                          });
                          _logReservation('create saving', {
                            'operationsCount': operationsToSave.length,
                          });
                          final saved = await _saveReservation(
                            selection: selection,
                            studentData: data,
                            operations: operationsToSave,
                          );
                          if (!mounted || !dialogContext.mounted) {
                            return;
                          }
                          setState(() {
                            isSaving = false;
                          });
                          _logReservation('create save result', {'saved': saved});
                          if (saved) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    await _disposeReservationDrafts(operationEntries, removedEntries);

    if (result == true) {
      return;
    }
  }

  Future<void> _confirmDeleteReservation(_ReservationEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rezervasyon Silinsin mi?'),
        content: const Text('Bu rezervasyonu silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      await _reservationCollection.doc(entry.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rezervasyon silindi.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rezervasyon silinemedi: $error')),
        );
      }
    }
  }

  Future<void> _openReservationUpdateForm(_ReservationEntry entry) async {
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    if (kurumkodu.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
        );
      }
      return;
    }

    final locations = await _fetchMekanOptions(kurumkodu);
    final operations = await _fetchOperationOptions(kurumkodu);
    final users = await _fetchUserOptions(kurumkodu);

    if (!mounted) {
      return;
    }
    if (locations.isEmpty || operations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rezervasyon bilgileri yüklenemedi.')),
      );
      return;
    }

    _MekanOption? selectedLocation;
    if (entry.locationId?.isNotEmpty == true) {
      for (final location in locations) {
        if (location.id == entry.locationId) {
          selectedLocation = location;
          break;
        }
      }
    }
    selectedLocation ??= locations.firstWhere(
      (location) => location.name == entry.locationName,
      orElse: () => locations.first,
    );

    final operationOptions = [...operations];
    final initialOperations = entry.operations.isNotEmpty
        ? entry.operations
        : (entry.operationName?.isNotEmpty == true
            ? [
                _ReservationOperationData(
                  operationId: entry.operationId,
                  operationName: entry.operationName,
                  operationCategoryId: entry.operationCategoryId,
                  operationCategoryName: entry.operationCategoryName,
                  operationPrice: entry.operationPrice,
                  assignedUserId: entry.assignedUserId,
                  assignedUserName: entry.assignedUserName,
                  note: null,
                ),
              ]
            : <_ReservationOperationData>[]);

    _OperationOption? resolveOperationOption(
      _ReservationOperationData data,
      int index,
    ) {
      if (data.operationId != null && data.operationId!.isNotEmpty) {
        for (final option in operationOptions) {
          if (option.id == data.operationId) {
            return option;
          }
        }
      }
      if (data.operationName != null && data.operationName!.isNotEmpty) {
        final fallback = _OperationOption(
          id: data.operationId?.isNotEmpty == true
              ? data.operationId!
              : 'custom-$index',
          name: data.operationName!,
          categoryId: data.operationCategoryId ?? '',
          categoryName: data.operationCategoryName ?? '',
          price: data.operationPrice ?? 0,
        );
        operationOptions.add(fallback);
        return fallback;
      }
      return null;
    }

    _UserOption? resolveUserOption(_ReservationOperationData data) {
      if (data.assignedUserId != null && data.assignedUserId!.isNotEmpty) {
        for (final user in users) {
          if (user.id == data.assignedUserId) {
            return user;
          }
        }
      }
      if (data.assignedUserName != null && data.assignedUserName!.isNotEmpty) {
        for (final user in users) {
          if (user.shortLabel == data.assignedUserName ||
              user.displayName == data.assignedUserName) {
            return user;
          }
        }
      }
      return null;
    }

    final operationEntries = <_ReservationOperationDraft>[];
    final removedEntries = <_ReservationOperationDraft>[];
    for (var index = 0; index < initialOperations.length; index += 1) {
      final data = initialOperations[index];
      final resolvedOperation = resolveOperationOption(data, index);
      final resolvedUser = resolveUserOption(data);
      operationEntries.add(
        _ReservationOperationDraft(
          operation: resolvedOperation,
          assignedUser: resolvedUser,
          priceController: TextEditingController(
            text: data.operationPrice != null
                ? _formatPrice(data.operationPrice!)
                : (resolvedOperation != null && resolvedOperation.price > 0
                    ? _formatPrice(resolvedOperation.price)
                    : ''),
          ),
          noteController: TextEditingController(text: data.note ?? ''),
        ),
      );
    }
    if (operationEntries.isEmpty) {
      operationEntries.add(_ReservationOperationDraft());
    }

    var selectedDate = DateUtils.dateOnly(entry.date ?? DateTime.now());
    var startMinutes = entry.startMinutes ?? 9 * 60;
    var endMinutes = entry.endMinutes ?? startMinutes + _slotDurationMinutes;
    var startTime = TimeOfDay(
      hour: startMinutes ~/ 60,
      minute: startMinutes % 60,
    );
    var endTime = TimeOfDay(
      hour: endMinutes ~/ 60,
      minute: endMinutes % 60,
    );
    var isSaving = false;

    Future<void> applyDefaultUser(
      _OperationOption? operation,
      _ReservationOperationDraft entry,
      void Function(void Function()) setState,
    ) async {
      if (operation == null) {
        setState(() {
          entry.assignedUser = null;
        });
        return;
      }
      _UserOption? matchedUser;
      for (final user in users) {
        if (operation.defaultUserId != null && operation.defaultUserId!.isNotEmpty) {
          if (user.id == operation.defaultUserId) {
            matchedUser = user;
            break;
          }
        } else if (operation.defaultUserName != null &&
            operation.defaultUserName!.isNotEmpty) {
          if (user.shortLabel == operation.defaultUserName ||
              user.displayName == operation.defaultUserName) {
            matchedUser = user;
            break;
          }
        }
      }
      setState(() {
        entry.assignedUser = matchedUser;
        if (operation.price > 0) {
          entry.priceController.text = _formatPrice(operation.price);
        }
      });
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Rezervasyonu Güncelle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            DateFormat('dd.MM.yyyy').format(selectedDate),
                          ),
                        ),
                        TextButton(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: selectedDate,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      selectedDate = DateUtils.dateOnly(picked);
                                    });
                                  }
                                },
                          child: const Text('Tarih seç'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.schedule),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Başlangıç: ${_formatTimeLabel(startTime)}',
                          ),
                        ),
                        TextButton(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: startTime,
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      startTime = picked;
                                    });
                                  }
                                },
                          child: const Text('Saat seç'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.timelapse_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bitiş: ${_formatTimeLabel(endTime)}',
                          ),
                        ),
                        TextButton(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: endTime,
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      endTime = picked;
                                    });
                                  }
                                },
                          child: const Text('Saat seç'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<_MekanOption>(
                      value: selectedLocation,
                      items: locations
                          .map(
                            (location) => DropdownMenuItem(
                              value: location,
                              child: Text(location.name),
                            ),
                          )
                          .toList(),
                      onChanged: isSaving
                          ? null
                          : (value) {
                              setState(() {
                                selectedLocation = value;
                              });
                            },
                      decoration: const InputDecoration(
                        labelText: 'Mekan',
                        border: OutlineInputBorder(),
                      ),
                      isExpanded: true,
                    ),
                    const SizedBox(height: 12),
                    ...operationEntries.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          key: item.key,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'İşlem ${index + 1}',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (operationEntries.length > 1)
                                    IconButton(
                                      tooltip: 'İşlemi kaldır',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: isSaving
                                          ? null
                                          : () {
                                              setState(() {
                                                final removed = operationEntries.removeAt(index);
                                                removedEntries.add(removed);
                                              });
                                            },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<_OperationOption>(
                                value: item.operation,
                                items: operationOptions
                                    .map(
                                      (operation) => DropdownMenuItem(
                                        value: operation,
                                        child: Text(operation.label),
                                      ),
                                    )
                                    .toList(),
                                onChanged: isSaving
                                    ? null
                                    : (value) async {
                                        setState(() {
                                          item.operation = value;
                                        });
                                        await applyDefaultUser(value, item, setState);
                                      },
                                decoration: const InputDecoration(
                                  labelText: 'İşlem',
                                  border: OutlineInputBorder(),
                                ),
                                isExpanded: true,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: item.priceController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'İşlem Ücreti (TL)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<_UserOption?>(
                                value: item.assignedUser,
                                items: [
                                  const DropdownMenuItem<_UserOption?>(
                                    value: null,
                                    child: Text('Çalışan atanmasın'),
                                  ),
                                  ...users.map(
                                    (user) => DropdownMenuItem<_UserOption?>(
                                      value: user,
                                      child: Text(user.displayName),
                                    ),
                                  ),
                                ],
                                onChanged: isSaving
                                    ? null
                                    : (value) {
                                        setState(() {
                                          item.assignedUser = value;
                                        });
                                      },
                                decoration: const InputDecoration(
                                  labelText: 'Çalışan (opsiyonel)',
                                  border: OutlineInputBorder(),
                                ),
                                isExpanded: true,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: item.noteController,
                                decoration: const InputDecoration(
                                  labelText: 'Açıklama (opsiyonel)',
                                  border: OutlineInputBorder(),
                                ),
                                minLines: 2,
                                maxLines: 3,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: isSaving
                            ? null
                            : () {
                                setState(() {
                                  operationEntries.add(_ReservationOperationDraft());
                                });
                              },
                        icon: const Icon(Icons.add),
                        label: const Text('İşlem Ekle'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (selectedLocation == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Lütfen tüm alanları doldurun.'),
                              ),
                            );
                            return;
                          }
                          final startValue = startTime.hour * 60 + startTime.minute;
                          final endValue = endTime.hour * 60 + endTime.minute;
                          if (endValue <= startValue) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Bitiş saati başlangıçtan sonra olmalı.'),
                              ),
                            );
                            return;
                          }
                          final operationsToSave = <_ReservationOperationData>[];
                          for (final entry in operationEntries) {
                            if (entry.operation == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Lütfen işlem seçin.')),
                              );
                              return;
                            }
                            final opPrice = _parsePrice(entry.priceController.text.trim());
                            if (opPrice <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Geçerli bir ücret girin.')),
                              );
                              return;
                            }
                            operationsToSave.add(
                              _ReservationOperationData(
                                operationId: entry.operation!.id,
                                operationName: entry.operation!.name,
                                operationCategoryId: entry.operation!.categoryId,
                                operationCategoryName: entry.operation!.categoryName,
                                operationPrice: opPrice,
                                assignedUserId: entry.assignedUser?.id,
                                assignedUserName: entry.assignedUser?.shortLabel,
                                note: entry.noteController.text.trim(),
                              ),
                            );
                          }
                          setState(() {
                            isSaving = true;
                          });
                          final saved = await _updateReservation(
                            entry: entry,
                            date: selectedDate,
                            startMinutes: startValue,
                            endMinutes: endValue,
                            location: selectedLocation!,
                            operations: operationsToSave,
                          );
                          if (!mounted || !dialogContext.mounted) {
                            return;
                          }
                          setState(() {
                            isSaving = false;
                          });
                          if (saved) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    await _disposeReservationDrafts(operationEntries, removedEntries);

    if (result == true) {
      return;
    }
  }

  Future<bool> _saveReservation({
    required _ReservationSelection selection,
    required Map<String, dynamic> studentData,
    required List<_ReservationOperationData> operations,
  }) async {
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    if (kurumkodu.isEmpty) {
      _logReservation('save aborted: empty kurumkodu');
      return false;
    }

    _logReservation('save start', {
      'customerId': widget.id,
      'operationsCount': operations.length,
      'locationId': selection.location.id,
      'startMinutes': selection.startMinutes,
      'endMinutes': selection.endMinutes,
    });

    final name = (studentData['adi'] ?? '').toString().trim();
    final surname = (studentData['soyadi'] ?? '').toString().trim();
    final customerName =
        [name, surname].where((part) => part.isNotEmpty).join(' ').trim();
    final customerShortName = _buildShortName(name, surname);

    final startDateTime =
        _buildDateTimeFromMinutes(selection.day, selection.startMinutes);

    final createdByName = _resolveUserDisplayName(user.data);
    final createdById = (user.data['email'] ?? user.data['uid'] ?? '').toString();

    final primaryOperation = operations.first;
    final assignedUserColor = _resolveUserColorValue(primaryOperation.assignedUserId);
    final payload = <String, dynamic>{
      'customerId': widget.id,
      'customerName': customerName,
      'customerShortName': customerShortName,
      'locationId': selection.location.id,
      'locationName': selection.location.name,
      'date': Timestamp.fromDate(startDateTime),
      'startMinutes': selection.startMinutes,
      'endMinutes': selection.endMinutes,
      'operationId': primaryOperation.operationId,
      'operationName': primaryOperation.operationName,
      'operationCategoryId': primaryOperation.operationCategoryId,
      'operationCategoryName': primaryOperation.operationCategoryName,
      'operationPrice': primaryOperation.operationPrice,
      'assignedUserId': primaryOperation.assignedUserId,
      'assignedUserName': primaryOperation.assignedUserName,
      'assignedUserColor': assignedUserColor,
      'operations': operations.map((entry) => entry.toMap()).toList(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdById': createdById,
      'createdByName': createdByName,
    };

    try {
      final docRef = await _reservationCollection.add(payload);
      _logReservation('save success', {'docId': docRef.id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rezervasyon kaydedildi.')),
        );
      }
      return true;
    } catch (error, stackTrace) {
      _logReservation('save failed', {
        'error': error.toString(),
        'stack': stackTrace.toString(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rezervasyon kaydedilemedi: $error')),
        );
      }
      return false;
    }
  }

  Future<bool> _savePayment({
    required Map<String, dynamic> data,
    required double amount,
    required _PaymentType type,
    required String note,
  }) async {
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    if (kurumkodu.isEmpty) {
      return false;
    }

    final name = (data['adi'] ?? '').toString().trim();
    final surname = (data['soyadi'] ?? '').toString().trim();
    final paidByName = [name, surname].where((part) => part.isNotEmpty).join(' ').trim();
    final receivedByName = _resolveUserDisplayName(user.data).trim();
    final receivedById = _currentUserId();

    final payload = <String, dynamic>{
      'amount': amount,
      'type': type.name,
      'note': note,
      'paidById': widget.id,
      'paidByName': paidByName,
      'receivedById': receivedById,
      'receivedByName': receivedByName,
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      final paymentRef = _paymentCollection.doc();
      final batch = FirebaseFirestore.instance.batch();
      batch.set(paymentRef, payload);
      batch.update(_danisanDoc, {
        'bakiye': FieldValue.increment(-amount),
      });
      await batch.commit();
      if (mounted && _danisanData != null) {
        setState(() {
          final currentBalance = _parsePriceValue(_danisanData?['bakiye']);
          _danisanData = {
            ...?_danisanData,
            'bakiye': currentBalance - amount,
          };
        });
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ödeme kaydedilemedi: $error')),
        );
      }
      return false;
    }
  }

  Future<bool> _saveManualOperation({
    required _MekanOption location,
    required _OperationOption operation,
    required double price,
    required String assignedUserId,
    required String assignedUserName,
    required String performedById,
    required String performedByName,
    required String note,
    required String entryType,
  }) async {
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    if (kurumkodu.isEmpty) {
      return false;
    }

    final operationsRef = _danisanDoc.collection('islemler').doc();
    final payload = <String, dynamic>{
      'locationId': location.id,
      'locationName': location.name,
      'operationId': operation.id,
      'operationName': operation.name,
      'operationCategoryId': operation.categoryId,
      'operationCategoryName': operation.categoryName,
      'operationPrice': price,
      'assignedUserId': assignedUserId,
      'assignedUserName': assignedUserName,
      'performedById': performedById,
      'performedByName': performedByName,
      'note': note,
      'entryType': entryType,
      'completedAt': FieldValue.serverTimestamp(),
    };

    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.set(operationsRef, payload);
      batch.update(_danisanDoc, {
        'bakiye': FieldValue.increment(price),
      });
      await batch.commit();
      if (mounted && _danisanData != null) {
        setState(() {
          final currentBalance = _parsePriceValue(_danisanData?['bakiye']);
          _danisanData = {
            ...?_danisanData,
            'bakiye': currentBalance + price,
          };
        });
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem kaydedilemedi: $error')),
        );
      }
      return false;
    }
  }

  Future<bool> _updateReservation({
    required _ReservationEntry entry,
    required DateTime date,
    required int startMinutes,
    required int endMinutes,
    required _MekanOption location,
    required List<_ReservationOperationData> operations,
  }) async {
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    if (kurumkodu.isEmpty) {
      return false;
    }

    final startDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      startMinutes ~/ 60,
      startMinutes % 60,
    );

    final updatedByName = _resolveUserDisplayName(user.data);
    final updatedById = (user.data['email'] ?? user.data['uid'] ?? '').toString();

    final primaryOperation = operations.first;
    final assignedUserColor = _resolveUserColorValue(primaryOperation.assignedUserId);
    final payload = <String, dynamic>{
      'locationId': location.id,
      'locationName': location.name,
      'date': Timestamp.fromDate(startDateTime),
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
      'operationId': primaryOperation.operationId,
      'operationName': primaryOperation.operationName,
      'operationCategoryId': primaryOperation.operationCategoryId,
      'operationCategoryName': primaryOperation.operationCategoryName,
      'operationPrice': primaryOperation.operationPrice,
      'assignedUserId': primaryOperation.assignedUserId,
      'assignedUserName': primaryOperation.assignedUserName,
      'assignedUserColor': assignedUserColor,
      'operations': operations.map((op) => op.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedById': updatedById,
      'updatedByName': updatedByName,
    };

    try {
      await _reservationCollection.doc(entry.id).set(payload, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rezervasyon güncellendi.')),
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rezervasyon güncellenemedi: $error')),
        );
      }
      return false;
    }
  }

  Future<List<_MekanOption>> _fetchMekanOptions(String kurumkodu) async {
    if (kurumkodu.isEmpty) {
      return [];
    }
    final snapshot = await _mekanCollection.get();
    final mekanlar = snapshot.docs
        .map((doc) {
          final data = doc.data();
          final name = (data['adi'] ?? '').toString().trim();
          final sequence = _parseSequenceNo(data['siraNo']);
          return _MekanOption(
            id: doc.id,
            name: name,
            sequence: sequence,
          );
        })
        .where((mekan) => mekan.name.isNotEmpty)
        .toList()
      ..sort((a, b) {
        final firstOrder = a.sequence > 0 ? a.sequence : 1 << 30;
        final secondOrder = b.sequence > 0 ? b.sequence : 1 << 30;
        if (firstOrder != secondOrder) {
          return firstOrder.compareTo(secondOrder);
        }
        return a.name.compareTo(b.name);
      });

    return mekanlar;
  }

  Future<List<_OperationOption>> _fetchOperationOptions(String kurumkodu) async {
    if (kurumkodu.isEmpty) {
      return [];
    }
    final categoriesSnapshot = await _operationCategoryCollection.get();
    final options = <_OperationOption>[];

    for (final categoryDoc in categoriesSnapshot.docs) {
      final categoryData = categoryDoc.data();
      final categoryName = (categoryData['adi'] ?? '').toString().trim();
      final operationsSnapshot =
          await _operationCategoryCollection.doc(categoryDoc.id).collection('islemler').get();

      for (final operationDoc in operationsSnapshot.docs) {
        final data = operationDoc.data();
        final name = (data['adi'] ?? '').toString().trim();
        if (name.isEmpty) {
          continue;
        }
        final price = _parsePriceValue(data['fiyat']);
        final defaultUserId = (data['defaultUserId'] ?? '').toString().trim();
        final defaultUserName =
            (data['defaultUserName'] ?? '').toString().trim();
        options.add(
          _OperationOption(
            id: operationDoc.id,
            name: name,
            categoryId: categoryDoc.id,
            categoryName: categoryName,
            price: price,
            defaultUserId: defaultUserId.isEmpty ? null : defaultUserId,
            defaultUserName: defaultUserName.isEmpty ? null : defaultUserName,
          ),
        );
      }
    }

    options.sort((a, b) => a.label.compareTo(b.label));
    return options;
  }

  Future<List<_UserOption>> _fetchUserOptions(String kurumkodu) async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('kullanicilar')
        .where('kurumkodu', isEqualTo: kurumkodu)
        .get();

    final users = querySnapshot.docs.map((doc) {
      final data = doc.data();
      final firstName = (data['adi'] ?? '').toString().trim();
      final lastName = (data['soyadi'] ?? '').toString().trim();
      final shortName = (data['kisaad'] ?? '').toString().trim();
      final fullName = [firstName, lastName].where((part) => part.isNotEmpty).join(' ');
      final displayName = shortName.isNotEmpty && fullName.isNotEmpty
          ? '$shortName • $fullName'
          : (shortName.isNotEmpty ? shortName : fullName);
      final safeDisplayName = displayName.isEmpty ? 'İsimsiz Kullanıcı' : displayName;
      return _UserOption(
        id: doc.id,
        displayName: safeDisplayName,
        shortLabel: shortName.isNotEmpty ? shortName : safeDisplayName,
      );
    }).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return users;
  }

  Future<void> _showEditDetailsDialog(Map<String, dynamic> data) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: (data['adi'] ?? '').toString().trim());
    final surnameController = TextEditingController(text: (data['soyadi'] ?? '').toString().trim());
    final phoneController = TextEditingController(text: _resolvePhone(data));
    final addressController = TextEditingController(text: (data['adres'] ?? '').toString().trim());
    final noteController = TextEditingController(text: (data['aciklama'] ?? '').toString().trim());
    String? genderValue = (data['cinsiyet'] ?? '').toString().trim().isEmpty
        ? null
        : (data['cinsiyet'] ?? '').toString().trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Danışanı Güncelle'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Adı'),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => (value ?? '').trim().isEmpty ? 'Adı zorunlu' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: surnameController,
                  decoration: const InputDecoration(labelText: 'Soyadı'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: genderValue,
                  decoration: const InputDecoration(labelText: 'Cinsiyet'),
                  items: const [
                    DropdownMenuItem(value: 'KADIN', child: Text('Kadın')),
                    DropdownMenuItem(value: 'ERKEK', child: Text('Erkek')),
                    DropdownMenuItem(value: 'BELİRTİLMEDİ', child: Text('Belirtilmedi')),
                  ],
                  onChanged: (value) => genderValue = value,
                  isExpanded: true,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'Telefon'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Adres'),
                  minLines: 2,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: noteController,
                  decoration: const InputDecoration(labelText: 'Açıklama'),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );

    if (result != true) {
      return;
    }

    final updatedPayload = <String, dynamic>{
      'adi': nameController.text.trim().toUpperCase(),
      'soyadi': surnameController.text.trim().toUpperCase(),
      'adres': addressController.text.trim(),
      'aciklama': noteController.text.trim(),
    };
    final normalizedPhone = normalizePhone(phoneController.text.trim());
    updatedPayload['telefon'] = normalizedPhone;
    if (genderValue != null && genderValue!.isNotEmpty) {
      updatedPayload['cinsiyet'] = genderValue;
    }

    await _danisanDoc.update(updatedPayload);
    if (!mounted) return;
    setState(() {
      _danisanData = {
        ...?_danisanData,
        ...updatedPayload,
      };
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Danışan bilgileri güncellendi.')),
    );
  }

  Widget _buildContactActions(String phone) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Ara',
          onPressed: phone.isEmpty ? null : () => _launchExternalUrl('tel:$phone'),
          icon: const Icon(Icons.call, color: Colors.green),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'WhatsApp',
          onPressed: phone.isEmpty
              ? null
              : () => _launchExternalUrl(
                    'https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}',
                  ),
          icon: Image.asset(
            'assets/icons/whatsapp.png',
            width: 24,
            height: 24,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileAvatar({required double radius}) {
    final diameter = radius * 2;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey.shade200,
            border: Border.all(color: Colors.black.withOpacity(0.04)),
          ),
          child: ClipOval(
            child: SizedBox(
              width: diameter,
              height: diameter,
              child: _buildPhotoContent(fit: BoxFit.cover),
            ),
          ),
        ),
        if (_photoLoading)
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black26,
              ),
              child: const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPhotoContent({BoxFit fit = BoxFit.cover}) {
    if (_photoUrl == null) {
      return _buildPhotoPlaceholder();
    }
    return Image.network(
      _photoUrl!,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        final progress = loadingProgress.expectedTotalBytes != null
            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
            : null;
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildPhotoPlaceholder(),
            Center(child: CircularProgressIndicator(value: progress)),
          ],
        );
      },
      errorBuilder: (_, __, ___) => _buildPhotoPlaceholder(),
    );
  }

  Widget _buildPhotoPlaceholder() {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceVariant.withOpacity(
        theme.brightness == Brightness.dark ? 0.3 : 0.15,
      ),
      child: Center(
        child: Icon(
          Icons.person_outline,
          size: 48,
          color: theme.colorScheme.onSurface.withOpacity(0.5),
        ),
      ),
    );
  }

  Widget _buildPhotoPickerButton() {
    final isDisabled = _photoLoading || !_canEdit;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDisabled ? Colors.black26 : Colors.black54,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        tooltip: 'Fotoğraf ekle',
        icon: const Icon(
          Icons.add_a_photo_outlined,
          color: Colors.white,
          size: 18,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: isDisabled ? null : _showPhotoSourceSheet,
      ),
    );
  }

  Future<void> _showPhotoSourceSheet() async {
    if (!_canEdit || _photoLoading) {
      return;
    }
    final result = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Kamera'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Galeri'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
    if (result == null || !mounted) {
      return;
    }
    await _handlePhotoPick(result);
  }

  Future<void> _handlePhotoPick(ImageSource source) async {
    if (!_canEdit) {
      return;
    }
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    if (kurumkodu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
      );
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked == null) {
      return;
    }

    final rawBytes = await picked.readAsBytes();
    final optimized = optimizeImageBytes(rawBytes, maxDimension: 1080, quality: 72);
    final ref = FirebaseStorage.instance.ref('$kurumkodu/danisanlar/${widget.id}.jpg');

    setState(() {
      _photoLoading = true;
    });

    try {
      await ref.putData(
        optimized,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final downloadUrl = await ref.getDownloadURL();
      if (!mounted) {
        return;
      }
      setState(() {
        _photoUrl = downloadUrl;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source == ImageSource.camera ? 'Yeni fotoğraf kaydedildi.' : 'Fotoğraf güncellendi.',
          ),
        ),
      );
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fotoğraf yüklenemedi: ${error.message ?? 'Bilinmeyen hata'}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _photoLoading = false;
        });
      }
    }
  }

  Future<void> _deletePhoto({bool silent = false}) async {
    final kurumkodu = (kurum.data['kurumkodu'] ?? '').toString();
    if (kurumkodu.isEmpty) {
      return;
    }
    final ref = FirebaseStorage.instance.ref('$kurumkodu/danisanlar/${widget.id}.jpg');
    setState(() {
      _photoLoading = true;
    });
    try {
      await ref.delete();
      if (!mounted) {
        return;
      }
      setState(() {
        _photoUrl = null;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf silindi.')),
        );
      }
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf silinemedi: ${error.message ?? 'Bilinmeyen hata'}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _photoLoading = false;
        });
      }
    }
  }

  Future<void> _refreshPhoto(Map<String, dynamic> data) async {
    await _loadPhoto(data);
  }

  Future<void> _confirmDeleteStudent() async {
    if (_isDeletingStudent) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Danışanı Sil'),
        content: const Text('Bu danışanı kalıcı olarak silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      setState(() => _isDeletingStudent = true);

      final batch = FirebaseFirestore.instance.batch();
      final extraDocs = await _extraInfoCollection.get();
      for (final doc in extraDocs.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_danisanDoc);
      await batch.commit();
      await _deletePhoto(silent: true);

      if (!mounted) {
        return;
      }
      Get.snackbar(
        'Başarılı',
        'Danışan silindi.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade600,
        colorText: Colors.white,
        margin: const EdgeInsets.all(16),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      Get.snackbar(
        'Hata',
        'Danışan silinemedi: $error',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        margin: const EdgeInsets.all(16),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingStudent = false);
      }
    }
  }

  Widget _buildPhoneInfoRow(String phone) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _buildInfoRow('Telefon', phone.isEmpty ? '-' : phone),
        ),
        if (phone.isNotEmpty) ...[
          const SizedBox(width: 12),
          _buildContactActions(phone),
        ],
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoGrid(
    BuildContext context,
    List<MapEntry<String, String>> entries,
  ) {
    final width = MediaQuery.of(context).size.width;
    final columnWidth = (width - 64) / 2;
    final useFullWidth = columnWidth < 200;

    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: entries
          .map(
            (entry) => SizedBox(
              width: useFullWidth ? double.infinity : columnWidth,
              child: _buildInfoRow(entry.key, entry.value),
            ),
          )
          .toList(),
    );
  }

  void _showPhotoDialog() {
    final url = _photoUrl;
    if (url == null || url.isEmpty) {
      return;
    }
    showGeneralDialog(
      context: context,
      barrierLabel: 'close',
      barrierDismissible: true,
      barrierColor: Colors.black87,
      pageBuilder: (context, _, __) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: Hero(
              tag: 'danisan-photo-${widget.id}',
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    size: 120,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    final theme = Theme.of(context);
    final backgroundColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceVariant.withOpacity(0.3)
        : Colors.grey.shade50;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: backgroundColor,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  String _resolvePhone(Map<String, dynamic> data) {
    final primary = normalizePhone((data['telefon'] ?? '').toString());
    if (primary.isNotEmpty) {
      return primary;
    }
    return normalizePhone((data['ogrencitel'] ?? '').toString());
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    try {
      return DateFormat('yyyy-MM-dd').parse(value.toString());
    } catch (_) {
      return null;
    }
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

  int _parseSequenceNo(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String? _formatDateTime(DateTime? value) {
    if (value == null) {
      return null;
    }
    return DateFormat('dd.MM.yyyy HH:mm').format(value);
  }

  String _formatMinutes(int totalMinutes) {
    final hour = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final minute = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  DateTime _buildDateTimeFromMinutes(DateTime day, int startMinutes) {
    return DateTime(
      day.year,
      day.month,
      day.day,
      startMinutes ~/ 60,
      startMinutes % 60,
    );
  }

  String _buildShortName(String name, String surname) {
    final trimmedName = name.trim();
    final trimmedSurname = surname.trim();
    final firstWord = trimmedName.isNotEmpty
        ? trimmedName.split(RegExp(r'\s+')).first
        : '';
    final surnameInitial =
        trimmedSurname.isNotEmpty ? trimmedSurname.substring(0, 1).toUpperCase() : '';
    if (firstWord.isEmpty && surnameInitial.isEmpty) {
      return '-';
    }
    if (surnameInitial.isEmpty) {
      return firstWord;
    }
    if (firstWord.isEmpty) {
      return surnameInitial;
    }
    return '$firstWord $surnameInitial';
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

  String _shortenDisplayLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final separatorIndex = trimmed.indexOf('•');
    if (separatorIndex == -1) {
      return trimmed;
    }
    return trimmed.substring(0, separatorIndex).trim();
  }

  String _paymentTypeLabel(_PaymentType type) {
    switch (type) {
      case _PaymentType.cash:
        return 'Nakit';
      case _PaymentType.card:
        return 'Kredi Kartı';
      case _PaymentType.transfer:
        return 'Havale/EFT';
    }
  }

  _PaymentType _parsePaymentType(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'card':
        return _PaymentType.card;
      case 'transfer':
        return _PaymentType.transfer;
      case 'cash':
      default:
        return _PaymentType.cash;
    }
  }

  double _parsePrice(String value) {
    final normalized = value.replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
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

  String _formatPrice(double price) {
    if (price % 1 == 0) {
      return price.toStringAsFixed(0);
    }
    return price.toStringAsFixed(2);
  }

  Future<void> _launchExternalUrl(String url) async {
    final uri = Uri.parse(url);
    if (await launcher.canLaunchUrl(uri)) {
      await launcher.launchUrl(uri);
    }
  }
}

class _ReservationEntry {
  const _ReservationEntry({
    required this.id,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    required this.locationName,
    required this.locationId,
    required this.operationName,
    required this.operationId,
    required this.operationCategoryId,
    required this.operationCategoryName,
    required this.operationPrice,
    required this.operations,
    required this.assignedUserName,
    required this.assignedUserId,
    required this.createdByName,
    required this.updatedByName,
    required this.startMinutes,
    required this.endMinutes,
  });

  final String id;
  final DateTime? date;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? locationName;
  final String? locationId;
  final String? operationName;
  final String? operationId;
  final String? operationCategoryId;
  final String? operationCategoryName;
  final double? operationPrice;
  final List<_ReservationOperationData> operations;
  final String? assignedUserName;
  final String? assignedUserId;
  final String? createdByName;
  final String? updatedByName;
  final int? startMinutes;
  final int? endMinutes;

  factory _ReservationEntry.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final date = _readTimestamp(data['date']);
    final startMinutes = _readInt(data['startMinutes']) ??
        (date != null ? date.hour * 60 + date.minute : null);
    final endMinutes = _readInt(data['endMinutes']);
    final operations = _parseReservationOperations(data);
    final primaryOperation = operations.isNotEmpty ? operations.first : null;
    return _ReservationEntry(
      id: snapshot.id,
      date: date,
      createdAt: _readTimestamp(data['createdAt']),
      updatedAt: _readTimestamp(data['updatedAt']),
      locationName: (data['locationName'] ?? '').toString().trim(),
      locationId: (data['locationId'] ?? '').toString().trim(),
      operationName:
          primaryOperation?.operationName ?? (data['operationName'] ?? '').toString().trim(),
      operationId:
          primaryOperation?.operationId ?? (data['operationId'] ?? '').toString().trim(),
      operationCategoryId: primaryOperation?.operationCategoryId ??
          (data['operationCategoryId'] ?? '').toString().trim(),
      operationCategoryName: primaryOperation?.operationCategoryName ??
          (data['operationCategoryName'] ?? '').toString().trim(),
      operationPrice: primaryOperation?.operationPrice ?? _readDouble(data['operationPrice']),
      operations: operations,
      assignedUserName: primaryOperation?.assignedUserName ??
          (data['assignedUserName'] ?? '').toString().trim(),
      assignedUserId: primaryOperation?.assignedUserId ??
          (data['assignedUserId'] ?? '').toString().trim(),
      createdByName: (data['createdByName'] ?? '').toString().trim(),
      updatedByName: (data['updatedByName'] ?? '').toString().trim(),
      startMinutes: startMinutes,
      endMinutes: endMinutes ??
          (startMinutes != null ? startMinutes + _slotDurationMinutes : null),
    );
  }
}

class _ReservationSlot {
  const _ReservationSlot({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.locationName,
    required this.startMinutes,
    required this.endMinutes,
    required this.customerShortName,
    required this.assignedUserId,
    required this.assignedUserColor,
  });

  final String id;
  final String customerId;
  final String customerName;
  final String locationName;
  final int startMinutes;
  final int endMinutes;
  final String customerShortName;
  final String? assignedUserId;
  final Color? assignedUserColor;

  factory _ReservationSlot.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final date = _readTimestamp(data['date']);
    final startMinutes = _readInt(data['startMinutes']) ??
        (date != null ? date.hour * 60 + date.minute : 0);
    final endMinutes = _readInt(data['endMinutes']) ?? startMinutes + _slotDurationMinutes;
    final customerName = (data['customerName'] ?? '').toString().trim();
    final rawShortName = (data['customerShortName'] ?? '').toString().trim();
    final derivedShortName = customerName.isNotEmpty
        ? _buildShortNameFromFullName(customerName)
        : '';
    final resolvedShortName = derivedShortName.isNotEmpty && derivedShortName != '-'
        ? derivedShortName
        : (rawShortName.isNotEmpty ? rawShortName : '-');
    var assignedUserId = (data['assignedUserId'] ?? '').toString().trim();
    if (assignedUserId.isEmpty) {
      final rawOperations = data['operations'];
      if (rawOperations is List) {
        for (final item in rawOperations) {
          if (item is Map) {
            final fallbackId = (item['assignedUserId'] ?? '').toString().trim();
            if (fallbackId.isNotEmpty) {
              assignedUserId = fallbackId;
              break;
            }
          }
        }
      }
    }
    final assignedUserName = (data['assignedUserName'] ?? '').toString().trim();
    final assignedUserColor = _readColor(data['assignedUserColor']) ??
        (assignedUserId.isNotEmpty
            ? _resolveUserColor(assignedUserId)
            : (assignedUserName.isNotEmpty ? _resolveUserColor(assignedUserName) : null));
    return _ReservationSlot(
      id: snapshot.id,
      customerId: (data['customerId'] ?? '').toString().trim(),
      customerName: customerName,
      locationName: (data['locationName'] ?? '').toString().trim(),
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      customerShortName: resolvedShortName,
      assignedUserId: assignedUserId.isNotEmpty ? assignedUserId : null,
      assignedUserColor: assignedUserColor,
    );
  }
}

class _MekanOption {
  const _MekanOption({
    required this.id,
    required this.name,
    required this.sequence,
  });

  final String id;
  final String name;
  final int sequence;
}

class _UserOption {
  const _UserOption({
    required this.id,
    required this.displayName,
    required this.shortLabel,
  });

  final String id;
  final String displayName;
  final String shortLabel;
}

class _OperationOption {
  const _OperationOption({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.price,
    this.defaultUserId,
    this.defaultUserName,
  });

  final String id;
  final String name;
  final String categoryId;
  final String categoryName;
  final double price;
  final String? defaultUserId;
  final String? defaultUserName;

  String get label {
    if (categoryName.trim().isEmpty) {
      return name;
    }
    return '$categoryName • $name';
  }
}

class _ReservationOperationData {
  const _ReservationOperationData({
    required this.operationId,
    required this.operationName,
    required this.operationCategoryId,
    required this.operationCategoryName,
    required this.operationPrice,
    required this.assignedUserId,
    required this.assignedUserName,
    required this.note,
  });

  final String? operationId;
  final String? operationName;
  final String? operationCategoryId;
  final String? operationCategoryName;
  final double? operationPrice;
  final String? assignedUserId;
  final String? assignedUserName;
  final String? note;

  factory _ReservationOperationData.fromMap(Map<String, dynamic> data) {
    return _ReservationOperationData(
      operationId: (data['operationId'] ?? '').toString().trim(),
      operationName: (data['operationName'] ?? '').toString().trim(),
      operationCategoryId: (data['operationCategoryId'] ?? '').toString().trim(),
      operationCategoryName: (data['operationCategoryName'] ?? '').toString().trim(),
      operationPrice: _readDouble(data['operationPrice']),
      assignedUserId: (data['assignedUserId'] ?? '').toString().trim(),
      assignedUserName: (data['assignedUserName'] ?? '').toString().trim(),
      note: (data['note'] ?? data['aciklama'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'operationId': operationId,
      'operationName': operationName,
      'operationCategoryId': operationCategoryId,
      'operationCategoryName': operationCategoryName,
      'operationPrice': operationPrice,
      'assignedUserId': assignedUserId,
      'assignedUserName': assignedUserName,
      'note': note,
    };
  }
}

class _ReservationOperationDraft {
  _ReservationOperationDraft({
    this.operation,
    this.assignedUser,
    TextEditingController? priceController,
    TextEditingController? noteController,
    Key? key,
  })  : priceController = priceController ?? TextEditingController(),
        noteController = noteController ?? TextEditingController(),
        key = key ?? UniqueKey();

  _OperationOption? operation;
  _UserOption? assignedUser;
  final TextEditingController priceController;
  final TextEditingController noteController;
  final Key key;

  void dispose() {
    priceController.dispose();
    noteController.dispose();
  }
}

class _ReservationSelection {
  const _ReservationSelection({
    required this.day,
    required this.location,
    required this.startMinutes,
    required this.endMinutes,
  });

  final DateTime day;
  final _MekanOption location;
  final int startMinutes;
  final int endMinutes;
}

class _TimeSlot {
  const _TimeSlot({
    required this.time,
    required this.startMinutes,
  });

  final TimeOfDay time;
  final int startMinutes;
}

const int _slotDurationMinutes = 30;

List<_TimeSlot> _buildTimeSlots({
  int startHour = 9,
  int endHour = 20,
  int intervalMinutes = _slotDurationMinutes,
}) {
  final slots = <_TimeSlot>[];
  var minutes = startHour * 60;
  final endMinutes = endHour * 60;
  while (minutes < endMinutes) {
    slots.add(
      _TimeSlot(
        time: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        startMinutes: minutes,
      ),
    );
    minutes += intervalMinutes;
  }
  return slots;
}

String _formatTimeLabel(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

Map<String, _ReservationSlot> _buildReservationLookup(List<_ReservationSlot> reservations) {
  final lookup = <String, _ReservationSlot>{};
  for (final reservation in reservations) {
    final endMinutes = reservation.endMinutes > reservation.startMinutes
        ? reservation.endMinutes
        : reservation.startMinutes + _slotDurationMinutes;
    for (var slot = reservation.startMinutes;
        slot < endMinutes;
        slot += _slotDurationMinutes) {
      lookup[_reservationKey(reservation.locationName, slot)] = reservation;
    }
  }
  return lookup;
}

String _reservationKey(String locationName, int slotStartMinutes) {
  return '$locationName-$slotStartMinutes';
}

bool _isSameReservationOwner(_ReservationSlot first, _ReservationSlot second) {
  final firstKey = first.customerId.isNotEmpty ? first.customerId : first.id;
  final secondKey = second.customerId.isNotEmpty ? second.customerId : second.id;
  return firstKey == secondKey;
}

const List<Color> _userColorPalette = [
  Color(0xFFB3E5FC),
  Color(0xFFC8E6C9),
  Color(0xFFFFF9C4),
  Color(0xFFFFCCBC),
  Color(0xFFD1C4E9),
  Color(0xFFFFE0B2),
  Color(0xFFB2DFDB),
  Color(0xFFFFDDE6),
];

Color _resolveUserColor(String userId) {
  if (userId.isEmpty) {
    return const Color(0xFFE0E0E0);
  }
  final index = userId.hashCode.abs() % _userColorPalette.length;
  return _userColorPalette[index];
}

int? _resolveUserColorValue(String? userId) {
  if (userId == null || userId.isEmpty) {
    return null;
  }
  return _resolveUserColor(userId).value;
}

Color? _readColor(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return Color(value);
  }
  if (value is String) {
    final raw = value.trim().replaceAll('#', '');
    if (raw.isEmpty) {
      return null;
    }
    final normalized = raw.length == 6 ? 'FF$raw' : raw;
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) {
      return null;
    }
    return Color(parsed);
  }
  return null;
}

Color _resolveForegroundColor(Color background, Color fallback) {
  final brightness = ThemeData.estimateBrightnessForColor(background);
  return brightness == Brightness.dark ? Colors.white : fallback;
}

String _buildShortNameFromFullName(String fullName) {
  final parts =
      fullName.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) {
    return '-';
  }
  final firstWord = parts.first;
  final lastInitial =
      parts.length > 1 ? parts.last.substring(0, 1).toUpperCase() : '';
  if (lastInitial.isEmpty) {
    return firstWord;
  }
  return '$firstWord $lastInitial';
}

class _ReservationTable extends StatefulWidget {
  const _ReservationTable({
    super.key,
    required this.selectedDay,
    required this.locations,
    required this.reservations,
    required this.selectedLocationId,
    required this.selectedSlots,
    required this.onDayChanged,
    required this.onSlotTapped,
    required this.onReservationTap,
  });

  final DateTime selectedDay;
  final List<_MekanOption> locations;
  final List<_ReservationSlot> reservations;
  final String? selectedLocationId;
  final Set<int> selectedSlots;
  final ValueChanged<DateTime> onDayChanged;
  final void Function(_MekanOption location, int startMinutes) onSlotTapped;
  final ValueChanged<_ReservationSlot> onReservationTap;

  static const double _timeColumnWidth = 72;
  static const double _locationColumnWidth = 112;
  static const double _headerHeight = 44;
  static const double _rowHeight = 44;

  @override
  State<_ReservationTable> createState() => _ReservationTableState();
}

class _ReservationTableState extends State<_ReservationTable> {
  late final ScrollController _headerHorizontalController;
  late final ScrollController _bodyHorizontalController;

  @override
  void initState() {
    super.initState();
    _headerHorizontalController = ScrollController();
    _bodyHorizontalController = ScrollController();
    _bodyHorizontalController.addListener(_syncHeaderScroll);
  }

  @override
  void dispose() {
    _bodyHorizontalController.removeListener(_syncHeaderScroll);
    _bodyHorizontalController.dispose();
    _headerHorizontalController.dispose();
    super.dispose();
  }

  void _syncHeaderScroll() {
    if (!_headerHorizontalController.hasClients) {
      return;
    }
    _headerHorizontalController.jumpTo(_bodyHorizontalController.offset);
  }

  @override
  Widget build(BuildContext context) {
    final slots = _buildTimeSlots();
    final theme = Theme.of(context);
    final reservationLookup = _buildReservationLookup(widget.reservations);
    final borderColor = theme.colorScheme.outlineVariant.withOpacity(0.6);

    return Column(
      children: [
        _buildDateBar(context),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, _) {
              return Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildHeaderRow(context, borderColor),
                    Divider(
                      height: 1,
                      thickness: 0.6,
                      color: borderColor,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTimeColumn(context, slots, borderColor),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                controller: _bodyHorizontalController,
                                child: SizedBox(
                                  width: widget.locations.length *
                                      _ReservationTable._locationColumnWidth,
                                  child: Column(
                                    children: slots
                                        .map(
                                          (slot) => _buildLocationRow(
                                            context,
                                            slot,
                                            reservationLookup,
                                            borderColor,
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDateBar(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant.withOpacity(0.6);
    final label = DateFormat('dd.MM.yyyy').format(widget.selectedDay);
    final dayLabel = DateFormat('EEEE', 'tr_TR').format(widget.selectedDay);
    final today = DateUtils.dateOnly(DateTime.now());
    final tomorrow = DateUtils.dateOnly(today.add(const Duration(days: 1)));
    String? daySuffix;
    if (DateUtils.isSameDay(widget.selectedDay, today)) {
      daySuffix = 'Bugün';
    } else if (DateUtils.isSameDay(widget.selectedDay, tomorrow)) {
      daySuffix = 'Yarın';
    }
    final dayLine = daySuffix == null ? dayLabel : '$dayLabel ($daySuffix)';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Önceki gün',
            onPressed: () =>
                widget.onDayChanged(widget.selectedDay.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dayLine,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Sonraki gün',
            onPressed: () =>
                widget.onDayChanged(widget.selectedDay.add(const Duration(days: 1))),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Tarih seç',
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: widget.selectedDay,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                widget.onDayChanged(DateUtils.dateOnly(picked));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context, Color borderColor) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _ReservationTable._headerHeight,
      child: Row(
        children: [
          Container(
            width: _ReservationTable._timeColumnWidth,
            height: _ReservationTable._headerHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              border: Border(
                right: BorderSide(color: borderColor, width: 0.6),
              ),
            ),
            child: Text(
              'Saat',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _headerHorizontalController,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: widget.locations.length *
                    _ReservationTable._locationColumnWidth,
                child: Row(
                  children: widget.locations
                      .map(
                        (location) => Container(
                          width: _ReservationTable._locationColumnWidth,
                          height: _ReservationTable._headerHeight,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant,
                            border: Border(
                              right: BorderSide(color: borderColor, width: 0.6),
                            ),
                          ),
                          child: Text(
                            location.name,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeColumn(
    BuildContext context,
    List<_TimeSlot> slots,
    Color borderColor,
  ) {
    final theme = Theme.of(context);
    return Column(
      children: slots
          .map(
            (slot) => Container(
              width: _ReservationTable._timeColumnWidth,
              height: _ReservationTable._rowHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  right: BorderSide(color: borderColor, width: 0.6),
                  bottom: BorderSide(color: borderColor, width: 0.6),
                ),
              ),
              child: Text(
                _formatTimeLabel(slot.time),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildLocationRow(
    BuildContext context,
    _TimeSlot slot,
    Map<String, _ReservationSlot> reservationLookup,
    Color borderColor,
  ) {
    return SizedBox(
      height: _ReservationTable._rowHeight,
      child: Row(
        children: widget.locations.map((location) {
          final reservation =
              reservationLookup[_reservationKey(location.name, slot.startMinutes)];
          final prevSlotStart = slot.startMinutes - _slotDurationMinutes;
          final prevReservation =
              reservationLookup[_reservationKey(location.name, prevSlotStart)];
          final nextSlotStart = slot.startMinutes + _slotDurationMinutes;
          final nextReservation =
              reservationLookup[_reservationKey(location.name, nextSlotStart)];
          final sameAsPrev = reservation != null &&
              prevReservation != null &&
              _isSameReservationOwner(prevReservation, reservation);
          final sameAsNext = reservation != null &&
              nextReservation != null &&
              _isSameReservationOwner(nextReservation, reservation);
          final isStart = reservation != null && !sameAsPrev;
          final isEnd = reservation != null && !sameAsNext;
          final isSelected = reservation == null &&
              widget.selectedLocationId == location.id &&
              widget.selectedSlots.contains(slot.startMinutes);
          return _buildReservationCell(
            context: context,
            location: location,
            slot: slot,
            reservation: reservation,
            isStart: isStart,
            isEnd: isEnd,
            showLabel: reservation != null,
            isSelected: isSelected,
            borderColor: borderColor,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildReservationCell({
    required BuildContext context,
    required _MekanOption location,
    required _TimeSlot slot,
    required _ReservationSlot? reservation,
    required bool isStart,
    required bool isEnd,
    required bool showLabel,
    required bool isSelected,
    required Color borderColor,
  }) {
    final theme = Theme.of(context);
    final baseCellColor = Color.lerp(
          theme.colorScheme.surface,
          theme.colorScheme.surfaceVariant,
          0.12,
        ) ??
        theme.colorScheme.surface;
    final selectedColor = Color.lerp(
          theme.colorScheme.primary.withOpacity(0.18),
          theme.colorScheme.surfaceVariant,
          0.3,
        ) ??
        theme.colorScheme.primary.withOpacity(0.12);
    final reservationColor =
        reservation?.assignedUserColor ?? theme.colorScheme.surfaceVariant;
    final cellColor = reservation == null
        ? (isSelected ? selectedColor : baseCellColor)
        : reservationColor.withOpacity(0.2);
    final labelColor = reservation?.assignedUserColor != null
        ? _resolveForegroundColor(reservationColor, theme.colorScheme.onSurface)
        : theme.colorScheme.onSurface;
    final displayName = reservation == null
        ? ''
        : (reservation.customerName.isNotEmpty
            ? reservation.customerName
            : reservation.customerShortName);
    final labelText = showLabel ? displayName : '';
    final cardRadius = reservation == null
        ? BorderRadius.circular(8)
        : isStart && isEnd
            ? BorderRadius.circular(8)
            : isStart
                ? const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                    bottomLeft: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  )
                : isEnd
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(2),
                        topRight: Radius.circular(2),
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      )
                    : BorderRadius.circular(2);
    final showShadow = reservation != null && (isStart || isEnd);
    final bottomBorderColor =
        reservation != null && !isEnd ? Colors.transparent : borderColor;
    return SizedBox(
      width: _ReservationTable._locationColumnWidth,
      height: _ReservationTable._rowHeight,
      child: Material(
        color: cellColor,
        child: InkWell(
          onTap: reservation == null
              ? () => widget.onSlotTapped(location, slot.startMinutes)
              : () => widget.onReservationTap(reservation),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: borderColor, width: 0.6),
                bottom: BorderSide(color: bottomBorderColor, width: 0.6),
              ),
            ),
            child: reservation == null
                ? const SizedBox.shrink()
                : SizedBox.expand(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: reservationColor,
                        borderRadius: cardRadius,
                        boxShadow: showShadow
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : const [],
                      ),
                      child: Center(
                        child: Text(
                          labelText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: labelColor,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

DateTime? _readTimestamp(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}

int? _readInt(dynamic value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '');
}

double? _readDouble(dynamic value) {
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final normalized = raw.replaceAll(',', '.');
  return double.tryParse(normalized);
}

List<_ReservationOperationData> _parseReservationOperations(Map<String, dynamic> data) {
  final operations = <_ReservationOperationData>[];
  final rawList = data['operations'];
  if (rawList is List) {
    for (final item in rawList) {
      if (item is Map) {
        operations.add(
          _ReservationOperationData.fromMap(Map<String, dynamic>.from(item)),
        );
      }
    }
  }
  if (operations.isNotEmpty) {
    return operations;
  }

  final legacyName = (data['operationName'] ?? '').toString().trim();
  if (legacyName.isEmpty) {
    return operations;
  }

  operations.add(
    _ReservationOperationData(
      operationId: (data['operationId'] ?? '').toString().trim(),
      operationName: legacyName,
      operationCategoryId: (data['operationCategoryId'] ?? '').toString().trim(),
      operationCategoryName: (data['operationCategoryName'] ?? '').toString().trim(),
      operationPrice: _readDouble(data['operationPrice']),
      assignedUserId: (data['assignedUserId'] ?? '').toString().trim(),
      assignedUserName: (data['assignedUserName'] ?? '').toString().trim(),
      note: (data['note'] ?? data['aciklama'] ?? '').toString().trim(),
    ),
  );
  return operations;
}
