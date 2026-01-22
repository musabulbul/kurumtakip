import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import '../../controllers/institution_controller.dart';
import '../../controllers/user_controller.dart';
import '../../utils/permission_utils.dart';

class SaatlerPage extends StatefulWidget {
  const SaatlerPage({super.key});

  @override
  State<SaatlerPage> createState() => _SaatlerPageState();
}

class _SaatlerPageState extends State<SaatlerPage> {
  final UserController _user = Get.find<UserController>();
  final InstitutionController _institution = Get.find<InstitutionController>();

  final EdgeInsets _pagePadding = const EdgeInsets.symmetric(horizontal: 16);

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  final Set<String> _selectedDays = {};
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 18, minute: 0);
  int _intervalMinutes = 30;
  bool _endNextDay = false;

  static const List<_DayOption> _dayOptions = [
    _DayOption(key: 'mon', label: 'Pazartesi'),
    _DayOption(key: 'tue', label: 'Salı'),
    _DayOption(key: 'wed', label: 'Çarşamba'),
    _DayOption(key: 'thu', label: 'Perşembe'),
    _DayOption(key: 'fri', label: 'Cuma'),
    _DayOption(key: 'sat', label: 'Cumartesi'),
    _DayOption(key: 'sun', label: 'Pazar'),
  ];

  static const List<int> _intervalOptions = [15, 20, 30, 45, 60];

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
      if (!mounted) {
        return;
      }

      final data = doc.data() ?? <String, dynamic>{};
      final settings = _asMap(data['settings']);
      final sessionHours = _asMap(settings['sessionHours']);

      _selectedDays
        ..clear()
        ..addAll(sessionHours.keys.map((key) => key.toString()));

      if (sessionHours.isNotEmpty) {
        final firstEntry = sessionHours.values.first;
        final values = _asMap(firstEntry);
        final hasStartMinutes = values.containsKey('startMinutes');
        final hasEndMinutes = values.containsKey('endMinutes');
        final startMinutes = _parseMinutes(values['startMinutes']);
        final endMinutes = _parseMinutes(values['endMinutes']);
        final intervalMinutes = _parseMinutes(values['intervalMinutes']);
        final endNextDay = values['endNextDay'] == true;
        final normalizedEndMinutes = endMinutes % (24 * 60);

        if (hasStartMinutes) {
          _startTime = _timeFromMinutes(startMinutes);
        }
        if (hasEndMinutes) {
          _endTime = _timeFromMinutes(normalizedEndMinutes);
        }
        if (intervalMinutes > 0) {
          _intervalMinutes = intervalMinutes;
        }
        _endNextDay = endNextDay || endMinutes >= 24 * 60;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'Saatler yüklenemedi: $error';
      });
    }
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

  String _currentInstitutionId() {
    return (_institution.data['kurumkodu'] ?? '').toString();
  }

  int _parseMinutes(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _timeToMinutes(TimeOfDay time) {
    return time.hour * 60 + time.minute;
  }

  TimeOfDay _timeFromMinutes(int minutes) {
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  Future<void> _pickStartTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (selected == null) {
      return;
    }
    setState(() {
      _startTime = selected;
    });
  }

  Future<void> _pickEndTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (selected == null) {
      return;
    }
    setState(() {
      _endTime = selected;
    });
  }

  Future<void> _saveSettings() async {
    if (_isSaving) {
      return;
    }

    if (_selectedDays.isEmpty) {
      _showSnack('Lütfen en az bir gün seçin.');
      return;
    }

    final startMinutes = _timeToMinutes(_startTime);
    final rawEndMinutes = _timeToMinutes(_endTime);
    final endMinutes =
        _endNextDay ? rawEndMinutes + 24 * 60 : rawEndMinutes;

    if (!_endNextDay && endMinutes <= startMinutes) {
      _showSnack('Bitiş saati başlangıç saatinden sonra olmalı.');
      return;
    }

    if (endMinutes - startMinutes < _intervalMinutes) {
      _showSnack('Seans aralığı için yeterli zaman yok.');
      return;
    }

    final institutionId = _currentInstitutionId();
    if (institutionId.isEmpty) {
      _showSnack('Kurum bilgisine ulaşılamadı.');
      return;
    }

    final sessionHours = <String, dynamic>{};
    for (final day in _selectedDays) {
      sessionHours[day] = {
        'startMinutes': startMinutes,
        'endMinutes': rawEndMinutes,
        'intervalMinutes': _intervalMinutes,
        'endNextDay': _endNextDay,
      };
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
          'settings': {
            'sessionHours': sessionHours,
          },
        },
        SetOptions(merge: true),
      );
      final updated = Map<String, dynamic>.from(_institution.data);
      final settings = _asMap(updated['settings']);
      settings['sessionHours'] = sessionHours;
      updated['settings'] = settings;
      _institution.data.value = updated;
      _showSnack('Saatler güncellendi.');
    } catch (error) {
      _showSnack('Saatler güncellenemedi: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saatler'),
        actions: const [HomeIconButton()],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: _pagePadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loadSettings,
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: _pagePadding.copyWith(top: 16, bottom: 24),
      children: [
        if (_isSaving) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        Text(
          'Seans günleri',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _dayOptions.map((day) {
            final isSelected = _selectedDays.contains(day.key);
            return FilterChip(
              label: Text(day.label),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedDays.add(day.key);
                  } else {
                    _selectedDays.remove(day.key);
                  }
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        Text(
          'Seans saatleri',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.play_arrow_outlined),
                title: const Text('İlk seans başlangıcı'),
                subtitle: Text(_formatTime(_startTime)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickStartTime,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.stop_outlined),
                title: const Text('Son seans bitişi'),
                subtitle: Text(_formatTime(_endTime)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickEndTime,
              ),
              SwitchListTile(
                value: _endNextDay,
                onChanged: (value) {
                  setState(() {
                    _endNextDay = value;
                  });
                },
                title: const Text('Bitiş ertesi gün'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<int>(
              value: _intervalMinutes,
              decoration: const InputDecoration(
                labelText: 'Seans süresi',
                border: OutlineInputBorder(),
              ),
              items: _intervalOptions
                  .map(
                    (minutes) => DropdownMenuItem<int>(
                      value: minutes,
                      child: Text('$minutes dk'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _intervalMinutes = value;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveSettings,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Saatleri Kaydet'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  String _formatTime(TimeOfDay time) {
    return MaterialLocalizations.of(context).formatTimeOfDay(time);
  }
}

class _DayOption {
  const _DayOption({
    required this.key,
    required this.label,
  });

  final String key;
  final String label;
}
