  import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/user_controller.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

class KurumlarPage extends StatefulWidget {
  const KurumlarPage({super.key, this.initialKurumkodu});

  /// Sayfa açıldığında bu kurumkodu ile arama alanı ön-doldurulur.
  final String? initialKurumkodu;

  @override
  State<KurumlarPage> createState() => _KurumlarPageState();
}

class _KurumlarPageState extends State<KurumlarPage> {
  final UserController user = Get.find<UserController>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  final List<Map<String, dynamic>> _institutions = [];
  List<Map<String, dynamic>> _filteredInstitutions = [];
  final List<Map<String, dynamic>> _smsProviders = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _filterInstitutions(_searchController.text);
    });
    if (widget.initialKurumkodu?.isNotEmpty == true) {
      _searchController.text = widget.initialKurumkodu!;
    }
    _loadInstitutions();
    _loadSmsProviders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInstitutions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final querySnapshot = await _firestore
          .collection('kurumlar')
          .orderBy('kurumadi', descending: false)
          .get();

      final items = querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'docId': doc.id,
          'kisaad': data['kisaad'] ?? '',
          'kurumadi': data['kurumadi'] ?? '',
          'kurumkodu': data['kurumkodu'] ?? doc.id,
          'slug': data['slug'] ?? '',
          'bookingEnabled': data['bookingEnabled'] == true,
          'kurumturu': data['kurumturu'] ?? '',
          'baslangicTarihi': data['baslangicTarihi'] ?? '',
          'bitisTarihi': data['bitisTarihi'] ?? '',
          'ilgiliKisiAdi': data['ilgiliKisiAdi'] ?? '',
          'ilgiliKisiTelefon': data['ilgiliKisiTelefon'] ?? '',
          'adres': data['adres'] ?? '',
          'ekBilgiler': data['ekBilgiler'] ?? '',
          'smsProviderId': data['smsProviderId'] ?? '',
          'smsApiKey': data['smsApiKey'] ?? '',
          'smsApiUsername': data['smsApiUsername'] ?? '',
          'smsApiPassword': data['smsApiPassword'] ?? '',
          'smsApiBaslik': data['smsApiBaslik'] ?? '',
          'smsApiTur': data['smsApiTur'] ?? '',
        };
      }).toList();

      setState(() {
        _institutions
          ..clear()
          ..addAll(items);
        final q = widget.initialKurumkodu?.trim() ?? '';
        _filteredInstitutions = q.isNotEmpty
            ? items.where((i) {
                final v = [i['kurumkodu'] ?? '', i['kurumadi'] ?? '', i['kisaad'] ?? '']
                    .join(' ')
                    .toUpperCase();
                return v.contains(q.toUpperCase());
              }).toList()
            : List.from(_institutions);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Kurumlar yüklenirken hata oluştu: $e';
      });
    }
  }

  Future<void> _loadSmsProviders() async {
    try {
      final snapshot = await _firestore.collection('sms_providers').get();
      final items = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'docId': doc.id,
          'name': data['name'] ?? doc.id,
        };
      }).toList();

      items.sort((a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));

      setState(() {
        _smsProviders
          ..clear()
          ..addAll(items);
      });
    } catch (_) {
      // Sessiz geç, kurum ekranı çalışmaya devam etsin.
    }
  }

  void _filterInstitutions(String query) {
    final cleanQuery = query.trim().toUpperCase();
    setState(() {
      if (cleanQuery.isEmpty) {
        _filteredInstitutions = List.from(_institutions);
        return;
      }

      _filteredInstitutions = _institutions.where((institution) {
        final values = [
          institution['kurumadi'] ?? '',
          institution['kurumkodu'] ?? '',
          institution['slug'] ?? '',
          institution['kisaad'] ?? '',
          institution['kurumturu'] ?? '',
        ].join(' ').toUpperCase();
        return values.contains(cleanQuery);
      }).toList();
    });
  }

  String _slugify(String raw) {
    var value = raw.toLowerCase().trim();
    const trMap = {
      'ç': 'c',
      'ğ': 'g',
      'ı': 'i',
      'ö': 'o',
      'ş': 's',
      'ü': 'u',
    };
    trMap.forEach((key, val) {
      value = value.replaceAll(key, val);
    });
    value = value.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    value = value.replaceAll(RegExp(r'-{2,}'), '-');
    value = value.replaceAll(RegExp(r'^-+|-+$'), '');
    return value;
  }

  Future<String> _ensureUniqueSlug(
    String baseSlug, {
    required String currentDocId,
  }) async {
    var candidate = _slugify(baseSlug);
    if (candidate.isEmpty) {
      throw Exception('Slug boş olamaz.');
    }

    var suffix = 1;
    while (true) {
      final query = await _firestore
          .collection('kurumlar')
          .where('slug', isEqualTo: candidate)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        return candidate;
      }

      final doc = query.docs.first;
      if (doc.id == currentDocId) {
        return candidate;
      }

      suffix += 1;
      candidate = '${_slugify(baseSlug)}-$suffix';
    }
  }

  Future<void> _openInstitutionDialog({Map<String, dynamic>? institution}) async {
    await _loadSmsProviders();

    final bool isEdit = institution != null;
    final formKey = GlobalKey<FormState>();

    final TextEditingController kisaAdController =
        TextEditingController(text: institution?['kisaad'] ?? '');
    final TextEditingController kurumAdiController =
        TextEditingController(text: institution?['kurumadi'] ?? '');
    final TextEditingController kurumkoduController =
        TextEditingController(text: institution?['kurumkodu'] ?? '');
    final TextEditingController slugController =
        TextEditingController(text: institution?['slug'] ?? '');
    final TextEditingController kurumTuruController =
        TextEditingController(text: institution?['kurumturu'] ?? '');
    final TextEditingController baslangicController =
        TextEditingController(text: institution?['baslangicTarihi'] ?? '');
    final TextEditingController bitisController =
        TextEditingController(text: institution?['bitisTarihi'] ?? '');
    final TextEditingController ilgiliKisiAdiController =
        TextEditingController(text: institution?['ilgiliKisiAdi'] ?? '');
    final TextEditingController ilgiliKisiTelefonController =
        TextEditingController(text: institution?['ilgiliKisiTelefon'] ?? '');
    final TextEditingController adresController =
        TextEditingController(text: institution?['adres'] ?? '');
    final TextEditingController ekBilgilerController =
        TextEditingController(text: institution?['ekBilgiler'] ?? '');
    final TextEditingController smsProviderIdController =
        TextEditingController(text: institution?['smsProviderId'] ?? '');
    final TextEditingController smsApiUsernameController =
        TextEditingController(text: institution?['smsApiUsername'] ?? '');
    final TextEditingController smsApiPasswordController =
        TextEditingController(text: institution?['smsApiPassword'] ?? '');
    final TextEditingController smsApiBaslikController =
        TextEditingController(text: institution?['smsApiBaslik'] ?? '');

    String selectedProviderId = smsProviderIdController.text.trim();
    var bookingEnabled = institution?['bookingEnabled'] == true;
    var slugManuallyEdited = slugController.text.trim().isNotEmpty;
    kurumAdiController.addListener(() {
      if (slugManuallyEdited) return;
      slugController.text = _slugify(kurumAdiController.text);
    });

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(isEdit ? 'Kurum Bilgilerini Güncelle' : 'Yeni Kurum'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTextField(
                        label: 'Kurum Kodu',
                        controller: kurumkoduController,
                        readOnly: isEdit,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Kurum kodu zorunludur';
                          }
                          return null;
                        },
                      ),
                  _buildTextField(
                    label: 'Kısa Ad',
                    controller: kisaAdController,
                  ),
                  _buildTextField(
                    label: 'Kurum Adı',
                    controller: kurumAdiController,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Kurum adı zorunludur';
                      }
                      return null;
                    },
                  ),
                  _buildTextField(
                    label: 'Slug',
                    controller: slugController,
                    hintText: 'orn: mebs',
                    validator: (value) {
                      final normalized = _slugify(value ?? '');
                      if (normalized.isEmpty) {
                        return 'Slug zorunludur';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      slugManuallyEdited = value.trim().isNotEmpty;
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        final generated = _slugify(kurumAdiController.text);
                        setLocalState(() {
                          slugController.text = generated;
                          slugManuallyEdited = true;
                        });
                      },
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Kurum adından slug üret'),
                    ),
                  ),
                  _buildTextField(
                    label: 'Kurum Türü',
                    controller: kurumTuruController,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Online Booking Aktif'),
                    value: bookingEnabled,
                    onChanged: (value) {
                      setLocalState(() {
                        bookingEnabled = value;
                      });
                    },
                  ),
                  _buildTextField(
                    label: 'Başlangıç Tarihi',
                    controller: baslangicController,
                    hintText: 'Örn: 01.09.2023',
                  ),
                  _buildTextField(
                    label: 'Bitiş Tarihi',
                    controller: bitisController,
                    hintText: 'Örn: 30.06.2024',
                  ),
                  _buildTextField(
                    label: 'İlgili Kişi Adı',
                    controller: ilgiliKisiAdiController,
                  ),
                  _buildTextField(
                    label: 'İlgili Kişi Telefon',
                    controller: ilgiliKisiTelefonController,
                    keyboardType: TextInputType.phone,
                  ),
                  _buildTextField(
                    label: 'Adres',
                    controller: adresController,
                    maxLines: 2,
                  ),
                  _buildTextField(
                    label: 'Ek Bilgiler',
                    controller: ekBilgilerController,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'SMS API Bilgileri',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: () {
                      if (selectedProviderId.isEmpty) {
                        return null;
                      }
                      final exists = _smsProviders.any(
                        (provider) => (provider['docId'] ?? '').toString() == selectedProviderId,
                      );
                      return exists ? selectedProviderId : null;
                    }(),
                    decoration: const InputDecoration(
                      labelText: 'SMS Sağlayıcı',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Seçiniz'),
                      ),
                      ..._smsProviders.map(
                        (provider) => DropdownMenuItem(
                          value: provider['docId'] as String,
                          child: Text(
                            (provider['name'] ?? provider['docId']).toString(),
                          ),
                        ),
                      ),
                      if (selectedProviderId.isNotEmpty &&
                          !_smsProviders.any(
                            (provider) =>
                                (provider['docId'] ?? '').toString() ==
                                selectedProviderId,
                          ))
                        DropdownMenuItem(
                          value: selectedProviderId,
                          child: Text('Mevcut: $selectedProviderId'),
                        ),
                    ],
                    onChanged: (value) {
                      setLocalState(() {
                        selectedProviderId = value ?? '';
                        smsProviderIdController.text = selectedProviderId;
                      });
                    },
                  ),
                  _buildTextField(
                    label: 'API Kullanıcı Adı',
                    controller: smsApiUsernameController,
                  ),
                  _buildTextField(
                    label: 'API Şifresi',
                    controller: smsApiPasswordController,
                    obscureText: true,
                  ),
                  _buildTextField(
                    label: 'Gönderici Başlığı',
                    controller: smsApiBaslikController,
                    hintText: 'Örn: OKULADI',
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.info_outline),
                    title: Text('Mesaj Türü'),
                    subtitle: Text('turkce (varsayılan)'),
                  ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) {
                      return;
                    }

                    final payload = {
                      'kisaad': kisaAdController.text.trim(),
                      'kurumadi': kurumAdiController.text.trim(),
                      'kurumkodu': kurumkoduController.text.trim(),
                      'slug': slugController.text.trim(),
                      'bookingEnabled': bookingEnabled,
                      'kurumturu': kurumTuruController.text.trim(),
                      'baslangicTarihi': baslangicController.text.trim(),
                      'bitisTarihi': bitisController.text.trim(),
                      'ilgiliKisiAdi': ilgiliKisiAdiController.text.trim(),
                      'ilgiliKisiTelefon': ilgiliKisiTelefonController.text.trim(),
                      'adres': adresController.text.trim(),
                      'ekBilgiler': ekBilgilerController.text.trim(),
                      'smsProviderId': smsProviderIdController.text.trim(),
                      'smsApiUsername': smsApiUsernameController.text.trim(),
                      'smsApiPassword': smsApiPasswordController.text.trim(),
                      'smsApiBaslik': smsApiBaslikController.text.trim(),
                      'smsApiTur': 'turkce',
                    };

                    try {
                      await _saveInstitution(
                        docId: institution?['docId'],
                        data: payload,
                        isEdit: isEdit,
                      );

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isEdit
                                  ? 'Kurum bilgileri güncellendi.'
                                  : 'Kurum başarıyla oluşturuldu.',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Kurum kaydedilirken hata oluştu: $e'),
                          ),
                        );
                      }
                    } finally {
                      await _loadInstitutions();
                    }
                  },
                  child: Text(isEdit ? 'Güncelle' : 'Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveInstitution({
    required Map<String, dynamic> data,
    required bool isEdit,
    String? docId,
  }) async {
    final String kurumkodu = data['kurumkodu'] as String;
    final String targetDocId = isEdit ? (docId ?? kurumkodu) : kurumkodu;
    final normalizedBaseSlug = _slugify(
      (data['slug'] ?? '').toString().trim().isNotEmpty
          ? (data['slug'] as String)
          : (data['kurumadi'] as String),
    );
    final uniqueSlug = await _ensureUniqueSlug(
      normalizedBaseSlug,
      currentDocId: targetDocId,
    );

    final existingDoc =
        await _firestore.collection('kurumlar').doc(targetDocId).get();
    final previousSlug = _slugify((existingDoc.data()?['slug'] ?? '').toString());

    final payload = Map<String, dynamic>.from(data)
      ..['slug'] = uniqueSlug
      ..['updatedAt'] = FieldValue.serverTimestamp();

    final batch = _firestore.batch();
    final kurumRef = _firestore.collection('kurumlar').doc(targetDocId);
    batch.set(kurumRef, payload, SetOptions(merge: true));

    final slugRef = _firestore.collection('orgSlugs').doc(uniqueSlug);
    batch.set(slugRef, {
      'orgId': targetDocId,
      'active': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': existingDoc.exists
          ? (existingDoc.data()?['createdAt'] ?? FieldValue.serverTimestamp())
          : FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (previousSlug.isNotEmpty && previousSlug != uniqueSlug) {
      final oldSlugRef = _firestore.collection('orgSlugs').doc(previousSlug);
      batch.set(oldSlugRef, {
        'orgId': targetDocId,
        'active': false,
        'replacedBy': uniqueSlug,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<void> _deleteInstitution(Map<String, dynamic> institution) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kurumu Sil'),
          content: Text(
            '${institution['kurumadi']} kurumunu silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    try {
      final docId = institution['docId'] as String;
      final slug = _slugify((institution['slug'] ?? '').toString());
      final batch = _firestore.batch();
      batch.delete(_firestore.collection('kurumlar').doc(docId));
      if (slug.isNotEmpty) {
        batch.set(
          _firestore.collection('orgSlugs').doc(slug),
          {
            'orgId': docId,
            'active': false,
            'deletedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kurum silindi.')),
        );
      }
      await _loadInstitutions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kurum silinemedi: $e')),
        );
      }
    }
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hintText,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    bool readOnly = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool obscureText = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        onChanged: onChanged,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  bool get _canAccessPage =>
      (user.data['ustyonetici']?.toString().toLowerCase() == 'admin');

  @override
  Widget build(BuildContext context) {
    if (!_canAccessPage) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Kurumlar'),
          actions: const [HomeIconButton()],
        ),
        body: const Center(
          child: Text('Bu sayfayı görüntüleme yetkiniz bulunmamaktadır.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kurumlar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadInstitutions();
              await _loadSmsProviders();
            },
            tooltip: 'Yenile',
          ),
          const HomeIconButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openInstitutionDialog(),
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Kurum ara (isim, kod vb.)...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(child: Text(_errorMessage!))
                      : _filteredInstitutions.isEmpty
                          ? const Center(
                              child: Text('Kayıtlı kurum bulunamadı.'),
                            )
                          : ListView.builder(
                              itemCount: _filteredInstitutions.length,
                              itemBuilder: (context, index) {
                                final institution =
                                    _filteredInstitutions[index];
                                return Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 8.0),
                                  child: ListTile(
                                    title: Text(
                                      institution['kurumadi'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Kurum Kodu: '
                                            '${institution['kurumkodu'] ?? ''}'),
                                        if ((institution['slug'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Text('Slug: ${institution['slug']}'),
                                        Text(
                                          'Online Booking: ${institution['bookingEnabled'] == true ? 'Açık' : 'Kapalı'}',
                                        ),
                                        if ((institution['kisaad'] ?? '').isNotEmpty)
                                          Text('Kısa Ad: '
                                              '${institution['kisaad']}'),
                                        if ((institution['kurumturu'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Text('Tür: '
                                              '${institution['kurumturu']}'),
                                        if ((institution['baslangicTarihi'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Text('Başlangıç: '
                                              '${institution['baslangicTarihi']}'),
                                        if ((institution['bitisTarihi'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Text('Bitiş: '
                                              '${institution['bitisTarihi']}'),
                                        if ((institution['ilgiliKisiAdi'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Text('İlgili Kişi: '
                                              '${institution['ilgiliKisiAdi']}'),
                                        if ((institution['ilgiliKisiTelefon'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Text('Telefon: '
                                              '${institution['ilgiliKisiTelefon']}'),
                                        if ((institution['adres'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Text('Adres: ${institution['adres']}'),
                                        if ((institution['ekBilgiler'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Text('Ek Bilgiler: '
                                              '${institution['ekBilgiler']}'),
                                        if ((institution['smsProviderId'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Text('SMS Provider: '
                                              '${institution['smsProviderId']}'),
                                        if ((institution['smsApiUsername'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Text('SMS Kullanıcı: '
                                              '${institution['smsApiUsername']}'),
                                        if ((institution['smsApiBaslik'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Text('SMS Başlık: '
                                              '${institution['smsApiBaslik']}'),
                                        if ((institution['smsApiTur'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Text('SMS Tür: '
                                              '${institution['smsApiTur']}'),
                                      ],
                                    ),
                                    isThreeLine: true,
                                    trailing: PopupMenuButton<int>(
                                      onSelected: (value) {
                                        if (value == 0) {
                                          _openInstitutionDialog(
                                            institution: institution,
                                          );
                                        } else if (value == 1) {
                                          _deleteInstitution(institution);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 0,
                                          child: Text('Düzenle'),
                                        ),
                                        const PopupMenuItem(
                                          value: 1,
                                          child: Text('Sil'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
