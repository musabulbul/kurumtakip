
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';

enum FormData {
  Email,
  Password,
}

class LoginScreen extends StatefulWidget {
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _emailKey = 'saved_email';
  static const _passwordKey = 'saved_password';
  static const _rememberKey = 'remember_me';

  final _formKey = GlobalKey<FormState>();
  Color enabled = const Color(0xFF8A2E5D);
  Color enabledtxt = Colors.white;
  Color deaible = const Color(0xFFD7B7C8);
  Color backgroundColor = const Color(0xFF3A1028);
  bool ispasswordev = true;
  bool rememberMe = false;
  FormData? selected;

  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  FocusNode emailFocusNode = FocusNode();
  FocusNode passwordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    super.dispose();
  }
  
  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRemember = prefs.getBool(_rememberKey) ?? false;
    final savedEmail = prefs.getString(_emailKey) ?? '';
    final savedPassword = prefs.getString(_passwordKey) ?? '';

    if (!mounted) {
      return;
    }

    setState(() {
      rememberMe = savedRemember;
      if (savedRemember) {
        emailController.text = savedEmail;
        passwordController.text = savedPassword;
      }
    });
  }

  Future<void> _handleRememberMe(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    if (rememberMe) {
      await prefs.setString(_emailKey, email);
      await prefs.setString(_passwordKey, password);
      await prefs.setBool(_rememberKey, true);
    } else {
      await prefs.remove(_emailKey);
      await prefs.remove(_passwordKey);
      await prefs.setBool(_rememberKey, false);
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.1, 0.4, 0.7, 0.9],
            colors: [
              HexColor("#d86ab0").withOpacity(0.85),
              HexColor("#c9549c"),
              HexColor("#9b2f72"),
              HexColor("#8a245e")
            ],
          ),
          image: DecorationImage(
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
                HexColor("#fff").withOpacity(0.2), BlendMode.dstATop),
            image: const AssetImage(
              'assets/icons/icon.png',
            ),
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Card(
                  elevation: 5,
                  color:
                      const Color(0xFFF2C6DC).withOpacity(0.55),
                  child: Container(
                    width: 400,
                    padding: const EdgeInsets.all(40.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            "assets/icons/icon.png",
                            width: 100,
                            height: 100,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "Lütfen Giriş Yapın",
                            style: TextStyle(
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            width: 300,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12.0),
                              color: selected == FormData.Email
                                  ? enabled
                                  : backgroundColor,
                            ),
                            padding: const EdgeInsets.all(5.0),
                            child: TextFormField(
                              controller: emailController,
                              focusNode: emailFocusNode,
                              onTap: () {
                                Future.delayed(
                                  const Duration(milliseconds: 100),
                                  () => emailFocusNode.requestFocus(),
                                );
                              },
                              decoration: InputDecoration(
                                enabledBorder: InputBorder.none,
                                border: InputBorder.none,
                                prefixIcon: Icon(
                                  Icons.email_outlined,
                                  color: selected == FormData.Email
                                      ? enabledtxt
                                      : deaible,
                                  size: 20,
                                ),
                                hintText: 'Email',
                                hintStyle: TextStyle(
                                  color: selected == FormData.Email
                                      ? enabledtxt
                                      : deaible,
                                  fontSize: 12,
                                ),
                              ),
                              textAlignVertical: TextAlignVertical.center,
                              style: TextStyle(
                                color: selected == FormData.Email
                                    ? enabledtxt
                                    : deaible,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Lütfen bir email adresi girin';
                                }
                                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                                    .hasMatch(value)) {
                                  return 'Geçerli bir email adresi girin';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            width: 300,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12.0),
                              color: selected == FormData.Password
                                  ? enabled
                                  : backgroundColor,
                            ),
                            padding: const EdgeInsets.all(5.0),
                            child: TextFormField(
                              controller: passwordController,
                              focusNode: passwordFocusNode,
                              obscureText: ispasswordev,
                              onTap: () {
                                Future.delayed(
                                  const Duration(milliseconds: 100),
                                  () => passwordFocusNode.requestFocus(),
                                );
                              },
                              decoration: InputDecoration(
                                enabledBorder: InputBorder.none,
                                border: InputBorder.none,
                                prefixIcon: Icon(
                                  Icons.lock_open_outlined,
                                  color: selected == FormData.Password
                                      ? enabledtxt
                                      : deaible,
                                  size: 20,
                                ),
                                suffixIcon: IconButton(
                                  icon: ispasswordev
                                      ? Icon(
                                          Icons.visibility_off,
                                          color: selected == FormData.Password
                                              ? enabledtxt
                                              : deaible,
                                          size: 20,
                                        )
                                      : Icon(
                                          Icons.visibility,
                                          color: selected == FormData.Password
                                              ? enabledtxt
                                              : deaible,
                                          size: 20,
                                        ),
                                  onPressed: () => setState(
                                      () => ispasswordev = !ispasswordev),
                                ),
                                hintText: 'Şifre',
                                hintStyle: TextStyle(
                                  color: selected == FormData.Password
                                      ? enabledtxt
                                      : deaible,
                                  fontSize: 12,
                                ),
                              ),
                              textAlignVertical: TextAlignVertical.center,
                              style: TextStyle(
                                color: selected == FormData.Password
                                    ? enabledtxt
                                    : deaible,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Lütfen bir şifre girin';
                                }
                                if (value.length < 6) {
                                  return 'Şifre en az 6 karakter olmalı';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: rememberMe,
                                  activeColor: const Color(0xFFE45AAE),
                                  onChanged: (value) {
                                    setState(() {
                                      rememberMe = value ?? false;
                                    });
                                  },
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'Beni hatırla',
                                  style: TextStyle(
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: () async {
                                  if (_formKey.currentState!.validate()) {
                                    String email = emailController.text.trim();
                                    String password =
                                        passwordController.text.trim();
                                    await _handleRememberMe(email, password);
                                    await AuthService().loginWithEmail(
                                        email, password, context);
                                  }
                                },
                                child: Text(
                                  "Giriş Yap",
                                  style: TextStyle(
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  backgroundColor: const Color(0xFFE45AAE),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14.0,
                                    horizontal: 30,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 20.0),
                              TextButton(
                                onPressed: () async {
                                  final email = emailController.text.trim();
                                  if (email.isNotEmpty) {
                                    await FirebaseAuth.instance
                                        .sendPasswordResetEmail(email: email);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Şifre sıfırlama bağlantısı gönderildi.'),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Lütfen bir e-posta adresi girin.'),
                                      ),
                                    );
                                  }
                                },
                                child: Text(
                                  "Şifremi Unuttum",
                                  style: TextStyle(
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  backgroundColor: const Color(0xFFE45AAE),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14.0,
                                    horizontal: 15,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HexColor extends Color {
  static int _getColorFromHex(String hexColor) {
    hexColor = hexColor.toUpperCase().replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF" + hexColor;
    }
    return int.parse(hexColor, radix: 16);
  }

  HexColor(final String hexColor) : super(_getColorFromHex(hexColor));
}
