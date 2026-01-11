import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:kurum_takip/controllers/institution_controller.dart';
import 'package:kurum_takip/utils/institution_metadata_utils.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

class UserProfilePage extends StatefulWidget {
  final String userDocId;

  const UserProfilePage({super.key, required this.userDocId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final InstitutionController _institution = Get.find<InstitutionController>();
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  static const Map<String, String> _fieldLabels = {
    'adi': 'Adı',
    'soyadi': 'Soyadı',
    'kisaad': 'Kısa Ad',
    'rol': 'Rol',
  };

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

  List<String> _normalizeClassList(dynamic value) {
    final result = <String>[];
    if (value is Iterable) {
      for (final item in value) {
        final normalized = item?.toString().trim().toUpperCase();
        if (normalized != null &&
            normalized.isNotEmpty &&
            !result.contains(normalized)) {
          result.add(normalized);
        }
      }
    } else if (value is String) {
      final normalized = value.trim().toUpperCase();
      if (normalized.isNotEmpty) {
        result.add(normalized);
      }
    }
    return result;
  }

  List<String> _availableClassSections() {
    final available = <String>{
      ...institutionClassSections(_institution)
          .map((value) => value.trim().toUpperCase())
          .where((value) => value.isNotEmpty),
    };

    final current = _normalizeClassList(_userData?['siniflar']);
    for (final entry in current) {
      if (entry != 'TÜMÜ') {
        available.add(entry);
      }
    }

    final list = available.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  String _classPermissionSummary() {
    final classes = _normalizeClassList(_userData?['siniflar']);
    if (classes.isEmpty || classes.contains('TÜMÜ')) {
      return 'Tümü';
    }
    return classes.join(', ');
  }

  void _showClassSelectionDialog() {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final availableClasses = _availableClassSections();

    if (availableClasses.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Kurum için tanımlı sınıf bulunamadı.')),
      );
      return;
    }

    final current = _normalizeClassList(_userData?['siniflar']);
    bool allowAll = current.isEmpty || current.contains('TÜMÜ');
    final selected = <String>{...current.where((item) => item != 'TÜMÜ')};

    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final listHeight = availableClasses.length > 6
                ? 280.0
                : (availableClasses.length * 48).clamp(160, 280).toDouble();

            return AlertDialog(
              title: const Text('Sınıf/Şube Yetkileri'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Varsayılan olarak Tümü seçilir. Devre dışı bırakarak şube seçebilirsiniz.'),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tümü'),
                      value: allowAll,
                      onChanged: (value) {
                        setStateDialog(() {
                          allowAll = value ?? false;
                          if (allowAll) {
                            selected.clear();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: listHeight,
                      child: Scrollbar(
                        thumbVisibility: availableClasses.length > 6,
                        child: ListView.builder(
                          itemCount: availableClasses.length,
                          itemBuilder: (context, index) {
                            final className = availableClasses[index];
                            final isChecked = selected.contains(className);
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(className),
                              value: isChecked,
                              onChanged: allowAll
                                  ? null
                                  : (value) {
                                      setStateDialog(() {
                                        if (value == true) {
                                          selected.add(className);
                                        } else {
                                          selected.remove(className);
                                        }
                                      });
                                    },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('İptal'),
                ),
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!allowAll && selected.isEmpty) {
                            scaffoldMessenger.showSnackBar(
                              const SnackBar(
                                content: Text('En az bir sınıf/şube seçmelisiniz.'),
                              ),
                            );
                            return;
                          }

                          setStateDialog(() {
                            isSaving = true;
                          });

                          final payload = allowAll
                              ? <String>['TÜMÜ']
                              : (selected.toList()..sort());

                          try {
                            await FirebaseFirestore.instance
                                .collection('kullanicilar')
                                .doc(widget.userDocId)
                                .update({'siniflar': payload});

                            await fetchUserData();
                            if (!mounted) return;

                            Navigator.of(dialogContext).pop();
                            scaffoldMessenger.showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Sınıf yetkileri güncellendi.'),
                              ),
                            );
                          } catch (e) {
                            setStateDialog(() {
                              isSaving = false;
                            });
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Sınıf yetkileri güncellenemedi: $e',
                                ),
                              ),
                            );
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
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
  }

  bool _isEditableField(String field) {
    return _fieldLabels.containsKey(field);
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

  Widget _buildClassPermissionsCard() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sınıf/Şube Yetkisi',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(_classPermissionSummary()),
            const SizedBox(height: 8),
            const Text(
              'Tümü seçiliyken şube seçimi pasiftir. İşaretini kaldırarak sınıf/şube seçebilirsiniz.',
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: _showClassSelectionDialog,
                icon: const Icon(Icons.class_),
                label: const Text('Düzenle'),
              ),
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
                      const SizedBox(height: 8),
                      _buildClassPermissionsCard(),
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
