import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../controllers/institution_controller.dart';
import '../controllers/user_controller.dart';

class InstitutionSwitchResult {
  final bool reset;
  final String? institutionName;
  final String? role;

  InstitutionSwitchResult({
    this.reset = false,
    this.institutionName,
    this.role,
  });
}

Future<InstitutionSwitchResult?> showInstitutionSwitchDialog({
  required BuildContext context,
  required UserController userController,
  required InstitutionController institutionController,
}) {
  return showDialog<InstitutionSwitchResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return _InstitutionSwitchDialog(
        userController: userController,
        institutionController: institutionController,
      );
    },
  );
}

class _InstitutionSwitchDialog extends StatefulWidget {
  final UserController userController;
  final InstitutionController institutionController;

  const _InstitutionSwitchDialog({
    required this.userController,
    required this.institutionController,
  });

  @override
  State<_InstitutionSwitchDialog> createState() =>
      _InstitutionSwitchDialogState();
}

class _InstitutionSwitchDialogState extends State<_InstitutionSwitchDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, String>> _institutions = [];
  List<String> _roles = [];
  String? _selectedInstitutionId;
  String? _selectedInstitutionName;
  String? _selectedRole;
  bool _loadingInstitutions = true;
  bool _loadingRoles = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInstitutions();
  }

  Future<void> _loadInstitutions() async {
    setState(() {
      _loadingInstitutions = true;
      _error = null;
    });

    try {
      final snapshot = await _firestore
          .collection('kurumlar')
          .orderBy('kurumadi')
          .get();

      final items = snapshot.docs.map((doc) {
        final data = doc.data();
        final kurumAdi = (data['kurumadi'] ?? doc.id).toString();
        final kisaAd = (data['kisaad'] ?? '').toString();
        return {
          'id': doc.id,
          'displayName':
              kisaAd.isNotEmpty ? '$kurumAdi ($kisaAd)' : kurumAdi,
          'kurumAdi': kurumAdi,
        };
      }).toList();

      setState(() {
        _institutions = items;
        _loadingInstitutions = false;
      });
    } catch (e) {
      setState(() {
        _loadingInstitutions = false;
        _error = 'Kurumlar yüklenirken hata oluştu: $e';
      });
    }
  }

  Future<void> _loadRoles(String institutionId) async {
    setState(() {
      _loadingRoles = true;
      _roles = [];
      _selectedRole = null;
      _error = null;
    });

    try {
      final query = await _firestore
          .collection('kullanicilar')
          .where('kurumkodu', isEqualTo: institutionId)
          .get();

      final rolesSet = query.docs
          .map((doc) => doc.data()['rol'])
          .whereType<String>()
          .map((role) => role.toUpperCase())
          .toSet();

      rolesSet.addAll(const ['YÖNETİCİ', 'ÇALIŞAN', 'MUHASEBE']);

      final roles = rolesSet.toList()..sort();

      setState(() {
        _roles = roles;
      });
    } catch (e) {
      setState(() {
        _error = 'Roller yüklenirken hata oluştu: $e';
      });
    } finally {
      setState(() {
        _loadingRoles = false;
      });
    }
  }

  bool get _canSubmit =>
      !_loadingInstitutions &&
      !_loadingRoles &&
      !_submitting &&
      _selectedInstitutionId != null &&
      _selectedRole != null;

  Future<void> _submit() async {
    if (!_canSubmit) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.institutionController
          .switchInstitution(_selectedInstitutionId!);
      widget.userController.impersonate(
        role: _selectedRole!,
        institutionId: _selectedInstitutionId!,
      );

      if (mounted) {
        Navigator.pop(
          context,
          InstitutionSwitchResult(
            reset: false,
            institutionName: _selectedInstitutionName,
            role: _selectedRole,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Geçiş sırasında hata oluştu: $e';
        _submitting = false;
      });
    }
  }

  void _resetToOriginal() {
    widget.userController.clearImpersonation();
    widget.institutionController.clearImpersonation();
    Navigator.pop(
      context,
      InstitutionSwitchResult(reset: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kurum Değiştir'),
      content: SizedBox(
        width: 420,
        child: _loadingInstitutions
            ? const Center(child: CircularProgressIndicator())
            : _institutions.isEmpty
                ? const Center(child: Text('Kayıtlı kurum bulunamadı.'))
                : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedInstitutionId,
                      decoration: const InputDecoration(
                        labelText: 'Kurum Seç',
                        border: OutlineInputBorder(),
                      ),
                      isExpanded: true,
                      menuMaxHeight: 320,
                      items: _institutions
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item['id'],
                              child: Text(item['displayName'] ?? item['id']!),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedInstitutionId = value;
                          if (value != null) {
                            final match = _institutions.where(
                              (element) => element['id'] == value,
                            );
                            _selectedInstitutionName = match.isNotEmpty
                                ? match.first['kurumAdi']
                                : value;
                          } else {
                            _selectedInstitutionName = null;
                          }
                        });
                        if (value != null) {
                          _loadRoles(value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    _loadingRoles
                        ? const Center(child: CircularProgressIndicator())
                        : DropdownButtonFormField<String>(
                            value: _selectedRole,
                            decoration: const InputDecoration(
                              labelText: 'Rol Seç',
                              border: OutlineInputBorder(),
                            ),
                            isExpanded: true,
                            menuMaxHeight: 260,
                            items: _roles
                                .map(
                                  (role) => DropdownMenuItem<String>(
                                    value: role,
                                    child: Text(role),
                                  ),
                                )
                                .toList(),
                            onChanged: _roles.isEmpty
                                ? null
                                : (value) {
                                    setState(() {
                                      _selectedRole = value;
                                    });
                                  },
                          ),
                    const SizedBox(height: 12),
                    if (_error != null)
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
        TextButton(
          onPressed: _submitting ? null : _resetToOriginal,
          child: const Text('Varsayılan Kullanıcıya Dön'),
        ),
        ElevatedButton(
          onPressed: _canSubmit ? _submit : null,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Geçiş Yap'),
        ),
      ],
    );
  }
}
