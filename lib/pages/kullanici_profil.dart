import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:kurum_takip/utils/permission_utils.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

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

  static const Map<String, String> _fieldLabels = {
    'adi': 'Adı',
    'soyadi': 'Soyadı',
    'kisaad': 'Kısa Ad',
    'rol': 'Rol',
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
    final role = (_userData?['rol'] ?? '').toString().toUpperCase();
    if (role != 'ÇALIŞAN') {
      return const SizedBox.shrink();
    }
    final currentPermissions = _readPermissions();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Çalışan Yetkileri',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text('İlgili işlemler için yetki verin.'),
            const SizedBox(height: 12),
            ..._permissionOrder.map((permission) {
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
                      const SizedBox(height: 8),
                      _buildUserColorCard(),
                      _buildPermissionsCard(),
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
