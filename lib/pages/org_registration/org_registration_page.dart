import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/org_registration_service.dart';

class OrgRegistrationPage extends StatefulWidget {
  const OrgRegistrationPage({super.key});

  @override
  State<OrgRegistrationPage> createState() => _OrgRegistrationPageState();
}

class _OrgRegistrationPageState extends State<OrgRegistrationPage> {
  final _service = OrgRegistrationService();

  // Adım: 0 = Form, 1 = OTP doğrulama
  int _step = 0;

  bool _isLoading = false;
  String? _errorMessage;

  // Form key
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  final _kurumAdiCtrl = TextEditingController();
  final _kisaadCtrl = TextEditingController();
  final _ilCtrl = TextEditingController();
  final _ilceCtrl = TextEditingController();
  final _mahalleCtrl = TextEditingController();
  final _adresCtrl = TextEditingController();
  final _yetkiliAdiCtrl = TextEditingController();
  final _yetkiliSoyadiCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _sifreCtrl = TextEditingController();
  final _telefonCtrl = TextEditingController();

  bool _sifreGizli = true;
  bool _kisaadManuallyEdited = false;

  // OTP adımı
  final _otpCtrl = TextEditingController();
  String? _otpToken;

  @override
  void initState() {
    super.initState();
    _yetkiliAdiCtrl.addListener(_autoFillKisaad);
    _yetkiliSoyadiCtrl.addListener(_autoFillKisaad);
  }

  void _autoFillKisaad() {
    if (_kisaadManuallyEdited) return;
    final kisaad = _buildKisaad(
      _yetkiliAdiCtrl.text.trim(),
      _yetkiliSoyadiCtrl.text.trim(),
    );
    if (_kisaadCtrl.text != kisaad) {
      _kisaadCtrl.text = kisaad;
    }
  }

  String _buildKisaad(String ad, String soyad) {
    final adParts = ad
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final initials = adParts.map((p) => p[0].toUpperCase()).join('.');
    final soyadClean = soyad.toUpperCase();
    final result = initials.isEmpty ? soyadClean : '$initials.$soyadClean';
    return result.length > 15 ? result.substring(0, 15) : result;
  }

