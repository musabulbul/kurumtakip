import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kurum_takip/controllers/institution_controller.dart';
import 'package:kurum_takip/controllers/user_controller.dart';
import 'package:kurum_takip/pages/kullanici_ekle.dart';
import 'package:kurum_takip/pages/kullanici_profil.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

class Kullanicilar extends StatefulWidget {
  const Kullanicilar({Key? key}) : super(key: key);

  @override
  _KullanicilarState createState() => _KullanicilarState();
}

class _KullanicilarState extends State<Kullanicilar> {
  final UserController user = Get.find<UserController>();
  final InstitutionController kurum = Get.find<InstitutionController>();

  final TextEditingController _aramaController = TextEditingController();

  final List<Map<String, dynamic>> _aramaSonucu = [];
  final List<Map<String, dynamic>> kullanicilar = [];

  final List<String> roller = ["ROL", "YÖNETİCİ", "ÇALIŞAN", "MUHASEBE"];
  String dropDown1Value = "ROL";
  var genel = "", rol = "";
  final EdgeInsets _pagePadding = const EdgeInsets.symmetric(horizontal: 16);
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> filtre({String genel = "", String rol = ""}) {
    return kullanicilar.where((e) {
      bool matchesGenel = genel.isEmpty ||
          e["adi"].toString().toUpperCase().contains(genel.toUpperCase()) ||
          e["soyadi"].toString().toUpperCase().contains(genel.toUpperCase());
      bool matchesRol = rol.isEmpty || e["rol"].toString().toUpperCase().contains(rol.toUpperCase());
      return matchesGenel && matchesRol;
    }).toList();
  }

  void ara() {
    setState(() {
      final aramaSonucu = filtre(genel: genel, rol: rol);
      aramaSonucu.sort(
        (a, b) => a["adi"].toString().compareTo(b["adi"].toString()),
      );
      _aramaSonucu
        ..clear()
        ..addAll(aramaSonucu);
    });
  }

  Future<void> _read() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection("kullanicilar")
          .where("kurumkodu", isEqualTo: kurum.data["kurumkodu"])
          .get();

      final fetched = querySnapshot.docs.map((doc) {
        return {
          "id": doc.id,
          "uid": doc["uid"] ?? '',
          "adi": doc["adi"] ?? '',
          "soyadi": doc["soyadi"] ?? '',
          "rol": doc["rol"] ?? '',
          "kisaad": doc["kisaad"] ?? '',
          "email": doc["email"] ?? '',
        };
      }).toList();

      setState(() {
        kullanicilar
          ..clear()
          ..addAll(fetched);
        _isLoading = false;
      });
      ara();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Kullanıcılar yüklenirken bir hata oluştu: $e';
      });
    }
  }

  Future<void> _openAddUserPage() async {
    final result = await Get.to<bool>(() => const KullaniciEkle());
    if (result == true) {
      await _read();
    }
  }

  Future<void> createExcelFile() async {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];

    sheet.appendRow(['Adı', 'Soyadı', 'Rol', 'Kısa Ad', 'E-posta']);

    final rows = _aramaSonucu.isEmpty ? kullanicilar : _aramaSonucu;

    for (var row in rows) {
      sheet.appendRow([
        row['adi'],
        row['soyadi'],
        row['rol'],
        row['kisaad'],
        row['email'],
      ]);
    }

    excel.save(fileName: 'Kullanicilar.xlsx');
  }

  @override
  void initState() {
    _read();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Kullanıcı Yönetimi"),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _openAddUserPage,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: createExcelFile,
          ),
          const HomeIconButton(),
        ],
      ),
      body: Padding(
        padding: _pagePadding.copyWith(top: 16, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchCard(),
            const SizedBox(height: 16),
            _buildActionBar(),
            const SizedBox(height: 16),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _aramaController,
              textCapitalization: TextCapitalization.characters,
              onChanged: (value) {
                genel = value.isNotEmpty ? value : "";
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 26),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      genel = "";
                      rol = "";
                      dropDown1Value = "ROL";
                      _aramaController.clear();
                      ara();
                    });
                  },
                ),
                hintText: 'Kullanıcı ara...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: dropDown1Value,
              decoration: InputDecoration(
                labelText: 'Rol',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: roller
                  .map(
                    (value) => DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    ),
                  )
                  .toList(),
              onChanged: (girilenDeger) {
                if (girilenDeger == null) return;
                setState(() {
                  dropDown1Value = girilenDeger;
                  rol = girilenDeger != "ROL" ? girilenDeger : "";
                });
                ara();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ElevatedButton.icon(
          onPressed: ara,
          icon: const Icon(Icons.search),
          label: const Text('Ara'),
        ),
        Chip(label: Text('Bulunan: ${_aramaSonucu.length}')),
        OutlinedButton(
          onPressed: () {
            setState(() {
              genel = "";
              rol = "";
              dropDown1Value = "ROL";
              _aramaController.clear();
              ara();
            });
          },
          child: const Text('Filtreleri Temizle'),
        ),
        OutlinedButton.icon(
          onPressed: createExcelFile,
          icon: const Icon(Icons.download),
          label: const Text('Excel İndir'),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    if (_aramaSonucu.isEmpty) {
      return _buildEmptyState();
    }

    return _buildResultsList();
  }

  Widget _buildResultsList() {
    return ListView.separated(
      itemCount: _aramaSonucu.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _aramaSonucu[index];
        final initials = _getInitials(item['adi'], item['soyadi']);

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(initials),
            ),
            title: Text(
              "${item['adi']} ${item['soyadi']}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(item['email']),
            trailing: Chip(label: Text(item['rol'] ?? '')),
            onTap: () {
              Get.to(() => UserProfilePage(userDocId: item["id"]));
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.groups_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text(
            'Kriterlere uygun kullanıcı bulunamadı.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              _openAddUserPage();
            },
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Yeni Kullanıcı Ekle'),
          ),
        ],
      ),
    );
  }

  String _getInitials(String? adi, String? soyadi) {
    final first = (adi ?? '').isNotEmpty ? adi!.trim()[0] : '';
    final last = (soyadi ?? '').isNotEmpty ? soyadi!.trim()[0] : '';
    final initials = '$first$last'.trim();
    return initials.isEmpty ? '?' : initials.toUpperCase();
  }

  @override
  void dispose() {
    _aramaController.dispose();
    super.dispose();
  }
}
