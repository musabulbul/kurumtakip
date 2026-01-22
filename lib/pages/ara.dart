import 'dart:async';
import 'dart:io' show exit;

import 'package:characters/characters.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import 'package:kurum_takip/controllers/institution_controller.dart';
import 'package:kurum_takip/controllers/user_controller.dart';

import 'package:kurum_takip/pages/kullanicilar.dart';
import 'package:kurum_takip/pages/kurumlar.dart';
import 'package:kurum_takip/widgets/institution_switch_dialog.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import 'danisan_ekle.dart';
import 'danisan_profil.dart';
import '../utils/phone_utils.dart';
import '../utils/student_utils.dart';
import '../utils/permission_utils.dart';
import '../utils/text_utils.dart';
import 'settings/admin_settings_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class Ara extends SearchPage {
  const Ara({super.key});
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _aramaController = TextEditingController();
  final RxList<Map<dynamic, dynamic>> _aramaSonucu = <Map<dynamic, dynamic>>[].obs;
  RxList<Map<dynamic, dynamic>> danisanlar = <Map<dynamic, dynamic>>[].obs;
  final RxString _searchQuery = ''.obs;
  UserController user = Get.find<UserController>();
  InstitutionController kurum = Get.find<InstitutionController>();
  Worker? _institutionWatcher;
  String? _listeningInstitutionId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _mekanSubscription;

  DateTime _selectedDay = DateUtils.dateOnly(DateTime.now());
  final List<String> _fallbackLocations = const [
    'Mekan1',
    'Mekan2',
    'Mekan3',
    'Mekan4',
    'Mekan5',
  ];
  List<String> _locations = [];

  final EdgeInsets _pagePadding = const EdgeInsets.symmetric(horizontal: 16);

  void filtre(String kelime) {
    final query = normalizeTr(kelime);
    _aramaSonucu.value = danisanlar
        .where((e) {
          final name = normalizeTr((e['adi'] ?? '').toString());
          final surname = normalizeTr((e['soyadi'] ?? '').toString());
          final phone = normalizeTr(_resolvePhone(e));
          return name.contains(query) || surname.contains(query) || phone.contains(query);
        })
        .toList()
      ..sort((a, b) => (a['adi'] ?? '').toString().compareTo((b['adi'] ?? '').toString()));
  }

  String _resolvePhone(Map<dynamic, dynamic> data) {
    final phone = normalizePhone((data['telefon'] ?? '').toString());
    if (phone.isNotEmpty) {
      return phone;
    }
    return normalizePhone((data['ogrencitel'] ?? '').toString());
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _studentsSubscription;

  void _listenToFirestoreChanges() {
    final kurumkodu = kurum.data["kurumkodu"]?.toString();
    if (kurumkodu == null || kurumkodu.isEmpty) {
      return;
    }
    _listeningInstitutionId = kurumkodu;
    final studentsRef = FirebaseFirestore.instance
        .collection("kurumlar")
        .doc(kurumkodu)
        .collection("danisanlar");

    _studentsSubscription = studentsRef.snapshots().listen((snapshot) {
      final updatedStudents = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data["id"] = doc.id;

        final rawNo = data["no"];
        if (rawNo is! int) {
          data["no"] = int.tryParse(rawNo?.toString() ?? "0") ?? 0;
        }

        return data;
      }).toList();

      updatedStudents.sort((a, b) {
        final nameA = (a['adi'] ?? '').toString();
        final nameB = (b['adi'] ?? '').toString();
        return nameA.compareTo(nameB);
      });

      danisanlar.assignAll(updatedStudents);

      if (_aramaController.text.isNotEmpty) {
        filtre(_aramaController.text);
      }
    });
  }

  void _listenToMekanChanges() {
    final kurumkodu = kurum.data["kurumkodu"]?.toString();
    if (kurumkodu == null || kurumkodu.isEmpty) {
      return;
    }
    _listeningInstitutionId = kurumkodu;
    final mekanRef = FirebaseFirestore.instance
        .collection("kurumlar")
        .doc(kurumkodu)
        .collection("mekanlar");

    _mekanSubscription = mekanRef.snapshots().listen((snapshot) {
      final mekanlar = snapshot.docs
          .map((doc) {
            final data = Map<String, dynamic>.from(doc.data());
            final name = (data['adi'] ?? '').toString().trim();
            final sequence = _parseSequenceNo(data['siraNo']);
            return _MekanLocation(name: name, sequence: sequence);
          })
          .where((mekan) => mekan.name.isNotEmpty)
          .toList()
        ..sort(_compareMekanLocations);

      if (!mounted) {
        return;
      }
      setState(() {
        _locations = mekanlar.map((mekan) => mekan.name).toList();
      });
    });
  }
  @override
  void initState() {
    super.initState();
    danisanlar.clear();
    _listenToFirestoreChanges();
    _listenToMekanChanges();
    _institutionWatcher = ever(kurum.data, (_) {
      final yeniKurumKodu = kurum.data["kurumkodu"]?.toString();
      if (yeniKurumKodu == null || yeniKurumKodu.isEmpty) {
        return;
      }
      if (yeniKurumKodu == _listeningInstitutionId) {
        return;
      }
      _studentsSubscription?.cancel();
      _mekanSubscription?.cancel();
      _listenToFirestoreChanges();
      _listenToMekanChanges();
    });
  }

  @override
  void dispose() {
    _studentsSubscription?.cancel();
    _mekanSubscription?.cancel();
    _aramaController.dispose();
    _institutionWatcher?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _confirmExitOnBack,
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() {
            // If data is not available, show a placeholder or empty string
            return Column(
              children: [
                const Text(
                  'Mebs Kurum Takip',
                  style: TextStyle(fontSize: 20),
                ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("${kurum.data['kisaad'] ?? ''}"),
            Text(
                      "${user.data['kisaad'] ?? ''}",
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ],
            );
          }),
          actions: const [HomeIconButton()],
        ),
        body: Column(
          children: [
            Padding(
              padding: _pagePadding.copyWith(top: 4, bottom: 8),
              child: _buildSearchField(),
            ),
            Expanded(
              child: Obx(() {
                if (!_canSearchStudents) {
                  return _buildReservationSection();
                }
                final query = _searchQuery.value.trim();
                if (query.isEmpty) {
                  return _buildReservationSection();
                }
                if (_aramaSonucu.isEmpty) {
                  return _buildSearchEmptyState();
                }
                return _buildResultList();
              }),
            ),
          ],
        ),
        drawer: Drawer(
          child: ListView(
            padding: const EdgeInsets.all(0.0),
            children: <Widget>[
              UserAccountsDrawerHeader(
                accountName: Text("${user.data["adi"]} ${user.data["soyadi"]}"),
                accountEmail: Text("${user.data["email"]}"),
                currentAccountPicture: const CircleAvatar(
                  backgroundImage: AssetImage("assets/images/profile.png"),
                  radius: 50.0,
                ),
                decoration: BoxDecoration(color: Colors.red[400]),
              ),
              const ListTile(
                title: Text("Profilim"),
                // onTap: () => Navigator.push(...),
              ),
              if (user.data["rol"] == "YÖNETİCİ")
                ListTile(
                  title: const Text("Kullanıcılar"),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const Kullanicilar(),
                      ),
                    );
                  },
                ),
              if (user.data['ustyonetici']?.toString().toLowerCase() == 'admin')
                ListTile(
                  title: const Text('Kurumlar'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const KurumlarPage(),
                      ),
                    );
                  },
                ),
              if (user.data['ustyonetici']?.toString().toLowerCase() == 'admin')
                ListTile(
                  title: const Text('Kurum Değiştir'),
                  onTap: () async {
                    Navigator.pop(context);
                    final result = await showInstitutionSwitchDialog(
                      context: context,
                      userController: user,
                      institutionController: kurum,
                    );
                    if (!mounted || result == null) {
                      return;
                    }
                    final message = result.reset
                        ? 'Varsayılan kurum ve role dönüldü.'
                        : '${result.institutionName ?? ''} kurumunda ${result.role ?? ''} rolüyle devam ediyorsunuz.';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message.trim())),
                    );
                  },
                ),
              if (isManagerUser(user.data))
                ListTile(
                  title: const Text("Ayarlar"),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AdminSettingsPage(),
                      ),
                    );
                  },
                ),
              ListTile(
                title: const Text('Şifre Değiştir'),
                onTap: () async {
                  Navigator.pop(context);
                  await _showChangePasswordDialog();
                },
              ),
              ListTile(
                title: const Text("Çıkış Yap"),
                onTap: () async {
                  Navigator.pop(context);
                  await _performLogout();
                },
              ),
              ListTile(
                title: const Text("Kapat"),
                onTap: () async {
                  Navigator.pop(context);
                  await _requestAppExit();
                },
              ),
          ],
        ),
      ),
    ),
    );
  }

  Future<void> _requestAppExit() async {
    final shouldExit = await _showExitConfirmationDialog();
    if (!shouldExit) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Web sürümünde uygulamayı kapatmak için sekmeyi kapatın.'),
        ),
      );
      return;
    }
    if (GetPlatform.isIOS || GetPlatform.isMacOS) {
      exit(0);
      return;
    }
    SystemNavigator.pop();
  }

  Future<void> _performLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Çıkış yapılırken bir sorun oluştu. Lütfen tekrar deneyin.'),
        ),
      );
      return;
    }

    danisanlar.clear();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
  }

  Future<bool> _confirmExitOnBack() async {
    final query = _searchQuery.value.trim();
    if (query.isNotEmpty) {
      _aramaController.clear();
      _aramaSonucu.clear();
      _searchQuery.value = '';
      if (mounted) {
        FocusScope.of(context).unfocus();
      }
      return false;
    }
    return await _showExitConfirmationDialog();
  }

  Future<bool> _showExitConfirmationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Çıkış Onayı'),
          content: const Text('Uygulamadan çıkmak istediğinize emin misiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Hayır'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Evet'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _openDanisanEklePage() async {
    if (!mounted) {
      return;
    }
    FocusScope.of(context).unfocus();
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DanisanEklePage()),
    );
    if (!mounted || result == null || result is! String || result.trim().isEmpty) {
      return;
    }
    final newStudentId = result.trim();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DanisanProfil(id: newStudentId),
      ),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Danışan kaydedildi.')),
    );
  }

  void _showInstitutionMissingSnackBar() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
    );
  }

  bool get _isManager =>
      (user.data['rol'] ?? '').toString().toUpperCase() == 'YÖNETİCİ';

  bool get _canSearchStudents => canSearchStudents(user.data);

  bool get _canViewContactInfo => canViewContactInfo(user.data);

  bool get _canViewAllReservations => canViewAllReservations(user.data);

  String _currentUserId() {
    return (user.data['email'] ?? user.data['uid'] ?? '').toString();
  }

  String _currentInstitutionId() {
    return (kurum.data['kurumkodu'] ?? '').toString();
  }

  void _updateSelectedDay(DateTime day) {
    setState(() {
      _selectedDay = DateUtils.dateOnly(day);
    });
  }

  int _parseSequenceNo(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _compareMekanLocations(_MekanLocation first, _MekanLocation second) {
    final firstOrder = first.sequence > 0 ? first.sequence : 1 << 30;
    final secondOrder = second.sequence > 0 ? second.sequence : 1 << 30;
    if (firstOrder != secondOrder) {
      return firstOrder.compareTo(secondOrder);
    }
    return first.name.compareTo(second.name);
  }

  List<String> get _resolvedLocations =>
      _locations.isEmpty ? _fallbackLocations : _locations;

  void _handleReservationTap(Reservation reservation) {
    if (!mounted) {
      return;
    }
    if (reservation.customerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Müşteri bilgisi bulunamadı.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DanisanProfil(id: reservation.customerId),
      ),
    );
  }

  Widget _buildReservationSection() {
    final kurumkodu = (kurum.data["kurumkodu"] ?? '').toString();
    if (kurumkodu.isEmpty) {
      return const Center(child: Text('Rezervasyon tablosu yüklenemedi.'));
    }
    final sessionHours =
        _asMap(_asMap(kurum.data['settings'])['sessionHours']);
    final sessionConfig = _resolveSessionHours(sessionHours, _selectedDay);
    final dayStart = DateUtils.dateOnly(_selectedDay);
    final dayEnd = dayStart.add(Duration(minutes: sessionConfig.endMinutes));
    Query<Map<String, dynamic>> reservationsQuery = FirebaseFirestore.instance
        .collection("kurumlar")
        .doc(kurumkodu)
        .collection('rezervasyonlar')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .where('date', isLessThan: Timestamp.fromDate(dayEnd));
    if (!_canViewAllReservations) {
      final currentUserId = _currentUserId();
      reservationsQuery = reservationsQuery.where(
        'assignedUserId',
        isEqualTo: currentUserId.isNotEmpty ? currentUserId : '__none__',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: _pagePadding.copyWith(top: 8, bottom: 8),
          child: Text(
            'Rezervasyon Tablosu',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: _pagePadding.copyWith(bottom: 16),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: reservationsQuery.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Rezervasyonlar yüklenemedi.'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final reservations = snapshot.data!.docs
                    .map((doc) => Reservation.fromSnapshot(doc))
                    .toList();
                final reservationIds = reservations.map((entry) => entry.id).toSet();
                final completedStream = FirebaseFirestore.instance
                    .collectionGroup('islemler')
                    .snapshots();
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: completedStream,
                  builder: (context, completedSnapshot) {
                    final completedByReservation = completedSnapshot.hasData
                        ? _extractCompletedOperationKeys(
                            completedSnapshot.data!.docs,
                            reservationIds,
                          )
                        : <String, Set<String>>{};
                    return ReservationGrid(
                      selectedDay: _selectedDay,
                      locations: _resolvedLocations,
                      reservations: reservations,
                      completedByReservation: completedByReservation,
                      sessionHours: sessionHours,
                      onDayChanged: _updateSelectedDay,
                      onReservationTap: _handleReservationTap,
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    if (!_canSearchStudents) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Text(
          'Danışan arama yetkiniz bulunmuyor.',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    }
    final searchField = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        textCapitalization: TextCapitalization.characters,
        controller: _aramaController,
        onChanged: (girilenDeger) {
          _searchQuery.value = girilenDeger;
          if (girilenDeger.trim().isNotEmpty) {
            filtre(girilenDeger);
          } else {
            _aramaSonucu.clear();
          }
        },
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 28),
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _aramaController.clear();
              _searchQuery.value = '';
              _aramaSonucu.clear();
            },
          ),
          hintText: 'Danışan ara...',
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        ),
      ),
    );

    if (!_isManager) {
      return searchField;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: searchField),
        const SizedBox(width: 12),
        _buildAddButton(),
      ],
    );
  }

  Widget _buildAddButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _openDanisanEklePage,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Ekle'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildResultList() {
    return ListView.builder(
      padding: _pagePadding.copyWith(bottom: 24),
      itemCount: _aramaSonucu.length,
      itemBuilder: (context, index) {
        final danisan = _aramaSonucu[index];
        final adi = (danisan["adi"] ?? '').toString();
        final soyadi = (danisan["soyadi"] ?? '').toString();
        final phone = _canViewContactInfo ? _resolvePhone(danisan) : '';
        final initials = [adi, soyadi]
            .where((part) => part.isNotEmpty)
            .map((part) => part.characters.first.toUpperCase())
            .join()
            .padRight(2, '?')
            .substring(0, 2);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            onTap: () {
              final id = resolveStudentId(danisan);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DanisanProfil(id: id.toString()),
                ),
              );
            },
            leading: CircleAvatar(
              backgroundColor: Colors.purple.shade100,
              child: Text(initials),
            ),
            title: Text(
              "$adi $soyadi".trim().isEmpty ? 'İsimsiz Danışan' : "$adi $soyadi",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(phone.isEmpty ? '-' : phone),
            trailing: phone.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.call, color: Colors.green),
                    onPressed: () => _launchDialer(phone),
                  ),
          ),
        );
      },
    );
  }

  Future<void> _launchDialer(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await launcher.canLaunchUrl(uri)) {
      await launcher.launchUrl(uri);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null || authUser.email == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanıcı bilgisi bulunamadı.')),
        );
      }
      return;
    }

    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool isSaving = false;
        bool obscureCurrent = true;
        bool obscureNew = true;
        bool obscureConfirm = true;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Şifre Değiştir'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: currentPasswordController,
                      obscureText: obscureCurrent,
                      decoration: InputDecoration(
                        labelText: 'Mevcut şifre',
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureCurrent ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscureCurrent = !obscureCurrent;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newPasswordController,
                      obscureText: obscureNew,
                      decoration: InputDecoration(
                        labelText: 'Yeni şifre',
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureNew ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscureNew = !obscureNew;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'Yeni şifre (tekrar)',
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureConfirm ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscureConfirm = !obscureConfirm;
                            });
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
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final currentPassword =
                              currentPasswordController.text.trim();
                          final newPassword =
                              newPasswordController.text.trim();
                          final confirmPassword =
                              confirmPasswordController.text.trim();

                          if (currentPassword.isEmpty ||
                              newPassword.isEmpty ||
                              confirmPassword.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Lütfen tüm alanları doldurun.'),
                              ),
                            );
                            return;
                          }
                          if (newPassword.length < 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Şifre en az 6 karakter olmalıdır.'),
                              ),
                            );
                            return;
                          }
                          if (newPassword != confirmPassword) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Yeni şifreler eşleşmiyor.'),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                          });

                          try {
                            final credential = EmailAuthProvider.credential(
                              email: authUser.email!,
                              password: currentPassword,
                            );
                            await authUser.reauthenticateWithCredential(credential);
                            await authUser.updatePassword(newPassword);
                            if (!mounted || !dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Şifre güncellendi.')),
                            );
                          } on FirebaseAuthException catch (e) {
                            String message = 'Şifre güncellenemedi: ${e.message}';
                            if (e.code == 'wrong-password') {
                              message = 'Mevcut şifre yanlış.';
                            } else if (e.code == 'weak-password') {
                              message = 'Şifre en az 6 karakter olmalıdır.';
                            } else if (e.code == 'requires-recent-login') {
                              message = 'Lütfen yeniden giriş yapın.';
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(message)),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Şifre güncellenemedi: $e')),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                isSaving = false;
                              });
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Güncelle'),
                ),
              ],
            );
          },
        );
      },
    );

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  Widget _buildSearchEmptyState() {
    return ListView(
      padding: _pagePadding.copyWith(top: 24, bottom: 32),
      children: [
        Text(
          'Arama sonucu bulunamadı.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text('Farklı bir isim veya telefon numarası deneyebilirsiniz.'),
      ],
    );
  }
}

