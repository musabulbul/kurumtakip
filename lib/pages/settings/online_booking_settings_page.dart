import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import '../../controllers/institution_controller.dart';
import '../../controllers/user_controller.dart';
import '../../utils/permission_utils.dart';

class OnlineBookingSettingsPage extends StatefulWidget {
  const OnlineBookingSettingsPage({super.key});

  @override
  State<OnlineBookingSettingsPage> createState() => _OnlineBookingSettingsPageState();
}

class _OnlineBookingSettingsPageState extends State<OnlineBookingSettingsPage> {
  final UserController _user = Get.find<UserController>();
  final InstitutionController _institution = Get.find<InstitutionController>();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  bool _bookingEnabled = false;
  String _authMode = 'phone_birthdate';
  bool _showServicePrices = false;
  bool _showAccountStatement = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!isManagerUser(_user.data)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu sayfaya sadece yöneticiler erişebilir.')),
        );
        Navigator.of(context).maybePop();
        return;
      }
      _load();
    });
  }

  String _institutionId() => (_institution.data['kurumkodu'] ?? '').toString();

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final institutionId = _institutionId();
    if (institutionId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Kurum bilgisine ulaşılamadı.';
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(institutionId)
          .get();
      final data = doc.data() ?? <String, dynamic>{};
      final settings = _asMap(data['settings']);
      final onlineBooking = _asMap(settings['onlineBooking']);

      _bookingEnabled = data['bookingEnabled'] == true;
      _authMode = (onlineBooking['authMode'] as String?) == 'otp'
          ? 'otp'
          : 'phone_birthdate';
      _showServicePrices = onlineBooking['showServicePrices'] == true;
      _showAccountStatement = onlineBooking['showAccountStatement'] == true;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ayarlar yüklenemedi: $e';
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final institutionId = _institutionId();
    if (institutionId.isEmpty) {
      _showSnack('Kurum bilgisine ulaşılamadı.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(institutionId)
          .set(
        {
          'bookingEnabled': _bookingEnabled,
          'settings': {
            'onlineBooking': {
              'enabled': _bookingEnabled,
              'authMode': _authMode,
              'showServicePrices': _showServicePrices,
              'showAccountStatement': _showAccountStatement,
            },
          },
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      _showSnack('Online randevu ayarları kaydedildi.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Kaydetme başarısız: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Online Randevu Ayarları'),
        actions: const [HomeIconButton()],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Online randevu aktif'),
                      value: _bookingEnabled,
                      onChanged: (value) => setState(() => _bookingEnabled = value),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Giriş doğrulama yöntemi'),
                            const SizedBox(height: 8),
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: 'otp',
                              groupValue: _authMode,
                              title: const Text('OTP (telefon + kod)'),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _authMode = value);
                              },
                            ),
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: 'phone_birthdate',
                              groupValue: _authMode,
                              title: const Text('OTP yok (telefon + doğum tarihi)'),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _authMode = value);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Danışanlar hizmet fiyatlarını görebilsin'),
                      value: _showServicePrices,
                      onChanged: (value) => setState(() => _showServicePrices = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Danışanlar hesap ekstresini görebilsin'),
                      value: _showAccountStatement,
                      onChanged: (value) => setState(() => _showAccountStatement = value),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Kaydet'),
                    ),
                  ],
                ),
    );
  }
}
