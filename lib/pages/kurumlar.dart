  import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/user_controller.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

class KurumlarPage extends StatefulWidget {
  const KurumlarPage({super.key});

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

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _filterInstitutions(_searchController.text);
    });
    _loadInstitutions();
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
          'kurumturu': data['kurumturu'] ?? '',
          'baslangicTarihi': data['baslangicTarihi'] ?? '',
          'bitisTarihi': data['bitisTarihi'] ?? '',
          'ilgiliKisiAdi': data['ilgiliKisiAdi'] ?? '',
          'ilgiliKisiTelefon': data['ilgiliKisiTelefon'] ?? '',
          'adres': data['adres'] ?? '',
          'ekBilgiler': data['ekBilgiler'] ?? '',
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
        _filteredInstitutions = List.from(_institutions);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Kurumlar yüklenirken hata oluştu: $e';
      });
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
          institution['kisaad'] ?? '',
          institution['kurumturu'] ?? '',
        ].join(' ').toUpperCase();
        return values.contains(cleanQuery);
      }).toList();
    });
  }

  Future<void> _openInstitutionDialog({Map<String, dynamic>? institution}) async {
    final bool isEdit = institution != null;
    final formKey = GlobalKey<FormState>();

    final TextEditingController kisaAdController =
        TextEditingController(text: institution?['kisaad'] ?? '');
    final TextEditingController kurumAdiController =
        TextEditingController(text: institution?['kurumadi'] ?? '');
    final TextEditingController kurumkoduController =
        TextEditingController(text: institution?['kurumkodu'] ?? '');
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
    final TextEditingController smsApiUsernameController =
        TextEditingController(text: institution?['smsApiUsername'] ?? '');
    final TextEditingController smsApiPasswordController =
        TextEditingController(text: institution?['smsApiPassword'] ?? '');
    final TextEditingController smsApiBaslikController =
        TextEditingController(text: institution?['smsApiBaslik'] ?? '');
    final TextEditingController smsApiTurController =
        TextEditingController(
            text: (institution?['smsApiTur'] ?? 'normal').toString());

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
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
                    label: 'Kurum Türü',
                    controller: kurumTuruController,
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
                  _buildTextField(
                    label: 'Tür (normal/turkce)',
                    controller: smsApiTurController,
                    hintText: 'Varsayılan: normal',
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
                  'kurumturu': kurumTuruController.text.trim(),
                  'baslangicTarihi': baslangicController.text.trim(),
                  'bitisTarihi': bitisController.text.trim(),
                  'ilgiliKisiAdi': ilgiliKisiAdiController.text.trim(),
                  'ilgiliKisiTelefon': ilgiliKisiTelefonController.text.trim(),
                  'adres': adresController.text.trim(),
                  'ekBilgiler': ekBilgilerController.text.trim(),
                  'smsApiUsername': smsApiUsernameController.text.trim(),
                  'smsApiPassword': smsApiPasswordController.text.trim(),
                  'smsApiBaslik': smsApiBaslikController.text.trim(),
                  'smsApiTur': smsApiTurController.text.trim().isEmpty
                      ? 'normal'
                      : smsApiTurController.text.trim(),
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
                        content:
                            Text('Kurum kaydedilirken hata oluştu: $e'),
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
  }

  Future<void> _saveInstitution({
    required Map<String, dynamic> data,
    required bool isEdit,
    String? docId,
  }) async {
    final String kurumkodu = data['kurumkodu'] as String;
    final String targetDocId = isEdit ? (docId ?? kurumkodu) : kurumkodu;

    await _firestore.collection('kurumlar').doc(targetDocId).set(
          data,
          SetOptions(merge: true),
        );
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
      await _firestore
          .collection('kurumlar')
          .doc(institution['docId'] as String)
          .delete();
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
            onPressed: _loadInstitutions,
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
