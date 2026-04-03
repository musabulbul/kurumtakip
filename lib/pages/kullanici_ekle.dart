import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:kurum_takip/firebase_options.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import '../controllers/institution_controller.dart';
import '../controllers/user_controller.dart';

class KullaniciEkle extends StatefulWidget {
  const KullaniciEkle({Key? key}) : super(key: key);

  @override
  _KullaniciEkleState createState() => _KullaniciEkleState();
}

class _KullaniciEkleState extends State<KullaniciEkle> {
  final UserController user = Get.find<UserController>();
  final InstitutionController kurum = Get.find<InstitutionController>();

  bool yukleniyor = false;
  bool _hesapOlustur = false;

  final _formAnahtari = GlobalKey<FormState>();
  late String adi, soyadi;
  String email = '', sifre = '';
  String rol = 'ÇALIŞAN';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personel Ekle'),
        actions: const [HomeIconButton()],
      ),
      body: ListView(
        children: [
          if (yukleniyor) const LinearProgressIndicator(),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formAnahtari,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Adı',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Ad boş bırakılamaz.';
                      if (v.trim().length < 2) return 'En az 2 karakter olmalı.';
                      return null;
                    },
                    onSaved: (v) => adi = v!.trim().toUpperCase(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Soyadı',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Soyad boş bırakılamaz.';
                      if (v.trim().length < 2) return 'En az 2 karakter olmalı.';
                      return null;
                    },
                    onSaved: (v) => soyadi = v!.trim().toUpperCase(),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: rol,
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'YÖNETİCİ', child: Text('YÖNETİCİ')),
                      DropdownMenuItem(value: 'ÇALIŞAN', child: Text('ÇALIŞAN')),
                      DropdownMenuItem(value: 'MUHASEBE', child: Text('MUHASEBE')),
                    ],
                    onChanged: (v) => setState(() => rol = v!),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Giriş hesabı oluştur'),
                    subtitle: const Text(
                        'E-posta ve şifre ile uygulama girişi için hesap açar.'),
                    value: _hesapOlustur,
                    onChanged: (v) => setState(() => _hesapOlustur = v),
                  ),
                  if (_hesapOlustur) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'E-posta',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: _hesapOlustur
                          ? (v) {
                              if (v == null || v.trim().isEmpty) return 'E-posta boş bırakılamaz.';
                              if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
                                  .hasMatch(v)) return 'Geçerli e-posta girin.';
                              return null;
                            }
                          : null,
                      onSaved: (v) => email = v?.trim().toLowerCase() ?? '',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Şifre',
                        prefixIcon: Icon(Icons.lock_outlined),
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      validator: _hesapOlustur
                          ? (v) {
                              if (v == null || v.trim().isEmpty) return 'Şifre boş bırakılamaz.';
                              if (v.trim().length < 6) return 'En az 6 karakter olmalı.';
                              return null;
                            }
                          : null,
                      onSaved: (v) => sifre = v ?? '',
                    ),
                  ],
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: yukleniyor ? null : _kaydet,
                    child: const Text(
                      'Kaydet',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _kaydet() async {
    final formState = _formAnahtari.currentState;
    if (formState == null || !formState.validate()) return;
    formState.save();

    setState(() => yukleniyor = true);

    try {
      final kurumkodu = ((kurum.data['kurumkodu'] ?? user.data['kurumkodu']) ?? '').toString();
      if (kurumkodu.isEmpty) {
        _showError('Kurum bilgisi yüklenemedi.');
        return;
      }

      String uid = '';
      String docId;

      if (_hesapOlustur) {
        // E-posta ile kayıtlı personel var mı?
        final existing = await FirebaseFirestore.instance
            .collection('kullanicilar')
            .doc(email)
            .get();
        if (existing.exists) throw 'Bu e-posta ile kayıtlı bir personel var.';

        uid = await _createFirebaseAuthUser(email, sifre);
        docId = email;
      } else {
        // Hesapsız: auto-generated ID
        docId = FirebaseFirestore.instance.collection('kullanicilar').doc().id;
      }

      await FirebaseFirestore.instance.collection('kullanicilar').doc(docId).set({
        'adi': adi,
        'soyadi': soyadi,
        'email': email,
        'rol': rol,
        'siniflar': <String>[],
        'yetkiler': <String>[],
        'kisaad': '${adi[0]}.${soyadi.toUpperCase()}',
        'kurumkodu': kurumkodu,
        'olusturulmazamani': Timestamp.now(),
        'olusturan': '${user.data['adi']} ${user.data['soyadi']}',
        'uid': uid,
        'durum': 'aktif',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$adi $soyadi başarıyla eklendi.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      _showError(_parseError(e));
    } finally {
      if (mounted) setState(() => yukleniyor = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _parseError(dynamic e) {
    final s = e.toString();
    if (s.contains('EMAIL_EXISTS') || s.contains('e-posta ile kayıtlı')) {
      return 'Bu e-posta adresi zaten kayıtlı.';
    }
    if (s.contains('WEAK_PASSWORD')) return 'Şifre en az 6 karakter olmalıdır.';
    return 'Bir hata oluştu: $s';
  }

  Future<String> _createFirebaseAuthUser(String email, String password) async {
    final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
    final uri = Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw body['error']?['message'] ?? 'Bilinmeyen hata';
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['localId'] as String;
  }
}
