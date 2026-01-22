import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import '../controllers/institution_controller.dart';
import '../utils/phone_utils.dart';
import '../utils/text_utils.dart';

class DanisanEklePage extends StatefulWidget {
  const DanisanEklePage({super.key});

  @override
  State<DanisanEklePage> createState() => _DanisanEklePageState();
}

class _DanisanEklePageState extends State<DanisanEklePage> {
  final _formKey = GlobalKey<FormState>();
  final _adSoyadController = TextEditingController();
  final _telefonController = TextEditingController();
  final _adresController = TextEditingController();
  final _aciklamaController = TextEditingController();
  final _dogumTarihiController = TextEditingController();
  final InstitutionController _kurum = Get.find<InstitutionController>();

  String? _selectedGender;
  DateTime? _selectedBirthDate;
  bool _submitting = false;

  @override
  void dispose() {
    _adSoyadController.dispose();
    _telefonController.dispose();
    _adresController.dispose();
    _aciklamaController.dispose();
    _dogumTarihiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danışan Ekle'),
        actions: const [HomeIconButton()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_submitting) const LinearProgressIndicator(),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _adSoyadController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Adı Soyadı *',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Adı soyadı zorunludur';
                      }
                      if (value.trim().length < 2) {
                        return 'En az 2 karakter olmalı';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _telefonController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Telefon',
                      hintText: '+90...',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedGender,
                    decoration: const InputDecoration(
                      labelText: 'Cinsiyet',
                      prefixIcon: Icon(Icons.person_search_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'KADIN', child: Text('Kadın')),
                      DropdownMenuItem(value: 'ERKEK', child: Text('Erkek')),
                      DropdownMenuItem(value: 'BELİRTİLMEDİ', child: Text('Belirtilmedi')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedGender = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _dogumTarihiController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Doğum Tarihi',
                      prefixIcon: Icon(Icons.cake_outlined),
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    onTap: () async {
                      final now = DateTime.now();
                      final initialDate = _selectedBirthDate ?? now;
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: initialDate,
                        firstDate: DateTime(1900),
                        lastDate: now,
                        helpText: 'Doğum tarihi seçin',
                      );
                      if (picked == null) {
                        return;
                      }
                      setState(() {
                        _selectedBirthDate = picked;
                        _dogumTarihiController.text = DateFormat('dd.MM.yyyy').format(picked);
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _adresController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Adres',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.home_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _aciklamaController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                          child: const Text('Vazgeç'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _saveDanisan,
                          child: _submitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text('Kaydet'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveDanisan() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    final kurumKodu = (_kurum.data['kurumkodu'] ?? '').toString();
    if (kurumKodu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
      );
      return;
    }

    final trimmedFullName = _adSoyadController.text.trim();
    final nameParts = trimmedFullName.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    String surname = '';
    String firstName;
    if (nameParts.length >= 2) {
      surname = toUpperCaseTr(nameParts.removeLast());
      firstName = toUpperCaseTr(nameParts.join(' '));
    } else {
      firstName = toUpperCaseTr(trimmedFullName);
    }
    final normalizedPhone = normalizePhone(_telefonController.text.trim());

    setState(() {
      _submitting = true;
    });

    try {
      final studentsRef = FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(kurumKodu)
          .collection('danisanlar');
      final docRef = studentsRef.doc();
      final kayitTarihi = DateFormat('yyyy-MM-dd').format(DateTime.now());

      await docRef.set({
        'id': docRef.id,
        'adi': firstName,
        'soyadi': surname,
        'telefon': normalizedPhone,
        if (_selectedGender != null) 'cinsiyet': _selectedGender,
        'adres': _adresController.text.trim(),
        'aciklama': _aciklamaController.text.trim(),
        'kayittarihi': kayitTarihi,
        if (_selectedBirthDate != null)
          'dogumtarihi': DateFormat('yyyy-MM-dd').format(_selectedBirthDate!),
        'kurumkodu': kurumKodu,
        'olusturulmaZamani': Timestamp.now(),
      });

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(docRef.id);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Danışan kaydedilemedi: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }
}
