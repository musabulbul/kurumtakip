import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import '../../controllers/institution_controller.dart';
import '../../controllers/user_controller.dart';
import '../../services/sms_service.dart';
import '../../utils/permission_utils.dart';

class MesajlarPage extends StatefulWidget {
  const MesajlarPage({super.key});

  @override
  State<MesajlarPage> createState() => _MesajlarPageState();
}

class _MesajlarPageState extends State<MesajlarPage> {
  final UserController _user = Get.find<UserController>();
  final InstitutionController _institution = Get.find<InstitutionController>();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  String _creditLabel = '-';
  bool _hasSmsProvider = false;
  final SmsService _smsService = SmsService();

  final TextEditingController _reservationSalutationController =
      TextEditingController(text: 'Sevgili');
  String _reservationNameFormat = 'first';
  bool _reservationIncludeOperation = true;
  final TextEditingController _reservationBodyController =
      TextEditingController(text: 'randevunuz oluşturulmuştur. Sağlıklı günler dileriz.');

  bool _reminderEnabled = true;
  final TextEditingController _reminderHoursController =
      TextEditingController(text: '1');
  final TextEditingController _reminderSalutationController =
      TextEditingController(text: 'Sevgili');
  String _reminderNameFormat = 'first';
  bool _reminderIncludeOperation = true;
  final TextEditingController _reminderBodyController =
      TextEditingController(text: 'randevunuzu hatırlatırız.');
  TimeOfDay _reminderStartTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _reminderEndTime = const TimeOfDay(hour: 21, minute: 0);