class Reservation {
  const Reservation({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.location,
    required this.startMinutes,
    required this.endMinutes,
    required this.customerShortName,
    required this.assignedUserId,
    required this.assignedUserColor,
    required this.operations,
  });

  final String id;
  final String customerId;
  final String customerName;
  final String location;
  final int startMinutes;
  final int endMinutes;
  final String customerShortName;
  final String? assignedUserId;
  final Color? assignedUserColor;
  final List<_ReservationOperation> operations;

  factory Reservation.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final date = _readTimestamp(data['date']);
    final startMinutes = _readInt(data['startMinutes']) ??
        (date != null ? date.hour * 60 + date.minute : 0);
    final endMinutes = _readInt(data['endMinutes']) ?? startMinutes + _slotDurationMinutes;
    final customerName = (data['customerName'] ?? '').toString().trim();
    final rawShortName = (data['customerShortName'] ?? '').toString().trim();
    final derivedShortName = customerName.isNotEmpty
        ? _buildShortNameFromFullName(customerName)
        : '';
    final resolvedShortName = derivedShortName.isNotEmpty && derivedShortName != '-'
        ? derivedShortName
        : (rawShortName.isNotEmpty ? rawShortName : '-');
    var assignedUserId = (data['assignedUserId'] ?? '').toString().trim();
    if (assignedUserId.isEmpty) {
      final rawOperations = data['operations'];
      if (rawOperations is List) {
        for (final item in rawOperations) {
          if (item is Map) {
            final fallbackId = (item['assignedUserId'] ?? '').toString().trim();
            if (fallbackId.isNotEmpty) {
              assignedUserId = fallbackId;
              break;
            }
          }
        }
      }
    }
    final assignedUserName = (data['assignedUserName'] ?? '').toString().trim();
    final assignedUserColor = _readColor(data['assignedUserColor']) ??
        (assignedUserId.isNotEmpty
            ? _resolveUserColor(assignedUserId)
            : (assignedUserName.isNotEmpty ? _resolveUserColor(assignedUserName) : null));
    final operations = _extractReservationOperations(data);
    return Reservation(
      id: snapshot.id,
      customerId: (data['customerId'] ?? '').toString().trim(),
      customerName: customerName,
      location: (data['locationName'] ?? '').toString().trim(),
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      customerShortName: resolvedShortName,
      assignedUserId: assignedUserId.isNotEmpty ? assignedUserId : null,
      assignedUserColor: assignedUserColor,
      operations: operations,
    );
  }
}

