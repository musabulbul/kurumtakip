import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import '../../controllers/institution_controller.dart';
import '../../controllers/user_controller.dart';
import '../../utils/permission_utils.dart';

class MekanlarPage extends StatefulWidget {
  const MekanlarPage({super.key});

  @override
  State<MekanlarPage> createState() => _MekanlarPageState();
}

class _MekanlarPageState extends State<MekanlarPage> {
  final UserController _user = Get.find<UserController>();
  final InstitutionController _institution = Get.find<InstitutionController>();

  final EdgeInsets _pagePadding = const EdgeInsets.symmetric(horizontal: 16);

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  List<MekanItem> _mekanlar = [];
  List<_UserOption> _users = [];

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
      _loadData();
    });
  }

  Future<void> _loadData() async {
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
      final users = await _fetchUsers(institutionId);
      final mekanlar = await _fetchMekanlar(institutionId);
      if (!mounted) {
        return;
      }
      setState(() {
        _users = users;
        _mekanlar = mekanlar;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'Mekanlar yüklenemedi: $error';
      });
    }
  }

  Future<void> _reloadMekanlar() async {
    final institutionId = _currentInstitutionId();
    if (institutionId.isEmpty) {
      return;
    }
    if (mounted) {
      setState(() {
        _errorMessage = null;
      });
    }
    try {
      final mekanlar = await _fetchMekanlar(institutionId);
      if (!mounted) {
        return;
      }
      setState(() {
        _mekanlar = mekanlar;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Mekanlar güncellenemedi: $error';
      });
    }
  }

  String _currentInstitutionId() {
    return (_institution.data['kurumkodu'] ?? '').toString();
  }

  Future<List<_UserOption>> _fetchUsers(String institutionId) async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('kullanicilar')
        .where('kurumkodu', isEqualTo: institutionId)
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

  Future<List<MekanItem>> _fetchMekanlar(String institutionId) async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('kurumlar')
        .doc(institutionId)
        .collection('mekanlar')
        .get();

    final mekanlar = querySnapshot.docs.map((doc) {
      final data = doc.data();
      return MekanItem(
        id: doc.id,
        name: (data['adi'] ?? '').toString(),
        sequence: _parseSequenceNo(data['siraNo']),
        defaultUserId: (data['defaultUserId'] ?? '').toString().isEmpty
            ? null
            : data['defaultUserId']?.toString(),
        defaultUserName: (data['defaultUserName'] ?? '').toString().isEmpty
            ? null
            : data['defaultUserName']?.toString(),
      );
    }).toList()
      ..sort(_compareMekanOrder);

    return mekanlar;
  }

  int _parseSequenceNo(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _compareMekanOrder(MekanItem first, MekanItem second) {
    final firstOrder = first.sequence > 0 ? first.sequence : 1 << 30;
    final secondOrder = second.sequence > 0 ? second.sequence : 1 << 30;
    if (firstOrder != secondOrder) {
      return firstOrder.compareTo(secondOrder);
    }
    return first.name.compareTo(second.name);
  }

  int _nextSequenceNumber() {
    var maxSequence = 0;
    for (final mekan in _mekanlar) {
      if (mekan.sequence > maxSequence) {
        maxSequence = mekan.sequence;
      }
    }
    return maxSequence + 1;
  }

  Future<void> _openMekanDialog({MekanItem? mekan}) async {
    if (_isSaving) {
      return;
    }
    final result = await _showMekanDialog(mekan: mekan);
    if (result == null) {
      return;
    }
    if (mekan == null) {
      await _createMekan(result);
    } else {
      await _updateMekan(mekan, result);
    }
  }

  Future<_MekanFormResult?> _showMekanDialog({MekanItem? mekan}) async {
    final nameController = TextEditingController(text: mekan?.name ?? '');
    final nextSequence = _nextSequenceNumber();
    final existingSequence = mekan?.sequence ?? 0;
    final initialSequence = existingSequence > 0 ? existingSequence : nextSequence;
    final sequenceController = TextEditingController(
      text: initialSequence > 0 ? initialSequence.toString() : '',
    );
    String? selectedUserId = mekan?.defaultUserId;
    if (selectedUserId != null && !_users.any((user) => user.id == selectedUserId)) {
      selectedUserId = null;
    }

    return showDialog<_MekanFormResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(mekan == null ? 'Mekan Ekle' : 'Mekan Güncelle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Mekan adı',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sequenceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Sıra no',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: selectedUserId,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Varsayılan kullanıcı atanmasın'),
                        ),
                        ..._users.map(
                          (user) => DropdownMenuItem<String?>(
                            value: user.id,
                            child: Text(user.displayName),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setModalState(() {
                          selectedUserId = value;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'Varsayılan kullanıcı',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      _showSnack('Mekan adı boş bırakılamaz.');
                      return;
                    }
                    final sequence = int.tryParse(sequenceController.text.trim()) ?? 0;
                    if (sequence <= 0) {
                      _showSnack('Sıra no 1 veya daha büyük olmalı.');
                      return;
                    }
                    final userLabel = _userLabelFor(selectedUserId);
                    Navigator.of(context).pop(
                      _MekanFormResult(
                        name: name,
                        sequence: sequence,
                        defaultUserId: selectedUserId,
                        defaultUserName: userLabel,
                      ),
                    );
                  },
                  child: Text(mekan == null ? 'Ekle' : 'Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String? _userLabelFor(String? userId) {
    if (userId == null) {
      return null;
    }
    for (final user in _users) {
      if (user.id == userId) {
        return user.shortLabel;
      }
    }
    return null;
  }

  Future<void> _createMekan(_MekanFormResult result) async {
    if (_isSaving) {
      return;
    }
    setState(() {
      _isSaving = true;
    });

    final institutionId = _currentInstitutionId();
    if (institutionId.isEmpty) {
      _showSnack('Kurum bilgisine ulaşılamadı.');
      setState(() {
        _isSaving = false;
      });
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(institutionId)
          .collection('mekanlar')
          .add({
        'adi': result.name,
        'siraNo': result.sequence,
        'defaultUserId': result.defaultUserId,
        'defaultUserName': result.defaultUserName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _reloadMekanlar();
      _showSnack('Mekan eklendi.');
    } catch (error) {
      _showSnack('Mekan eklenemedi: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _updateMekan(MekanItem mekan, _MekanFormResult result) async {
    if (_isSaving) {
      return;
    }
    setState(() {
      _isSaving = true;
    });

    final institutionId = _currentInstitutionId();
    if (institutionId.isEmpty) {
      _showSnack('Kurum bilgisine ulaşılamadı.');
      setState(() {
        _isSaving = false;
      });
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(institutionId)
          .collection('mekanlar')
          .doc(mekan.id)
          .set(
        {
          'adi': result.name,
          'siraNo': result.sequence,
          'defaultUserId': result.defaultUserId,
          'defaultUserName': result.defaultUserName,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await _reloadMekanlar();
      _showSnack('Mekan güncellendi.');
    } catch (error) {
      _showSnack('Mekan güncellenemedi: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteMekan(MekanItem mekan) async {
    if (_isSaving) {
      return;
    }
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Mekan Silinsin mi?'),
          content: Text('${mekan.name} mekanını silmek istediğinize emin misiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final institutionId = _currentInstitutionId();
    if (institutionId.isEmpty) {
      _showSnack('Kurum bilgisine ulaşılamadı.');
      setState(() {
        _isSaving = false;
      });
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(institutionId)
          .collection('mekanlar')
          .doc(mekan.id)
          .delete();
      await _reloadMekanlar();
      _showSnack('Mekan silindi.');
    } catch (error) {
      _showSnack('Mekan silinemedi: $error');
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
        title: const Text('Mekanlar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadData,
          ),
          const HomeIconButton(),
        ],
      ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _isSaving ? null : () => _openMekanDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Mekan Ekle'),
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
                onPressed: _loadData,
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    final content = _mekanlar.isEmpty ? _buildEmptyState() : _buildMekanList();

    return Column(
      children: [
        if (_isSaving) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _reloadMekanlar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _pagePadding.copyWith(top: 56, bottom: 24),
        children: const [
          Icon(Icons.meeting_room_outlined, size: 48),
          SizedBox(height: 16),
          Text(
            'Henüz mekan eklenmedi.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          Text(
            'Yeni mekan eklemek için sağ alttaki butonu kullanabilirsiniz.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMekanList() {
    return RefreshIndicator(
      onRefresh: _reloadMekanlar,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _pagePadding.copyWith(top: 16, bottom: 80),
        itemCount: _mekanlar.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final mekan = _mekanlar[index];
          final defaultUser =
              (mekan.defaultUserName ?? '').trim().isEmpty ? 'Atanmamış' : mekan.defaultUserName!;
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                child: Text(
                  mekan.sequence > 0 ? mekan.sequence.toString() : '-',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              title: Text(mekan.name.isEmpty ? 'İsimsiz Mekan' : mekan.name),
              subtitle: Text('Varsayılan kullanıcı: $defaultUser'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Güncelle',
                    onPressed: _isSaving ? null : () => _openMekanDialog(mekan: mekan),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Sil',
                    onPressed: _isSaving ? null : () => _deleteMekan(mekan),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class MekanItem {
  const MekanItem({
    required this.id,
    required this.name,
    required this.sequence,
    this.defaultUserId,
    this.defaultUserName,
  });

  final String id;
  final String name;
  final int sequence;
  final String? defaultUserId;
  final String? defaultUserName;
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

class _MekanFormResult {
  const _MekanFormResult({
    required this.name,
    required this.sequence,
    this.defaultUserId,
    this.defaultUserName,
  });

  final String name;
  final int sequence;
  final String? defaultUserId;
  final String? defaultUserName;
}