  @override
  void dispose() {
    _kurumAdiCtrl.dispose();
    _kisaadCtrl.dispose();
    _ilCtrl.dispose();
    _ilceCtrl.dispose();
    _mahalleCtrl.dispose();
    _adresCtrl.dispose();
    _yetkiliAdiCtrl.dispose();
    _yetkiliSoyadiCtrl.dispose();
    _emailCtrl.dispose();
    _sifreCtrl.dispose();
    _telefonCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _onFormSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Mükerrer kayıt kontrolü
      final dupes = await _service.checkDuplicates(
        email: _emailCtrl.text.trim(),
        phone: _telefonCtrl.text.trim(),
      );

      if (dupes['emailExists'] == true && dupes['phoneExists'] == true) {
        setState(() {
          _errorMessage =
              'Bu e-posta adresi ve telefon numarası zaten kayıtlı.';
          _isLoading = false;
        });
        return;
      }
      if (dupes['emailExists'] == true) {
        setState(() {
          _errorMessage = 'Bu e-posta adresi zaten kayıtlı.';
          _isLoading = false;
        });
        return;
      }
      if (dupes['phoneExists'] == true) {
        setState(() {
          _errorMessage = 'Bu telefon numarası zaten kayıtlı.';
          _isLoading = false;
        });
        return;
      }

      // OTP gönder
      final token = await _service.sendRegistrationOtp(_telefonCtrl.text.trim());
      setState(() {
        _otpToken = token;
        _step = 1;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _onOtpSubmit() async {
    final enteredCode = _otpCtrl.text.trim();
    if (enteredCode.isEmpty) return;
    if (_otpToken == null) return;

    if (enteredCode != _otpToken) {
      setState(() => _errorMessage = 'Doğrulama kodu hatalı. Lütfen tekrar deneyin.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _service.registerOrgAndAdmin(
        kurumAdi: _kurumAdiCtrl.text.trim(),
        kisaad: _kisaadCtrl.text.trim(),
        il: _ilCtrl.text.trim(),
        ilce: _ilceCtrl.text.trim(),
        mahalle: _mahalleCtrl.text.trim(),
        adres: _adresCtrl.text.trim(),
        yetkiliAdi: _yetkiliAdiCtrl.text.trim(),
        yetkiliSoyadi: _yetkiliSoyadiCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        sifre: _sifreCtrl.text,
        telefon: _telefonCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        '/homepage',
        arguments: {
          'userDocId': result['userDocId'],
          'userKurum': result['kurumkodu'],
        },
      );
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _otpCtrl.clear();
    });
    try {
      final token = await _service.sendRegistrationOtp(_telefonCtrl.text.trim());
      setState(() {
        _otpToken = token;
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yeni doğrulama kodu gönderildi.')),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
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
              _hex('#d86ab0').withValues(alpha: 0.85),
              _hex('#c9549c'),
              _hex('#9b2f72'),
              _hex('#8a245e'),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
            child: _step == 0 ? _buildFormCard() : _buildOtpCard(),
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Card(
      elevation: 5,
      color: const Color(0xFFF2C6DC).withValues(alpha: 0.55),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Başlık
              const Text(
                'Kurumunuzu Kaydedin',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '30 gün ücretsiz deneyin',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 28),

              // Kurum bilgileri
              _sectionLabel('Kurum Bilgileri'),
              const SizedBox(height: 12),
              _buildField(
                controller: _kurumAdiCtrl,
                label: 'Kurum Tam Adı',
                icon: Icons.business_outlined,
                validator: _required('Kurum adı zorunludur'),
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _kisaadCtrl,
                label: 'Kurum Kısa Adı',
                icon: Icons.short_text_outlined,
                hint: 'Maks. 15 karakter',
                inputFormatters: [LengthLimitingTextInputFormatter(15)],
                onChanged: (_) => _kisaadManuallyEdited = true,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Kısa ad zorunludur';
                  if (v.trim().length > 15) return 'En fazla 15 karakter';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _ilCtrl,
                      label: 'İl',
                      icon: Icons.location_city_outlined,
                      validator: _required('İl zorunludur'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _ilceCtrl,
                      label: 'İlçe',
                      icon: Icons.map_outlined,
                      validator: _required('İlçe zorunludur'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _mahalleCtrl,
                label: 'Mahalle',
                icon: Icons.holiday_village_outlined,
                validator: _required('Mahalle zorunludur'),
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _adresCtrl,
                label: 'Adres',
                icon: Icons.home_outlined,
                maxLines: 2,
                validator: _required('Adres zorunludur'),
              ),
              const SizedBox(height: 24),

              // Yetkili kişi
              _sectionLabel('Yetkili Kişi'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _yetkiliAdiCtrl,
                      label: 'Ad',
                      icon: Icons.person_outline,
                      validator: _required('Ad zorunludur'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _yetkiliSoyadiCtrl,
                      label: 'Soyad',
                      icon: Icons.person_outline,
                      validator: _required('Soyad zorunludur'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Hesap bilgileri
              _sectionLabel('Hesap Bilgileri'),
              const SizedBox(height: 12),
              _buildField(
                controller: _emailCtrl,
                label: 'E-posta (kullanıcı adı)',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'E-posta zorunludur';
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                    return 'Geçerli bir e-posta girin';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildPasswordField(),
              const SizedBox(height: 12),
              _buildField(
                controller: _telefonCtrl,
                label: 'Cep Telefonu',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                hint: '05XX XXX XX XX',
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Telefon zorunludur';
                  final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                  if (digits.length < 10) return 'Geçerli bir telefon numarası girin';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Hata mesajı
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Butonlar
              ElevatedButton(
                onPressed: _isLoading ? null : _onFormSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE45AAE),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Devam Et',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Giriş ekranına dön',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpCard() {
    final phone = _service.normalizePhone(_telefonCtrl.text.trim());
    return Card(
      elevation: 5,
      color: const Color(0xFFF2C6DC).withValues(alpha: 0.55),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.sms_outlined, color: Colors.white, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Doğrulama Kodu',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$phone numaralı telefonunuza 6 haneli doğrulama kodu gönderildi.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 10,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '------',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 28,
                  letterSpacing: 10,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white54),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white),
                ),
                filled: true,
                fillColor: const Color(0xFF3A1028).withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
            ],
            ElevatedButton(
              onPressed: _isLoading ? null : _onOtpSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE45AAE),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Kaydı Tamamla',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : _resendOtp,
                  child: const Text(
                    'Kodu tekrar gönder',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                const Text('·', style: TextStyle(color: Colors.white54)),
                TextButton(
                  onPressed: () => setState(() {
                    _step = 0;
                    _errorMessage = null;
                    _otpCtrl.clear();
                  }),
                  child: const Text(
                    'Geri dön',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.white70, size: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white38),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        errorStyle: const TextStyle(color: Colors.white, fontSize: 11),
        filled: true,
        fillColor: const Color(0xFF3A1028).withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      validator: validator,
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _sifreCtrl,
      obscureText: _sifreGizli,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: 'Şifre',
        hintText: 'En az 6 karakter',
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
        prefixIcon: const Icon(Icons.lock_outlined, color: Colors.white70, size: 18),
        suffixIcon: IconButton(
          icon: Icon(
            _sifreGizli ? Icons.visibility_off : Icons.visibility,
            color: Colors.white70,
            size: 18,
          ),
          onPressed: () => setState(() => _sifreGizli = !_sifreGizli),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white38),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        errorStyle: const TextStyle(color: Colors.white, fontSize: 11),
        filled: true,
        fillColor: const Color(0xFF3A1028).withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Şifre zorunludur';
        if (v.length < 6) return 'Şifre en az 6 karakter olmalı';
        return null;
      },
    );
  }

  String? Function(String?) _required(String message) {
    return (v) => (v == null || v.trim().isEmpty) ? message : null;
  }

  Color _hex(String hexColor) {
    hexColor = hexColor.toUpperCase().replaceAll('#', '');
    if (hexColor.length == 6) hexColor = 'FF$hexColor';
    return Color(int.parse(hexColor, radix: 16));
  }
}
