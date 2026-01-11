import 'dart:async';

import 'package:characters/characters.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../controllers/institution_controller.dart';
import '../utils/phone_utils.dart';
import '../utils/student_utils.dart';
import '../widgets/home_icon_button.dart';
import 'danisan_profil.dart';

class DetayliAra extends StatefulWidget {
  const DetayliAra({super.key});

  @override
  State<DetayliAra> createState() => _DetayliAraState();
}

class _DetayliAraState extends State<DetayliAra> {
  final InstitutionController kurum = Get.find<InstitutionController>();

  final TextEditingController _searchController = TextEditingController();
  final List<Map<String, dynamic>> _allDanisanlar = [];
  final List<Map<String, dynamic>> _filteredDanisanlar = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  Worker? _institutionWorker;
  String _selectedGender = _genderAll;

  static const String _genderAll = 'Tümü';
  static const String _genderFemale = 'Kadın';
  static const String _genderMale = 'Erkek';

  @override
  void initState() {
    super.initState();
    _listenDanisanlar();
    _institutionWorker = ever(kurum.data, (_) => _listenDanisanlar());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _institutionWorker?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _listenDanisanlar() {
    final institutionId = (kurum.data['kurumkodu'] ?? '').toString();
    if (institutionId.isEmpty) {
      _subscription?.cancel();
      _allDanisanlar.clear();
      _filteredDanisanlar.clear();
      setState(() {});
      return;
    }
    _subscription?.cancel();
    _subscription = FirebaseFirestore.instance
        .collection('kurumlar')
        .doc(institutionId)
        .collection('danisanlar')
        .orderBy('adi')
        .snapshots()
        .listen((snapshot) {
      _allDanisanlar
        ..clear()
        ..addAll(snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }));
      _applyFilters();
    });
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toUpperCase();
    final genderFilter = _selectedGender;
    _filteredDanisanlar
      ..clear()
      ..addAll(_allDanisanlar.where((danisan) {
        final name = (danisan['adi'] ?? '').toString().toUpperCase();
        final surname = (danisan['soyadi'] ?? '').toString().toUpperCase();
        final phone = _resolvePhone(danisan).toUpperCase();
        final gender = (danisan['cinsiyet'] ?? '').toString().toUpperCase();

        final matchesSearch = query.isEmpty ||
            name.contains(query) ||
            surname.contains(query) ||
            phone.contains(query);

        final matchesGender = genderFilter == _genderAll ||
            (genderFilter == _genderFemale && gender == 'KADIN') ||
            (genderFilter == _genderMale && gender == 'ERKEK');

        return matchesSearch && matchesGender;
      }));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detaylı Danışan Arama'),
        actions: const [HomeIconButton()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _buildSearchField(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildGenderFilter(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: _buildSummaryRow(),
          ),
          const Divider(height: 1),
          Expanded(
            child: _filteredDanisanlar.isEmpty
                ? const Center(child: Text('Eşleşen danışan bulunamadı.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredDanisanlar.length,
                    itemBuilder: (context, index) {
                      final danisan = _filteredDanisanlar[index];
                      return _buildDanisanCard(danisan);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => _applyFilters(),
      decoration: InputDecoration(
        hintText: 'Danışan ara...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  _applyFilters();
                },
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildGenderFilter() {
    final options = [_genderAll, _genderFemale, _genderMale];
    return Wrap(
      spacing: 8,
      children: options.map((option) {
        final isSelected = option == _selectedGender;
        return ChoiceChip(
          label: Text(option),
          selected: isSelected,
          onSelected: (_) {
            setState(() => _selectedGender = option);
            _applyFilters();
          },
        );
      }).toList(),
    );
  }

  Widget _buildSummaryRow() {
    return Row(
      children: [
        Text('Toplam: ${_allDanisanlar.length}'),
        const SizedBox(width: 16),
        Text('Listelenen: ${_filteredDanisanlar.length}'),
      ],
    );
  }

  Widget _buildDanisanCard(Map<String, dynamic> danisan) {
    final adi = (danisan['adi'] ?? '').toString();
    final soyadi = (danisan['soyadi'] ?? '').toString();
    final phone = _resolvePhone(danisan);
    final gender = (danisan['cinsiyet'] ?? '').toString();
    final firstInitial = adi.isNotEmpty ? adi.characters.first.toUpperCase() : '';
    final secondInitial = soyadi.isNotEmpty ? soyadi.characters.first.toUpperCase() : '';
    final initials = (firstInitial + secondInitial).padRight(2, '?').substring(0, 2);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () {
          final id = resolveStudentId(danisan);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DanisanProfil(id: id)),
          );
        },
        leading: CircleAvatar(
          backgroundColor: Colors.purple.shade100,
          child: Text(initials),
        ),
        title: Text(
          "$adi $soyadi".trim().isEmpty ? 'İsimsiz Danışan' : "$adi $soyadi",
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(phone.isEmpty ? '-' : phone),
            if (gender.isNotEmpty)
              Text(
                gender,
                style: const TextStyle(color: Colors.black54),
              ),
          ],
        ),
        trailing: phone.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.phone, color: Colors.green),
                onPressed: () => _launchDialer(phone),
              ),
      ),
    );
  }

  String _resolvePhone(Map<String, dynamic> data) {
    final primary = normalizePhone((data['telefon'] ?? '').toString());
    if (primary.isNotEmpty) {
      return primary;
    }
    return normalizePhone((data['ogrencitel'] ?? '').toString());
  }

  Future<void> _launchDialer(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await launcher.canLaunchUrl(uri)) {
      await launcher.launchUrl(uri);
    }
  }
}