class _ReservationOperation {
  const _ReservationOperation({
    required this.operationId,
    required this.operationName,
  });

  final String operationId;
  final String operationName;
}

List<_ReservationOperation> _extractReservationOperations(
  Map<String, dynamic> data,
) {
  final operations = <_ReservationOperation>[];
  final rawOperations = data['operations'];
  if (rawOperations is List) {
    for (final item in rawOperations) {
      if (item is Map) {
        final opId = (item['operationId'] ?? '').toString().trim();
        final opName = (item['operationName'] ?? '').toString().trim();
        if (opId.isNotEmpty || opName.isNotEmpty) {
          operations.add(
            _ReservationOperation(operationId: opId, operationName: opName),
          );
        }
      }
    }
  }
  if (operations.isEmpty) {
    final opId = (data['operationId'] ?? '').toString().trim();
    final opName = (data['operationName'] ?? '').toString().trim();
    if (opId.isNotEmpty || opName.isNotEmpty) {
      operations.add(
        _ReservationOperation(operationId: opId, operationName: opName),
      );
    }
  }
  return operations;
}

class _MekanLocation {
  const _MekanLocation({
    required this.name,
    required this.sequence,
  });

  final String name;
  final int sequence;
}

class TimeSlot {
  const TimeSlot({
    required this.time,
    required this.startMinutes,
  });