  bool _birthdayEnabled = false;
  TimeOfDay _birthdaySendTime = const TimeOfDay(hour: 9, minute: 0);
  final TextEditingController _birthdaySalutationController =
      TextEditingController(text: 'Sevgili');
  String _birthdayNameFormat = 'first';
  final TextEditingController _birthdayBodyController =
      TextEditingController(text: 'doğum gününüzü kutlar, sağlıklı ve mutlu yıllar dileriz.');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!isManagerUser(_user.data)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu sayfaya sadece yöneticiler erişebilir.'),
          ),
        );
        Navigator.of(context).maybePop();
        return;
      }
      _loadSettings();
    });
  }

  @override
  void dispose() {
    _reservationSalutationController.dispose();
    _reservationBodyController.dispose();
    _reminderHoursController.dispose();
    _reminderSalutationController.dispose();
    _reminderBodyController.dispose();
    _birthdaySalutationController.dispose();
    _birthdayBodyController.dispose();
    super.dispose();
  }

  String _currentInstitutionId() {
    return (_institution.data['kurumkodu'] ?? '').toString();
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {};
  }

  int _parseInt(dynamic value, int fallback) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int _timeToMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  TimeOfDay _timeFromMinutes(int minutes) {
    final normalized = minutes % (24 * 60);
    return TimeOfDay(hour: normalized ~/ 60, minute: normalized % 60);
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final institutionId = _currentInstitutionId();
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
      if (!mounted) return;

      final data = doc.data() ?? <String, dynamic>{};
      final creditValue = data['smsCredit'] ?? data['smsKredi'] ?? data['smsBalance'];
      _creditLabel = creditValue == null ? '-' : creditValue.toString();
      final providerId = (data['smsProviderId'] ?? '').toString().trim();
      _hasSmsProvider = providerId.isNotEmpty;
      final userInfoResult = await _smsService.fetchUserInformation(
        kurumId: institutionId,
        providerId: providerId.isEmpty ? null : providerId,
      );
      if (userInfoResult.success) {
        final refreshedCredit = _extractCreditFromRaw(userInfoResult.rawResponse);
        if (refreshedCredit != null) {
          _creditLabel = refreshedCredit;
        }
      }

      final settings = _asMap(data['settings']);
      final messageSettings = _asMap(settings['messageSettings']);

      final reservation = _asMap(messageSettings['reservation']);
      _reservationSalutationController.text =
          (reservation['salutation'] ?? 'Sevgili').toString();
      _reservationNameFormat =
          (reservation['nameFormat'] ?? 'first').toString();
      _reservationIncludeOperation = reservation['includeOperation'] != false;
      _reservationBodyController.text =
          (reservation['body'] ??
                  'randevunuz oluşturulmuştur. Sağlıklı günler dileriz.')
              .toString();

      final reminder = _asMap(messageSettings['reminder']);
      _reminderEnabled = reminder['enabled'] != false;
      _reminderHoursController.text =
          _parseInt(reminder['hoursBefore'], 1).toString();
      _reminderSalutationController.text =
          (reminder['salutation'] ?? 'Sevgili').toString();
      _reminderNameFormat =
          (reminder['nameFormat'] ?? 'first').toString();
      _reminderIncludeOperation = reminder['includeOperation'] != false;
      _reminderBodyController.text =
          (reminder['body'] ?? 'randevunuzu hatırlatırız.').toString();
      final reminderWindow = _asMap(reminder['sendWindow']);
      _reminderStartTime =
          _timeFromMinutes(_parseInt(reminderWindow['startMinutes'], 9 * 60));
      _reminderEndTime =
          _timeFromMinutes(_parseInt(reminderWindow['endMinutes'], 21 * 60));

      final birthday = _asMap(messageSettings['birthday']);
      _birthdayEnabled = birthday['enabled'] == true;
      _birthdaySendTime = _timeFromMinutes(
        _parseInt(birthday['sendTimeMinutes'], 9 * 60),
      );
      _birthdaySalutationController.text =
          (birthday['salutation'] ?? 'Sevgili').toString();
      _birthdayNameFormat =
          (birthday['nameFormat'] ?? 'first').toString();
      _birthdayBodyController.text =
          (birthday['body'] ??
                  'doğum gününüzü kutlar, sağlıklı ve mutlu yıllar dileriz.')
              .toString();

      setState(() {
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ayarlar yüklenemedi: $error';
      });
    }
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;

    final institutionId = _currentInstitutionId();
    if (institutionId.isEmpty) {
      _showSnack('Kurum bilgisine ulaşılamadı.');
      return;
    }

    final hoursBefore = _parseInt(_reminderHoursController.text.trim(), 1);
    if (hoursBefore <= 0) {
      _showSnack('Hatırlatma saati 1 veya daha büyük olmalı.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final messageSettings = {
      'reservation': {
        'salutation': _reservationSalutationController.text.trim().isEmpty
            ? 'Sevgili'
            : _reservationSalutationController.text.trim(),
        'nameFormat': _reservationNameFormat,
        'includeOperation': _reservationIncludeOperation,
        'body': _reservationBodyController.text.trim().isEmpty
            ? 'randevunuz oluşturulmuştur. Sağlıklı günler dileriz.'
            : _reservationBodyController.text.trim(),
      },
      'reminder': {
        'enabled': _reminderEnabled,
        'hoursBefore': hoursBefore,
        'salutation': _reminderSalutationController.text.trim().isEmpty
            ? 'Sevgili'
            : _reminderSalutationController.text.trim(),
        'nameFormat': _reminderNameFormat,
        'includeOperation': _reminderIncludeOperation,
        'body': _reminderBodyController.text.trim().isEmpty
            ? 'randevunuzu hatırlatırız.'
            : _reminderBodyController.text.trim(),
        'sendWindow': {
          'startMinutes': _timeToMinutes(_reminderStartTime),
          'endMinutes': _timeToMinutes(_reminderEndTime),
        },
      },
      'birthday': {
        'enabled': _birthdayEnabled,
        'sendTimeMinutes': _timeToMinutes(_birthdaySendTime),
        'salutation': _birthdaySalutationController.text.trim().isEmpty
            ? 'Sevgili'
            : _birthdaySalutationController.text.trim(),
        'nameFormat': _birthdayNameFormat,
        'body': _birthdayBodyController.text.trim().isEmpty
            ? 'doğum gününüzü kutlar, sağlıklı ve mutlu yıllar dileriz.'
            : _birthdayBodyController.text.trim(),
      },
    };

    try {
      await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(institutionId)
          .set(
        {
          'settings': {
            'messageSettings': messageSettings,
          },
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      _showSnack('Mesaj ayarları kaydedildi.');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Kaydetme başarısız: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _handleCreditTap() async {
    final institutionId = _currentInstitutionId().trim();
    if (institutionId.isEmpty) {
      _showSnack('Kurum bilgisine ulaşılamadı.');
      return;
    }

    final providerId = (_institution.data['smsProviderId'] ?? '').toString().trim();
    final result = await _smsService.fetchUserInformation(
      kurumId: institutionId,
      providerId: providerId.isEmpty ? null : providerId,
    );

    debugPrint('[mesajlar_page] sms user info success=${result.success}');
    debugPrint('[mesajlar_page] sms user info message=${result.message}');
    debugPrint('[mesajlar_page] sms user info raw=${result.rawResponse}');
    if (result.success) {
      final refreshedCredit = _extractCreditFromRaw(result.rawResponse);
      if (refreshedCredit != null && mounted) {
        setState(() {
          _creditLabel = refreshedCredit;
        });
      }
    }

    if (!mounted) return;
    _showSnack(result.message);
  }

  String? _extractCreditFromRaw(Map<String, dynamic>? raw) {
    if (raw == null) {
      return null;
    }
    final data = _asMap(raw['data']);
    final dynamic value = data['credit'] ??
        raw['credit'] ??
        data['smsCredit'] ??
        data['smsKredi'] ??
        data['smsBalance'];
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value % 1 == 0 ? value.toInt().toString() : value.toString();
    }
    final parsed = double.tryParse(value.toString().replaceAll(',', '.'));
    if (parsed == null) {
      return value.toString();
    }
    return parsed % 1 == 0 ? parsed.toInt().toString() : parsed.toString();
  }

  Future<void> _pickReminderStartTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _reminderStartTime,
    );
    if (selected == null) return;
    setState(() {
      _reminderStartTime = selected;
    });
  }

  Future<void> _pickReminderEndTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _reminderEndTime,
    );
    if (selected == null) return;
    setState(() {
      _reminderEndTime = selected;
    });
  }

  Future<void> _pickBirthdaySendTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _birthdaySendTime,
    );
    if (selected == null) return;
    setState(() {
      _birthdaySendTime = selected;
    });
  }

  Widget _buildSmsProviderWarning() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sms_failed_outlined, size: 18, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 13, color: cs.onErrorContainer),
                children: const [
                  TextSpan(
                    text: 'SMS sağlayıcınız mevcut değildir. '
                        'SMS gönderebilmek için temsilcinizle iletişime geçiniz.\n',
                  ),
                  TextSpan(
                    text: 'mebssoftware@gmail.com',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _buildNameFormatSelector({
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      children: [
        RadioListTile<String>(
          value: 'first',
          groupValue: value,
          onChanged: (val) => onChanged(val ?? 'first'),
          title: const Text('İlk ad'),
        ),
        RadioListTile<String>(
          value: 'full',
          groupValue: value,
          onChanged: (val) => onChanged(val ?? 'full'),
          title: const Text('Tam ad'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesaj Ayarları'),
        actions: [
          const HomeIconButton(),
          IconButton(
            onPressed: _isSaving ? null : _saveSettings,
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Kaydet',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (!_hasSmsProvider) ...[
                      _buildSmsProviderWarning(),
                      const SizedBox(height: 16),
                    ],
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.sms_outlined),
                        title: const Text('Mesaj Kredisi'),
                        subtitle: Text(_creditLabel),
                        onTap: _handleCreditTap,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('Randevu Bilgisi Şablonu'),
                            TextField(
                              controller: _reservationSalutationController,
                              decoration: const InputDecoration(
                                labelText: 'Hitap',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildNameFormatSelector(
                              value: _reservationNameFormat,
                              onChanged: (value) {
                                setState(() {
                                  _reservationNameFormat = value;
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            const Text('Tarih/Saat: 12.02.2026 tarihinde saat 14:30 için'),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _reservationIncludeOperation,
                              onChanged: (value) {
                                setState(() {
                                  _reservationIncludeOperation = value;
                                });
                              },
                              title: const Text('İşlem adı eklensin'),
                            ),
                            TextField(
                              controller: _reservationBodyController,
                              decoration: const InputDecoration(
                                labelText: 'Mesaj metni',
                                border: OutlineInputBorder(),
                              ),
                              minLines: 2,
                              maxLines: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('Randevu Hatırlatma'),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _reminderEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _reminderEnabled = value;
                                });
                              },
                              title: const Text('Randevu hatırlatma mesajı gönder'),
                            ),
                            TextField(
                              controller: _reminderHoursController,
                              decoration: const InputDecoration(
                                labelText: 'Kaç saat önce',
                                border: OutlineInputBorder(),
                                suffixText: 'saat',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 12),
                            _buildSectionTitle('Hatırlatma Şablonu'),
                            TextField(
                              controller: _reminderSalutationController,
                              decoration: const InputDecoration(
                                labelText: 'Hitap',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildNameFormatSelector(
                              value: _reminderNameFormat,
                              onChanged: (value) {
                                setState(() {
                                  _reminderNameFormat = value;
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            const Text('Tarih/Saat: 12.02.2026 tarihinde saat 14:30 için'),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _reminderIncludeOperation,
                              onChanged: (value) {
                                setState(() {
                                  _reminderIncludeOperation = value;
                                });
                              },
                              title: const Text('İşlem adı eklensin'),
                            ),
                            TextField(
                              controller: _reminderBodyController,
                              decoration: const InputDecoration(
                                labelText: 'Mesaj metni',
                                border: OutlineInputBorder(),
                              ),
                              minLines: 2,
                              maxLines: 4,
                            ),
                            const SizedBox(height: 12),
                            _buildSectionTitle('Gönderim Saat Aralığı'),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _pickReminderStartTime,
                                    child: Text(
                                      'Başlangıç: ${_reminderStartTime.format(context)}',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _pickReminderEndTime,
                                    child: Text(
                                      'Bitiş: ${_reminderEndTime.format(context)}',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('Doğum Günü Mesajı'),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _birthdayEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _birthdayEnabled = value;
                                });
                              },
                              title: const Text('Doğum günü mesajı gönder'),
                            ),
                            OutlinedButton(
                              onPressed: _pickBirthdaySendTime,
                              child: Text(
                                'Gönderim Saati: ${_birthdaySendTime.format(context)}',
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildSectionTitle('Doğum Günü Şablonu'),
                            TextField(
                              controller: _birthdaySalutationController,
                              decoration: const InputDecoration(
                                labelText: 'Hitap',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildNameFormatSelector(
                              value: _birthdayNameFormat,
                              onChanged: (value) {
                                setState(() {
                                  _birthdayNameFormat = value;
                                });
                              },
                            ),
                            TextField(
                              controller: _birthdayBodyController,
                              decoration: const InputDecoration(
                                labelText: 'Mesaj metni',
                                border: OutlineInputBorder(),
                              ),
                              minLines: 2,
                              maxLines: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveSettings,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Kaydet'),
                    ),
                  ],
                ),
    );
  }
}
