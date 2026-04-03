import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kurum_takip/firebase_options.dart';
import 'package:get/get.dart';
import 'package:kurum_takip/controllers/user_controller.dart';
import 'package:kurum_takip/utils/permission_utils.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import 'personel/aylik_pirim_page.dart';
import 'personel/calisma_saatleri_page.dart';
import 'personel/izin_page.dart';
import 'personel/performans_page.dart';
import 'personel/personel_odeme_page.dart';
import 'personel/pirim_tanimlari_page.dart';

class UserProfilePage extends StatefulWidget {
  final String userDocId;

  const UserProfilePage({super.key, required this.userDocId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _isSavingPermissions = false;

  String _normalizeRole(String value) {
    var input = value.trim();
    if (input.isEmpty) return '';
    input = input
        .replaceAll('\u0307', '')
        .replaceAll('İ', 'I')
        .replaceAll('ı', 'I')
        .replaceAll('ö', 'O')
        .replaceAll('Ö', 'O')
        .replaceAll('ü', 'U')
        .replaceAll('Ü', 'U')
        .replaceAll('ş', 'S')
        .replaceAll('Ş', 'S')
        .replaceAll('ç', 'C')
        .replaceAll('Ç', 'C')
        .replaceAll('ğ', 'G')
        .replaceAll('Ğ', 'G')
        .toUpperCase();
    return input;
  }

  static const Map<String, String> _fieldLabels = {
    'adi': 'Adı',
    'soyadi': 'Soyadı',
    'kisaad': 'Kısa Ad',
    'rol': 'Rol',
    'telefon': 'Telefon',
    'adres': 'Adres',
    'ekBilgiler': 'Ek Bilgiler',
  };

  static const List<String> _permissionOrder = [
    kPermissionViewPrice,
    kPermissionUpdatePrice,
    kPermissionCreateReservation,
    kPermissionUpdateReservation,
    kPermissionTakePayment,
    kPermissionViewAllReservations,
    kPermissionViewContactInfo,
    kPermissionSearchStudents,
    kPermissionUpdateStudent,
    kPermissionMakeSale,
    kPermissionManagePackages,
    kPermissionAddToContacts,
    kPermissionReceiveAllReservationNotifications,
    kPermissionReceiveAssignedReservationNotifications,
  ];

  static const Map<String, String> _permissionLabels = {
    kPermissionViewPrice: 'Fiyat bilgilerini görme',
    kPermissionUpdatePrice: 'Fiyat değiştirme',
    kPermissionCreateReservation: 'Rezervasyon alma',
    kPermissionUpdateReservation: 'Rezervasyon güncelleme',
    kPermissionTakePayment: 'Ödeme alma',
    kPermissionViewAllReservations: 'Tüm rezervasyonları görme',
    kPermissionViewContactInfo: 'Müşteri iletişim bilgilerini görme',
    kPermissionSearchStudents: 'Danışan arama',
    kPermissionUpdateStudent: 'Danışan güncelleme',
    kPermissionMakeSale: 'Satış yapma',
    kPermissionManagePackages: 'Paket ekleme / oluşturma',
    kPermissionAddToContacts: 'Danışanı telefon rehberine ekleme',
    kPermissionReceiveAllReservationNotifications: 'Tüm randevu bildirimlerini al',
    kPermissionReceiveAssignedReservationNotifications:
        'Sadece kendine atanan görev bildirimlerini al',
  };

  static const List<Color> _userColorPalette = [
    Color(0xFFB3E5FC),
    Color(0xFFC8E6C9),
    Color(0xFFFFF9C4),
    Color(0xFFFFCCBC),
    Color(0xFFD1C4E9),
    Color(0xFFFFE0B2),
    Color(0xFFB2DFDB),
    Color(0xFFFFDDE6),
  ];

  @override
  void initState() {
    super.initState();
    fetchUserData();
  }

  Future<void> fetchUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(widget.userDocId)
          .get();

      if (!mounted) {
        return;
      }

      setState(() {
        _userData = snapshot.data();
        _isLoading = false;
      });

      if (!snapshot.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanıcı bulunamadı.')),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcı verileri alınamadı.')),
      );
    }
  }

  Future<void> updateUserField(String field, dynamic newValue) async {
    try {
      await FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(widget.userDocId)
          .update({field: newValue});

      await fetchUserData();

      if (!mounted) return;

      final label = _fieldLabels[field] ?? field;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label güncellendi.')),
      );
    } catch (e) {
      if (!mounted) return;
      final label = _fieldLabels[field] ?? field;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label güncellenemedi: $e')),
      );
    }
  }

  void showUpdateDialog(String field, dynamic initialValue) {
    final controller =
        TextEditingController(text: initialValue?.toString() ?? '');
    String? selectedRole = initialValue?.toString();
    selectedRole ??= 'YÖNETİCİ';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('${_fieldLabels[field] ?? field} Güncelle'),
              content: field == 'rol'
                  ? DropdownButton<String>(
                      value: selectedRole,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'YÖNETİCİ', child: Text('YÖNETİCİ')),
                        DropdownMenuItem(value: 'ÇALIŞAN', child: Text('ÇALIŞAN')),
                        DropdownMenuItem(value: 'MUHASEBE', child: Text('MUHASEBE')),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          selectedRole = value ?? 'YÖNETİCİ';
                        });
                      },
                    )
                  : TextField(
                      controller: controller,
                      maxLines: field == 'ekBilgiler' ? 5 : 1,
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('İptal'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    updateUserField(
                      field,
                      field == 'rol' ? selectedRole : controller.text.trim(),
                    );
                  },
                  child: const Text('Güncelle'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _isEditableField(String field) {
    return _fieldLabels.containsKey(field);
  }

  Set<String> _readPermissions() {
    final raw = _userData?['yetkiler'];
    if (raw is Iterable) {
      return raw
          .map((item) => item?.toString().trim())
          .where((item) => item != null && item!.isNotEmpty)
          .cast<String>()
          .toSet();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return {raw.trim()};
    }
    return <String>{};
  }

  Future<void> _updateUserPermissions(Set<String> permissions) async {
    if (_isSavingPermissions) {
      return;
    }
    setState(() {
      _isSavingPermissions = true;
    });
    try {
      final payload = permissions.toList()..sort();
      await FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(widget.userDocId)
          .update({'yetkiler': payload});

      await fetchUserData();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yetkiler güncellendi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yetkiler güncellenemedi: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPermissions = false;
        });
      }
    }
  }

  Widget _buildProfileItem(String title, String field, dynamic value) {
    final displayValue = value?.toString() ?? 'Yok';

    return InkWell(
      onDoubleTap: _isEditableField(field)
          ? () => showUpdateDialog(field, value)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                '$title:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(child: Text(displayValue)),
          ],
        ),
      ),
    );
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

  Future<void> _updateUserColor(Color? color) async {
    try {
      final payload =
          color == null ? {'renk': FieldValue.delete()} : {'renk': color.value};
      await FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(widget.userDocId)
          .update(payload);

      await fetchUserData();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            color == null ? 'Kullanıcı rengi sıfırlandı.' : 'Kullanıcı rengi güncellendi.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kullanıcı rengi güncellenemedi: $e')),
      );
    }
  }

  Widget _buildUserColorCard() {
    final selectedColor = _readColor(_userData?['renk']);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kullanıcı Rengi',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Rezervasyonlarda kullanılacak rengi seçin.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _userColorPalette.map((color) {
                final isSelected = selectedColor?.value == color.value;
                return InkWell(
                  onTap: () => _updateUserColor(color),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 18, color: Colors.black)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: selectedColor == null ? null : () => _updateUserColor(null),
                child: const Text('Otomatik'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsCard() {
    final role = (_userData?['rol'] ?? '').toString().trim();
    final normalizedRole = _normalizeRole(role);
    final isEmployee = normalizedRole == 'CALISAN';
    final isManager = normalizedRole == 'YONETICI';
    if (!isEmployee && !isManager) {
      return const SizedBox.shrink();
    }
    final currentPermissions = _readPermissions();
    final permissionKeys = isManager
        ? const <String>[
            kPermissionReceiveAllReservationNotifications,
            kPermissionReceiveAssignedReservationNotifications,
          ]
        : _permissionOrder;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Yetkiler',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              isManager
                  ? 'Yönetici için bildirim yetkilerini seçin.'
                  : 'İlgili işlemler için yetki verin.',
            ),
            const SizedBox(height: 12),
            ...permissionKeys.map((permission) {
              final label = _permissionLabels[permission] ?? permission;
              final isEnabled = currentPermissions.contains(permission);
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label),
                value: isEnabled,
                onChanged: _isSavingPermissions
                    ? null
                    : (value) {
                        final updated = Set<String>.from(currentPermissions);
                        if (value) {
                          updated.add(permission);
                        } else {
                          updated.remove(permission);
                        }
                        _updateUserPermissions(updated);
                      },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildMaasCard(Map<String, dynamic> data) {
    final kurumKodu = (data['kurumkodu'] ?? '').toString();
    if (kurumKodu.isEmpty) return const SizedBox.shrink();

    final aylikMaas = (data['aylikMaas'] as num?)?.toDouble();
    final isBaslama = data['isBaslamaTarihi'];
    DateTime? isBaslamaDate;
    if (isBaslama is Timestamp) isBaslamaDate = isBaslama.toDate();

    final fmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final dateFmt = DateFormat('dd.MM.yyyy');

    final durum = (data['durum'] ?? 'aktif').toString();
    final bool isAyrildi = durum == 'ayrildi';
    final ayrilmaTarihi = data['ayrilmaTarihi'];
    DateTime? ayrilmaDate;
    if (ayrilmaTarihi is Timestamp) ayrilmaDate = ayrilmaTarihi.toDate();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Maaş Bilgileri',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (isAyrildi) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.red.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        ayrilmaDate != null
                            ? '${DateFormat('dd.MM.yyyy').format(ayrilmaDate)} tarihinden itibaren maaş işlenmez.'
                            : 'Personel ayrıldığı için maaş işlenmez.',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _showMaasDialog(data),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Aylık Maaş',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          aylikMaas != null
                              ? fmt.format(aylikMaas)
                              : 'Tanımlanmadı',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
                ],
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _showIsBaslamaDialog(data),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('İşe Başlama Tarihi',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          isBaslamaDate != null
                              ? dateFmt.format(isBaslamaDate)
                              : 'Tanımlanmadı',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMaasDialog(Map<String, dynamic> data) async {
    final aylikMaas = (data['aylikMaas'] as num?)?.toDouble();
    final ctrl = TextEditingController(
        text: aylikMaas != null ? aylikMaas.toStringAsFixed(0) : '');
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aylık Maaş'),
        content: TextField(
          controller: ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Tutar',
            border: OutlineInputBorder(),
            suffixText: '₺',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kaydet')),
        ],
      ),
    );
    ctrl.dispose();
    if (result != true) return;
    final val = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
    if (val == null) return;
    await updateUserField('aylikMaas', val);
  }

  Future<void> _showIsBaslamaDialog(Map<String, dynamic> data) async {
    final isBaslama = data['isBaslamaTarihi'];
    DateTime initial = DateTime.now();
    if (isBaslama is Timestamp) initial = isBaslama.toDate();

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    await FirebaseFirestore.instance
        .collection('kullanicilar')
        .doc(widget.userDocId)
        .update({'isBaslamaTarihi': Timestamp.fromDate(picked)});
    await fetchUserData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('İşe başlama tarihi güncellendi.')),
    );
  }

  Widget _buildHesapOlusturCard(Map<String, dynamic> data) {
    final uid = (data['uid'] ?? '').toString().trim();
    if (uid.isNotEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_circle_outlined,
                    color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text(
                  'Giriş Hesabı Yok',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Bu personel için henüz uygulama giriş hesabı oluşturulmamış.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _showHesapOlusturDialog(),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Hesap Oluştur'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHesapOlusturDialog() async {
    final emailCtrl = TextEditingController();
    final sifreCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Giriş Hesabı Oluştur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'E-posta', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sifreCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Şifre', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Oluştur')),
        ],
      ),
    );

    final email = emailCtrl.text.trim().toLowerCase();
    final sifre = sifreCtrl.text;
    emailCtrl.dispose();
    sifreCtrl.dispose();

    if (result != true || email.isEmpty || sifre.length < 6) {
      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('E-posta girilmeli, şifre en az 6 karakter olmalı.')),
        );
      }
      return;
    }

    try {
      final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
      final uri = Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': sifre,
          'returnSecureToken': true,
        }),
      );

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw body['error']?['message'] ?? 'Bilinmeyen hata';
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final uid = decoded['localId'] as String;

      await FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(widget.userDocId)
          .update({'email': email, 'uid': uid});

      await fetchUserData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hesap oluşturuldu.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  String _currentUserDisplayName() {
    try {
      final u = Get.find<UserController>().data;
      final kisaad = (u['kisaad'] ?? '').toString().trim();
      if (kisaad.isNotEmpty) return kisaad;
      final adi = (u['adi'] ?? '').toString().trim();
      final soyadi = (u['soyadi'] ?? '').toString().trim();
      final tam = [adi, soyadi].where((s) => s.isNotEmpty).join(' ');
      if (tam.isNotEmpty) return tam;
    } catch (_) {}
    return FirebaseAuth.instance.currentUser?.email ?? 'Yönetici';
  }

  Widget _buildPersonelDetayCard(Map<String, dynamic> data) {
    final kurumKodu = (data['kurumkodu'] ?? '').toString();
    final adi = (data['adi'] ?? '').toString().trim();
    final soyadi = (data['soyadi'] ?? '').toString().trim();
    final personelAdi =
        [adi, soyadi].where((s) => s.isNotEmpty).join(' ');

    if (kurumKodu.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Personel Detayı',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('Çalışma Saatleri'),
              subtitle: const Text('Günlük çalışma saati tanımları'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CalismaSaatleriPage(
                  userId: widget.userDocId,
                  personelAdi: personelAdi,
                ),
              )),
            ),
            const Divider(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.beach_access_outlined),
              title: const Text('İzin Takibi'),
              subtitle: const Text('Yıllık, mazeret ve diğer izinler'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => IzinPage(
                  userId: widget.userDocId,
                  personelAdi: personelAdi,
                ),
              )),
            ),
            const Divider(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('Performans'),
              subtitle: const Text('Aylık işlem sayısı ve ciro'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PerformansPage(
                  userId: widget.userDocId,
                  personelAdi: personelAdi,
                ),
              )),
            ),
            const Divider(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Ödemeler'),
              subtitle: const Text('Maaş, avans ve diğer ödemeler'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PersonelOdemePage(
                  userId: widget.userDocId,
                  personelAdi: personelAdi,
                  kurumKodu: kurumKodu,
                  yapanAdi: _currentUserDisplayName(),
                ),
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPirimCard(Map<String, dynamic> data) {
    final kurumKodu = (data['kurumkodu'] ?? '').toString();
    final adi = (data['adi'] ?? '').toString().trim();
    final soyadi = (data['soyadi'] ?? '').toString().trim();
    final personelAdi = [adi, soyadi].where((s) => s.isNotEmpty).join(' ');

    if (kurumKodu.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pirim',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.percent_outlined),
              title: const Text('Pirim Tanımları'),
              subtitle: const Text('Kategori bazlı hizmet ve satış oranları'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PirimTanimlariPage(
                  userId: widget.userDocId,
                  kurumKodu: kurumKodu,
                  personelAdi: personelAdi,
                ),
              )),
            ),
            const Divider(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Aylık Pirim'),
              subtitle: const Text('Hesapla, onayla ve ödendi olarak işaretle'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AylikPirimPage(
                  userId: widget.userDocId,
                  personelAdi: personelAdi,
                  onaylayanAdi:
                      FirebaseAuth.instance.currentUser?.email ?? 'Yönetici',
                ),
              )),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _userData;
    final String? userEmail = data?['email']?.toString();
    final currentUserEmail =
        FirebaseAuth.instance.currentUser?.email?.toLowerCase();
    final bool isSelf =
        data != null && currentUserEmail == userEmail?.toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kullanıcı Profili'),
        actions: const [HomeIconButton()],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : data == null
              ? const Center(child: Text('Kullanıcı bulunamadı.'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ListView(
                    children: [
                      _buildProfileItem('Adı', 'adi', data['adi']),
                      _buildProfileItem('Soyadı', 'soyadi', data['soyadi']),
                      _buildProfileItem('Kısa Ad', 'kisaad', data['kisaad']),
                      _buildProfileItem('Email', 'email', data['email']),
                      _buildProfileItem('Rol', 'rol', data['rol']),
                      _buildProfileItem('Telefon', 'telefon', data['telefon']),
                      _buildProfileItem('Adres', 'adres', data['adres']),
                      _buildProfileItem('Ek Bilgiler', 'ekBilgiler', data['ekBilgiler']),
                      const SizedBox(height: 8),
                      _buildHesapOlusturCard(data),
                      _buildDurumCard(),
                      _buildUserColorCard(),
                      _buildPermissionsCard(),
                      _buildMaasCard(data),
                      _buildPersonelDetayCard(data),
                      _buildPirimCard(data),
                      if (isSelf) ...[
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                          ),
                          onPressed: _confirmAccountDeletion,
                          icon: const Icon(Icons.delete_forever),
                          label: const Text('Hesabımı Sil'),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  void _confirmAccountDeletion() {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hesabı Sil'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Hesabınızı silmek için lütfen şifrenizi girin.'),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Şifre',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () async {
                await _deleteCurrentAccount(passwordController.text);
              },
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteCurrentAccount(String password) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      return;
    }

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şifreyi girmelisiniz.')),
      );
      return;
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      await FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(widget.userDocId)
          .delete();

      await user.delete();

      Navigator.of(context)
        ..pop()
        ..pushNamedAndRemoveUntil('/login', (route) => false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hesabınız silindi.')),
      );
    } on FirebaseAuthException catch (e) {
      String message = 'Hesap silme başarısız: ${e.message}';
      if (e.code == 'wrong-password') {
        message = 'Şifreniz doğrulanamadı. Lütfen tekrar deneyin.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hesap silme başarısız: $e')),
      );
    }
  }

  Widget _buildDurumCard() {
    final data = _userData;
    if (data == null) return const SizedBox.shrink();

    final String? userEmail = data['email']?.toString();
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
    final bool isSelf = currentUserEmail != null && currentUserEmail == userEmail?.toLowerCase();
    if (isSelf) return const SizedBox.shrink();

    final durum = (data['durum'] ?? 'aktif').toString();
    final bool isAyrildi = durum == 'ayrildi';
    final bool isPasif = durum == 'pasif';

    Color statusColor;
    String statusLabel;
    if (isAyrildi) {
      statusColor = Colors.red;
      statusLabel = 'İşten Ayrıldı';
    } else if (isPasif) {
      statusColor = Colors.orange;
      statusLabel = 'Pasif';
    } else {
      statusColor = Colors.green;
      statusLabel = 'Aktif';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Durum',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                        color: statusColor, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (isAyrildi) ...[
              const SizedBox(height: 8),
              const Divider(height: 8),
              const SizedBox(height: 4),
              _buildAyrilmaDetay(data),
              const SizedBox(height: 8),
            ] else
              const SizedBox(height: 12),
            if (!isAyrildi) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _toggleDurum(durum),
                      icon: Icon(isPasif
                          ? Icons.play_circle_outline
                          : Icons.pause_circle_outline),
                      label: Text(isPasif ? 'Aktif Yap' : 'Pasif Yap'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isPasif ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _confirmIsctenCikar,
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('İşten Çıkar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _confirmKaliciSil,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Kalıcı Olarak Sil'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAyrilmaDetay(Map<String, dynamic> data) {
    final ayrilmaTarihi = data['ayrilmaTarihi'];
    DateTime? tarih;
    if (ayrilmaTarihi is Timestamp) tarih = ayrilmaTarihi.toDate();

    final aciklama = (data['ayrilmaAciklamasi'] ?? '').toString().trim();
    final dateFmt = DateFormat('dd.MM.yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Text(
              'Ayrılma Tarihi: ${tarih != null ? dateFmt.format(tarih) : 'Belirtilmedi'}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        if (aciklama.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.notes_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  aciklama,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _toggleDurum(String currentDurum) async {
    final newDurum = currentDurum == 'pasif' ? 'aktif' : 'pasif';
    try {
      await FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(widget.userDocId)
          .update({'durum': newDurum});
      await fetchUserData();
      if (!mounted) return;
      final label = newDurum == 'aktif' ? 'Aktif' : 'Pasif';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Durum $label olarak güncellendi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Durum güncellenemedi: $e')),
      );
    }
  }

  Future<void> _confirmIsctenCikar() async {
    DateTime ayrilmaTarihi = DateTime.now();
    final aciklamaCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('İşten Çıkar'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Personel uygulamaya erişemeyecek ve tüm yetkileri kaldırılacak.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: ayrilmaTarihi,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setDialog(() => ayrilmaTarihi = picked);
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    'Ayrılma Tarihi: ${DateFormat('dd.MM.yyyy').format(ayrilmaTarihi)}',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: aciklamaCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama (opsiyonel)',
                    border: OutlineInputBorder(),
                    hintText: 'İstifa, işten çıkarma, vb.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('İşten Çıkar'),
            ),
          ],
        ),
      ),
    );

    final aciklama = aciklamaCtrl.text.trim();
    aciklamaCtrl.dispose();

    if (result != true) return;
    await _isctenCikar(ayrilmaTarihi, aciklama);
  }

  Future<void> _isctenCikar(DateTime ayrilmaTarihi, String aciklama) async {
    try {
      await FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(widget.userDocId)
          .update({
        'durum': 'ayrildi',
        'yetkiler': <String>[],
        'siniflar': <String>[],
        'ayrilmaTarihi': Timestamp.fromDate(ayrilmaTarihi),
        if (aciklama.isNotEmpty) 'ayrilmaAciklamasi': aciklama,
      });
      await fetchUserData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personel işten çıkarıldı.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İşlem başarısız: $e')),
      );
    }
  }

  void _confirmKaliciSil() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kalıcı Olarak Sil'),
        content: const Text(
          'Bu personelin TÜM bilgileri kalıcı olarak silinecek. '
          'Bu işlem geri alınamaz. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _kaliciOlarakSil();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            child: const Text('Kalıcı Olarak Sil'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSubCollection(String subCollectionName) async {
    final collection = FirebaseFirestore.instance
        .collection('kullanicilar')
        .doc(widget.userDocId)
        .collection(subCollectionName);
    QuerySnapshot snapshot;
    do {
      snapshot = await collection.limit(100).get();
      if (snapshot.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } while (snapshot.docs.length >= 100);
  }

  Future<void> _kaliciOlarakSil() async {
    try {
      const subCollections = [
        'bildirimler',
        'pirimTanimlari',
        'pirimKayitlari',
        'izinler',
        'personelOdemeleri',
        'personelHakedisleri',
      ];
      for (final sub in subCollections) {
        await _deleteSubCollection(sub);
      }
      await FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(widget.userDocId)
          .delete();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personel kalıcı olarak silindi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silme işlemi başarısız: $e')),
      );
    }
  }

  Future<void> deleteUser(String uid, BuildContext context) async {
    try {
      await FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(uid)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcı Silindi')),
      );

      Navigator.pushReplacementNamed(context, '/kullanicilar');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kullanıcı silinirken hata oluştu: $e')),
      );
    }
  }
}
