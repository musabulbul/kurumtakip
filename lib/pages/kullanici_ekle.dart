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
  UserController user = Get.find<UserController>();
  InstitutionController kurum = Get.find<InstitutionController>();
  bool yukleniyor = false;
  final _formAnahtari = GlobalKey<FormState>();
  late String adi, soyadi, email, sifre;
  String roldeger = "YÖNETİCİ";
  String rol = "YÖNETİCİ";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Kullanıcı Ekle"),
        actions: const [HomeIconButton()],
      ),
      body: ListView(
        children: <Widget>[
          if (yukleniyor) const LinearProgressIndicator(),
          const SizedBox(height: 20.0),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Form(
              key: _formAnahtari,
              child: Column(
                children: <Widget>[
                  TextFormField(
                    autocorrect: true,
                    decoration: const InputDecoration(
                      hintText: "Kullanıcı adını giriniz",
                      labelText: "Adı:",
                      errorStyle: TextStyle(fontSize: 16.0),
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (girilenDeger) {
                      if (girilenDeger!.isEmpty) {
                        return "Adı boş bırakılamaz!";
                      } else if (girilenDeger.trim().length < 2 ||
                          girilenDeger.trim().length > 30) {
                        return "En az 2 en fazla 30 karakter olabilir!";
                      }
                      return null;
                    },
                    onSaved: (girilenDeger) => adi = girilenDeger!.toUpperCase(),
                  ),
                  const SizedBox(height: 10.0),
                  TextFormField(
                    autocorrect: true,
                    decoration: const InputDecoration(
                      hintText: "Kullanıcı soyadını giriniz",
                      labelText: "Soyadı:",
                      errorStyle: TextStyle(fontSize: 16.0),
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (girilenDeger) {
                      if (girilenDeger!.isEmpty) {
                        return "Soyadı boş bırakılamaz!";
                      } else if (girilenDeger.trim().length < 2 ||
                          girilenDeger.trim().length > 30) {
                        return "En az 2 en fazla 30 karakter olabilir!";
                      }
                      return null;
                    },
                    onSaved: (girilenDeger) => soyadi = girilenDeger!.toUpperCase(),
                  ),
                  const SizedBox(height: 10.0),
                  TextFormField(
                    autocorrect: true,
                    decoration: const InputDecoration(
                      hintText: "Kullanıcı e-mailini giriniz",
                      labelText: "E-mail:",
                      errorStyle: TextStyle(fontSize: 16.0),
                      prefixIcon: Icon(Icons.email),
                    ),
                    validator: (girilenDeger) {
                      if (girilenDeger!.isEmpty) {
                        return "E-mail boş bırakılamaz!";
                      } else if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
                          .hasMatch(girilenDeger)) {
                        return "Geçerli bir e-posta adresi giriniz!";
                      }
                      return null;
                    },
                    onSaved: (girilenDeger) => email = girilenDeger!,
                  ),
                  const SizedBox(height: 10.0),
                  TextFormField(
                    autocorrect: true,
                    decoration: const InputDecoration(
                      hintText: "Şifre giriniz",
                      labelText: "Şifre:",
                      errorStyle: TextStyle(fontSize: 16.0),
                      prefixIcon: Icon(Icons.lock),
                    ),
                    validator: (girilenDeger) {
                      if (girilenDeger!.isEmpty) {
                        return "Şifre boş bırakılamaz!";
                      } else if (girilenDeger.trim().length < 4 ||
                          girilenDeger.trim().length > 30) {
                        return "En az 4 en fazla 30 karakter olabilir!";
                      }
                      return null;
                    },
                    onSaved: (girilenDeger) => sifre = girilenDeger!,
                  ),
                  const SizedBox(height: 10.0),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        const Icon(Icons.person),
                        const Text("    Rol:    ",
                            style: TextStyle(fontSize: 16.0)),
                        DropdownButton<String>(
                          value: roldeger,
                          icon: const Icon(Icons.arrow_downward),
                          iconSize: 24,
                          elevation: 16,
                          style: const TextStyle(color: Colors.black),
                          underline: Container(
                            height: 2,
                            color: Colors.black,
                          ),
                          onChanged: (girilenDeger) {
                            setState(() {
                              rol = girilenDeger!;
                              roldeger = girilenDeger;
                            });
                          },
                          items: <String>['YÖNETİCİ', 'ÇALIŞAN', 'MUHASEBE']
                              .map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 50.0),
                  Container(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _kullaniciOlustur,
                      child: const Text(
                        "Kullanıcı Ekle",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
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
  }

  void _kullaniciOlustur() async {
  var _formState = _formAnahtari.currentState;

  if (_formState!.validate()) {
    _formState.save();
    setState(() {
      yukleniyor = true;
    });

    try {
      // E-posta adresini normalize et
      email = email.trim().toLowerCase();

      // Kullanıcı var mı kontrolü
      var docSnapshot = await FirebaseFirestore.instance
          .collection('kullanicilar')
          .doc(email)
          .get();

      if (docSnapshot.exists) {
        throw "Bu e-posta ile bir kullanıcı zaten kayıtlı.";
      }

      final dynamic kurumkoduKaynak =
          kurum.data["kurumkodu"] ?? user.data["kurumkodu"];
      final String kurumkodu = (kurumkoduKaynak ?? '').toString();

      if (kurumkodu.isEmpty) {
        setState(() {
          yukleniyor = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Kurum bilgisi yüklenemedi. Lütfen tekrar deneyin."),
          ),
        );
        return;
      }

      final localId = await _createFirebaseAuthUser(email, sifre);

      // Kullanıcı oluşturma
      await FirebaseFirestore.instance.collection('kullanicilar').doc(email).set({
        'adi': adi,
        'soyadi': soyadi,
        'email': email,
        'rol': rol,
        'siniflar': <String>[],
        "kisaad": "${adi[0]}.${soyadi.toUpperCase()}",
        "kurumkodu": kurumkodu,
        "olusturulmazamani": Timestamp.now(),
        "olusturan": "${user.data["adi"]} ${user.data["soyadi"]}",
        "uid": localId,
      });

      // Başarılı işlem mesajı
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$adi $soyadi başarıyla eklendi."))
      );

      setState(() {
        yukleniyor = false;
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (hata) {
      setState(() {
        yukleniyor = false;
      });

      // Hata mesajı
      String mesaj;
      if (hata == "Bu e-posta ile bir kullanıcı zaten kayıtlı.") {
        mesaj = "Bu e-posta adresi zaten kayıtlı.";
      } else if (hata == 'EMAIL_EXISTS') {
        mesaj = "Bu e-posta adresi zaten kayıtlı.";
      } else if (hata == 'WEAK_PASSWORD : Password should be at least 6 characters') {
        mesaj = "Şifre en az 6 karakter olmalıdır.";
      } else if (hata is String && hata.contains('WEAK_PASSWORD')) {
        mesaj = "Şifre en az 6 karakter olmalıdır.";
      } else {
        mesaj = "Bir hata oluştu: $hata";
        print(mesaj);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mesaj)),
      );
    }
  }
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
      final Map<String, dynamic> body = jsonDecode(response.body);
      final errorMessage = body['error']?['message'] ?? 'Bilinmeyen hata';
      throw errorMessage;
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['localId'] as String;
  }

}