  final TimeOfDay time;
  final int startMinutes;
}

class _SessionHoursConfig {
  const _SessionHoursConfig({
    required this.startMinutes,
    required this.endMinutes,
    required this.intervalMinutes,
  });

  final int startMinutes;
  final int endMinutes;
  final int intervalMinutes;
}

const int _slotDurationMinutes = 30;

List<TimeSlot> buildTimeSlots({
  int startMinutes = 9 * 60,
  int endMinutes = 20 * 60,
  int intervalMinutes = _slotDurationMinutes,
}) {
  final slots = <TimeSlot>[];
  final safeInterval = intervalMinutes > 0 ? intervalMinutes : _slotDurationMinutes;
  var minutes = startMinutes;
  final safeEnd =
      endMinutes > startMinutes ? endMinutes : startMinutes + safeInterval;
  while (minutes < safeEnd) {
    final normalizedMinutes = minutes % (24 * 60);
    slots.add(
      TimeSlot(
        time: TimeOfDay(
          hour: normalizedMinutes ~/ 60,
          minute: normalizedMinutes % 60,
        ),
        startMinutes: minutes,
      ),
    );
    minutes += safeInterval;
  }
  return slots;
}

String formatTimeLabel(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

Map<String, Reservation> buildReservationLookup(
  List<Reservation> reservations, {
  required int intervalMinutes,
}) {
  final lookup = <String, Reservation>{};
  final step = intervalMinutes > 0 ? intervalMinutes : _slotDurationMinutes;
  for (final reservation in reservations) {
    final endMinutes = reservation.endMinutes > reservation.startMinutes
        ? reservation.endMinutes
        : reservation.startMinutes + step;
    for (var slot = reservation.startMinutes;
        slot < endMinutes;
        slot += step) {
      lookup[_reservationKey(reservation.location, slot)] = reservation;
    }
  }
  return lookup;
}

String _weekdayKey(DateTime day) {
  switch (day.weekday) {
    case DateTime.monday:
      return 'mon';
    case DateTime.tuesday:
      return 'tue';
    case DateTime.wednesday:
      return 'wed';
    case DateTime.thursday:
      return 'thu';
    case DateTime.friday:
      return 'fri';
    case DateTime.saturday:
      return 'sat';
    case DateTime.sunday:
      return 'sun';
  }
  return 'mon';
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

_SessionHoursConfig _resolveSessionHours(
  Map<String, dynamic> sessionHours,
  DateTime day,
) {
  final dayConfig = _asMap(sessionHours[_weekdayKey(day)]);
  final startMinutes = _readInt(dayConfig['startMinutes']) ?? 9 * 60;
  final rawEndMinutes = _readInt(dayConfig['endMinutes']) ?? 20 * 60;
  final intervalMinutes = _readInt(dayConfig['intervalMinutes']) ?? _slotDurationMinutes;
  final endNextDay =
      dayConfig['endNextDay'] == true || rawEndMinutes >= 24 * 60;
  final endMinutes =
      endNextDay ? rawEndMinutes + 24 * 60 : rawEndMinutes;
  final safeInterval = intervalMinutes > 0 ? intervalMinutes : _slotDurationMinutes;
  if (endMinutes <= startMinutes) {
    return _SessionHoursConfig(
      startMinutes: 9 * 60,
      endMinutes: 20 * 60,
      intervalMinutes: _slotDurationMinutes,
    );
  }
  return _SessionHoursConfig(
    startMinutes: startMinutes,
    endMinutes: endMinutes,
    intervalMinutes: safeInterval,
  );
}

String _reservationKey(String location, int slotStartMinutes) {
  return '$location-$slotStartMinutes';
}

bool _isSameReservationOwner(Reservation first, Reservation second) {
  final firstKey = first.customerId.isNotEmpty ? first.customerId : first.id;
  final secondKey = second.customerId.isNotEmpty ? second.customerId : second.id;
  return firstKey == secondKey;
}

const List<Color> _userColorPalette = [
  Color(0xFFB3E5FC),
  Color(0xFFC8E6C9),
  Color(0xFFFFF9C4),
  Color(0xFFFFCCBC),
  Color(0xFFD1C4E9),
  Color(0xFFFFE0B2),
  Color(0xFFB2DFDB),
  Color(0xFFFFDDE6),
];

Color _resolveUserColor(String userId) {
  if (userId.isEmpty) {
    return const Color(0xFFE0E0E0);
  }
  final index = userId.hashCode.abs() % _userColorPalette.length;
  return _userColorPalette[index];
}

DateTime? _readTimestamp(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}

int? _readInt(dynamic value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '');
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

Color _resolveForegroundColor(Color background, Color fallback) {
  final brightness = ThemeData.estimateBrightnessForColor(background);
  return brightness == Brightness.dark ? Colors.white : fallback;
}

String _buildShortNameFromFullName(String fullName) {
  final parts =
      fullName.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) {
    return '-';
  }
  final firstWord = parts.first;
  final lastInitial =
      parts.length > 1 ? parts.last.substring(0, 1).toUpperCase() : '';
  if (lastInitial.isEmpty) {
    return firstWord;
  }
  return '$firstWord $lastInitial';
}

class ReservationGrid extends StatefulWidget {
  const ReservationGrid({
    super.key,
    required this.selectedDay,
    required this.locations,
    required this.reservations,
    required this.completedByReservation,
    required this.sessionHours,
    required this.onDayChanged,
    required this.onReservationTap,
  });

  final DateTime selectedDay;
  final List<String> locations;
  final List<Reservation> reservations;
  final Map<String, Set<String>> completedByReservation;
  final Map<String, dynamic> sessionHours;
  final ValueChanged<DateTime> onDayChanged;
  final ValueChanged<Reservation> onReservationTap;

  static const double _timeColumnWidth = 72;
  static const double _locationColumnWidth = 112;
  static const double _headerHeight = 44;
  static const double _rowHeight = 44;

  @override
  State<ReservationGrid> createState() => _ReservationGridState();
}

class _ReservationGridState extends State<ReservationGrid> {
  late final ScrollController _headerHorizontalController;
  late final ScrollController _bodyHorizontalController;

  @override
  void initState() {
    super.initState();
    _headerHorizontalController = ScrollController();
    _bodyHorizontalController = ScrollController();
    _bodyHorizontalController.addListener(_syncHeaderScroll);
  }

  @override
  void dispose() {
    _bodyHorizontalController.removeListener(_syncHeaderScroll);
    _bodyHorizontalController.dispose();
    _headerHorizontalController.dispose();
    super.dispose();
  }

  void _syncHeaderScroll() {
    if (!_headerHorizontalController.hasClients) {
      return;
    }
    _headerHorizontalController.jumpTo(_bodyHorizontalController.offset);
  }

  @override
  Widget build(BuildContext context) {
    final sessionConfig =
        _resolveSessionHours(widget.sessionHours, widget.selectedDay);
    final slots = buildTimeSlots(
      startMinutes: sessionConfig.startMinutes,
      endMinutes: sessionConfig.endMinutes,
      intervalMinutes: sessionConfig.intervalMinutes,
    );
    final theme = Theme.of(context);
    final reservationLookup = buildReservationLookup(
      widget.reservations,
      intervalMinutes: sessionConfig.intervalMinutes,
    );
    final borderColor = theme.colorScheme.outlineVariant.withOpacity(0.6);

    return Column(
      children: [
        _buildDateBar(context),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, _) {
              return Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildHeaderRow(context, borderColor),
                    Divider(
                      height: 1,
                      thickness: 0.6,
                      color: borderColor,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTimeColumn(context, slots, borderColor),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                controller: _bodyHorizontalController,
                                child: SizedBox(
                                  width: widget.locations.length *
                                      ReservationGrid._locationColumnWidth,
                                      child: Column(
                                        children: slots
                                            .map(
                                              (slot) => _buildLocationRow(
                                            context,
                                            slot,
                                            reservationLookup,
                                            sessionConfig.intervalMinutes,
                                            borderColor,
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDateBar(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant.withOpacity(0.6);
    final label = DateFormat('dd.MM.yyyy').format(widget.selectedDay);
    final dayLabel = DateFormat('EEEE', 'tr_TR').format(widget.selectedDay);
    final today = DateUtils.dateOnly(DateTime.now());
    final tomorrow = DateUtils.dateOnly(today.add(const Duration(days: 1)));
    String? daySuffix;
    if (DateUtils.isSameDay(widget.selectedDay, today)) {
      daySuffix = 'Bugün';
    } else if (DateUtils.isSameDay(widget.selectedDay, tomorrow)) {
      daySuffix = 'Yarın';
    }
    final dayLine = daySuffix == null ? dayLabel : '$dayLabel ($daySuffix)';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Önceki gün',
            onPressed: () => widget.onDayChanged(
              widget.selectedDay.subtract(const Duration(days: 1)),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dayLine,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Sonraki gün',
            onPressed: () => widget.onDayChanged(
              widget.selectedDay.add(const Duration(days: 1)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Tarih seç',
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: widget.selectedDay,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                widget.onDayChanged(DateUtils.dateOnly(picked));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context, Color borderColor) {
    final theme = Theme.of(context);
    return SizedBox(
      height: ReservationGrid._headerHeight,
      child: Row(
        children: [
          Container(
            width: ReservationGrid._timeColumnWidth,
            height: ReservationGrid._headerHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              border: Border(
                right: BorderSide(color: borderColor, width: 0.6),
              ),
            ),
            child: Text(
              'Saat',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _headerHorizontalController,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: widget.locations.length *
                    ReservationGrid._locationColumnWidth,
                child: Row(
                  children: widget.locations
                      .map(
                        (location) => Container(
                          width: ReservationGrid._locationColumnWidth,
                          height: ReservationGrid._headerHeight,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant,
                            border: Border(
                              right: BorderSide(color: borderColor, width: 0.6),
                            ),
                          ),
                          child: Text(
                            location,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeColumn(
    BuildContext context,
    List<TimeSlot> slots,
    Color borderColor,
  ) {
    final theme = Theme.of(context);
    return Column(
      children: slots
          .map(
            (slot) => Container(
              width: ReservationGrid._timeColumnWidth,
              height: ReservationGrid._rowHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  right: BorderSide(color: borderColor, width: 0.6),
                  bottom: BorderSide(color: borderColor, width: 0.6),
                ),
              ),
              child: Text(
                formatTimeLabel(slot.time),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildLocationRow(
    BuildContext context,
    TimeSlot slot,
    Map<String, Reservation> reservationLookup,
    int intervalMinutes,
    Color borderColor,
  ) {
    return SizedBox(
      height: ReservationGrid._rowHeight,
      child: Row(
        children: widget.locations.map((location) {
          final reservation =
              reservationLookup[_reservationKey(location, slot.startMinutes)];
          final step =
              intervalMinutes > 0 ? intervalMinutes : _slotDurationMinutes;
          final prevSlotStart = slot.startMinutes - step;
          final prevReservation =
              reservationLookup[_reservationKey(location, prevSlotStart)];
          final nextSlotStart = slot.startMinutes + step;
          final nextReservation =
              reservationLookup[_reservationKey(location, nextSlotStart)];
          final sameAsPrev = reservation != null &&
              prevReservation != null &&
              _isSameReservationOwner(prevReservation, reservation);
          final sameAsNext = reservation != null &&
              nextReservation != null &&
              _isSameReservationOwner(nextReservation, reservation);
          final isStart = reservation != null && !sameAsPrev;
          final isEnd = reservation != null && !sameAsNext;
          return _buildReservationCell(
            context: context,
            reservation: reservation,
            isStart: isStart,
            isEnd: isEnd,
            showLabel: reservation != null,
            borderColor: borderColor,
            completedByReservation: widget.completedByReservation,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildReservationCell({
    required BuildContext context,
    required Reservation? reservation,
    required bool isStart,
    required bool isEnd,
    required bool showLabel,
    required Color borderColor,
    required Map<String, Set<String>> completedByReservation,
  }) {
    final theme = Theme.of(context);
    final baseCellColor = Color.lerp(
          theme.colorScheme.surface,
          theme.colorScheme.surfaceVariant,
          0.12,
        ) ??
        theme.colorScheme.surface;
    final reservationColor =
        reservation?.assignedUserColor ?? theme.colorScheme.surfaceVariant;
    final isCompleted = reservation != null &&
        _isReservationCompleted(reservation, completedByReservation);
    final effectiveCellColor = reservation == null
        ? baseCellColor
        : reservationColor.withOpacity(isCompleted ? 0.12 : 0.2);
    final labelColor = reservation?.assignedUserColor != null
        ? _resolveForegroundColor(reservationColor, theme.colorScheme.onSurface)
        : theme.colorScheme.onSurface;
    final displayName = reservation == null
        ? ''
        : (reservation.customerName.isNotEmpty
            ? reservation.customerName
            : reservation.customerShortName);
    final labelText = showLabel ? displayName : '';
    final cardRadius = reservation == null
        ? BorderRadius.circular(8)
        : isStart && isEnd
            ? BorderRadius.circular(8)
            : isStart
                ? const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                    bottomLeft: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  )
                : isEnd
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(2),
                        topRight: Radius.circular(2),
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      )
                    : BorderRadius.circular(2);
    final showShadow = reservation != null && (isStart || isEnd);
    final bottomBorderColor =
        reservation != null && !isEnd ? Colors.transparent : borderColor;
    return SizedBox(
      width: ReservationGrid._locationColumnWidth,
      height: ReservationGrid._rowHeight,
      child: Material(
        color: effectiveCellColor,
        child: InkWell(
          onTap:
              reservation == null ? null : () => widget.onReservationTap(reservation),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: borderColor, width: 0.6),
                bottom: BorderSide(color: bottomBorderColor, width: 0.6),
              ),
            ),
            child: reservation == null
                ? const SizedBox.shrink()
                : SizedBox.expand(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? reservationColor.withOpacity(0.4)
                            : reservationColor,
                        borderRadius: cardRadius,
                        boxShadow: showShadow
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : const [],
                      ),
                      child: Center(
                        child: Text(
                          labelText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight:
                                isCompleted ? FontWeight.w500 : FontWeight.w700,
                            color: isCompleted
                                ? labelColor.withOpacity(0.6)
                                : labelColor,
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

Map<String, Set<String>> _extractCompletedOperationKeys(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  Set<String> reservationIds,
) {
  final result = <String, Set<String>>{};
  for (final doc in docs) {
    final data = doc.data();
    final reservationId = (data['reservationId'] ?? '').toString().trim();
    if (reservationId.isEmpty || !reservationIds.contains(reservationId)) {
      continue;
    }
    final operationId = (data['operationId'] ?? '').toString().trim();
    final operationName = (data['operationName'] ?? '').toString().trim();
    final keys = result.putIfAbsent(reservationId, () => <String>{});
    if (operationId.isNotEmpty) {
      keys.add('id:$operationId');
    }
    if (operationName.isNotEmpty) {
      keys.add('name:$operationName');
    }
  }
  return result;
}

bool _isOperationCompleted(
  _ReservationOperation operation,
  Set<String> completedKeys,
) {
  if (operation.operationId.isNotEmpty &&
      completedKeys.contains('id:${operation.operationId}')) {
    return true;
  }
  if (operation.operationName.isNotEmpty &&
      completedKeys.contains('name:${operation.operationName}')) {
    return true;
  }
  return false;
}

bool _isReservationCompleted(
  Reservation reservation,
  Map<String, Set<String>> completedByReservation,
) {
  if (reservation.operations.isEmpty) {
    return false;
  }
  final completedKeys = completedByReservation[reservation.id];
  if (completedKeys == null || completedKeys.isEmpty) {
    return false;
  }
  for (final operation in reservation.operations) {
    if (!_isOperationCompleted(operation, completedKeys)) {
      return false;
    }
  }
  return true;
}
