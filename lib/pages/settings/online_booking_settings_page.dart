import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import '../../controllers/institution_controller.dart';
import '../../controllers/user_controller.dart';
import '../../models/booking_settings.dart';
import '../../utils/permission_utils.dart';

class OnlineBookingSettingsPage extends StatefulWidget {
  const OnlineBookingSettingsPage({super.key});

  @override
  State<OnlineBookingSettingsPage> createState() =>
      _OnlineBookingSettingsPageState();
}

class _OnlineBookingSettingsPageState
    extends State<OnlineBookingSettingsPage> {
  final _user = Get.find<UserController>();
  final _institution = Get.find<InstitutionController>();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  // Genel
  bool _bookingEnabled = false;
  final _slugController = TextEditingController();
  bool _hasSmsProvider = false;

  // Doğrulama
  String _authMode = 'phone_birthdate';

  // Kurallar
  int _maxDaysAhead = 30;
  int _minHoursBefore = 2;
  int _slotMinutes = 30;
  bool _allowSameDay = true;
  bool _weekendOpen = false;

  // Görüntüleme
  bool _showServicePrices = false;
  bool _showAccountStatement = false;
  bool _allowStaffSelection = false;

  // Metinler
  final _publicInfoController = TextEditingController();
  final _successTextController = TextEditingController();

  // AI Asistan
  bool _aiAssistantEnabled = false;
  final _aiExtraContextController = TextEditingController();

  // Görseller
  String _logoUrl = '';
  final List<String> _bannerUrls = ['', '', ''];
  final List<TextEditingController> _bannerCaptions = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  bool _isUploadingImage = false;

  // Çalışma saatleri
  final Map<int, bool> _dayOpen = {};
  final Map<int, String> _dayStart = {};
  final Map<int, String> _dayEnd = {};
  List<String> _closedDates = [];

  static const _dayNames = {
    1: 'Pazartesi',
    2: 'Salı',
    3: 'Çarşamba',
    4: 'Perşembe',
    5: 'Cuma',
    6: 'Cumartesi',
    7: 'Pazar',
  };

  @override
  void initState() {
    super.initState();
    for (var i = 1; i <= 7; i++) {
      _dayOpen[i] = i <= 5;
      _dayStart[i] = '09:00';
      _dayEnd[i] = '18:00';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!isManagerUser(_user.data)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Bu sayfaya sadece yöneticiler erişebilir.')),
        );
        Navigator.of(context).maybePop();
        return;
      }
      _load();
    });
  }

  @override
  void dispose() {
    _slugController.dispose();
    _publicInfoController.dispose();
    _successTextController.dispose();
    _aiExtraContextController.dispose();
    for (final c in _bannerCaptions) {
      c.dispose();
    }
    super.dispose();
  }

  String _institutionId() =>
      (_institution.data['kurumkodu'] ?? '').toString();

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final id = _institutionId();
    if (id.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Kurum bilgisine ulaşılamadı.';
      });
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(id)
          .get();
      final data = doc.data() ?? <String, dynamic>{};

      // bookingSettings önce denenir (yeni format), sonra settings.onlineBooking
      final bs = data['bookingSettings'] is Map
          ? _asMap(data['bookingSettings'])
          : _asMap(_asMap(data['settings'])['onlineBooking']);

      _bookingEnabled = data['bookingEnabled'] == true;
      _slugController.text = (data['slug'] as String?) ?? '';
      _hasSmsProvider =
          (data['smsProviderId'] as String?)?.trim().isNotEmpty == true;

      _authMode =
          (bs['authMode'] as String?) == 'otp' ? 'otp' : 'phone_birthdate';
      _showServicePrices = bs['showServicePrices'] == true;
      _showAccountStatement = bs['showAccountStatement'] == true;
      _allowStaffSelection = bs['allowStaffSelection'] == true;
      _maxDaysAhead = (bs['maxDaysAhead'] as num?)?.toInt() ?? 30;
      _minHoursBefore = (bs['minHoursBefore'] as num?)?.toInt() ?? 2;
      _slotMinutes = (bs['slotMinutes'] as num?)?.toInt() ?? 30;
      _allowSameDay = bs['allowSameDay'] != false;
      _weekendOpen = bs['weekendOpen'] == true;
      _publicInfoController.text = (bs['publicInfoText'] as String?) ?? '';
      _successTextController.text = (bs['successText'] as String?) ?? '';
      _aiAssistantEnabled = bs['aiAssistantEnabled'] == true;
      _aiExtraContextController.text = (bs['aiExtraContext'] as String?) ?? '';

      // Görseller
      _logoUrl = (data['logoUrl'] as String?) ?? '';
      final rawBanners = (bs['bannerImages'] as List?) ?? [];
      for (var i = 0; i < 3; i++) {
        if (i < rawBanners.length && rawBanners[i] is Map) {
          final b = Map<String, dynamic>.from(rawBanners[i] as Map);
          _bannerUrls[i] = (b['url'] as String?) ?? '';
          _bannerCaptions[i].text = (b['caption'] as String?) ?? '';
        }
      }

      final wh = WorkingHours.fromMap(
        data['workingHours'] is Map ? _asMap(data['workingHours']) : null,
      );
      for (var i = 1; i <= 7; i++) {
        final cfg = wh.days[i];
        _dayOpen[i] = cfg?.isOpen ?? (i <= 5);
        final win =
            cfg?.windows.isNotEmpty == true ? cfg!.windows.first : null;
        _dayStart[i] = win?.start ?? '09:00';
        _dayEnd[i] = win?.end ?? '18:00';
      }
      _closedDates = List<String>.from(wh.closedDates);

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ayarlar yüklenemedi: $e';
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final id = _institutionId();
    if (id.isEmpty) {
      _showSnack('Kurum bilgisine ulaşılamadı.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final whMap = <String, dynamic>{};
      for (var i = 1; i <= 7; i++) {
        whMap['$i'] = {
          'isOpen': _dayOpen[i] ?? false,
          'windows': [
            {
              'start': _dayStart[i] ?? '09:00',
              'end': _dayEnd[i] ?? '18:00',
            }
          ],
        };
      }
      whMap['closedDates'] = _closedDates;

      final bannerList = List.generate(3, (i) {
        final url = _bannerUrls[i];
        if (url.isEmpty) return null;
        return {'url': url, 'caption': _bannerCaptions[i].text.trim()};
      }).whereType<Map<String, dynamic>>().toList();

      await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(id)
          .set(
            {
              'bookingEnabled': _bookingEnabled,
              'logoUrl': _logoUrl,
              'bookingSettings': {
                'enabled': _bookingEnabled,
                'authMode': _authMode,
                'showServicePrices': _showServicePrices,
                'showAccountStatement': _showAccountStatement,
                'allowStaffSelection': _allowStaffSelection,
                'maxDaysAhead': _maxDaysAhead,
                'minHoursBefore': _minHoursBefore,
                'slotMinutes': _slotMinutes,
                'allowSameDay': _allowSameDay,
                'weekendOpen': _weekendOpen,
                'publicInfoText': _publicInfoController.text.trim(),
                'successText': _successTextController.text.trim(),
                'aiAssistantEnabled': _aiAssistantEnabled,
                'aiExtraContext': _aiExtraContextController.text.trim(),
                'bannerImages': bannerList,
              },
              'workingHours': whMap,
            },
            SetOptions(merge: true),
          );
      if (!mounted) return;
      _showSnack('Ayarlar kaydedildi.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Kaydetme başarısız: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  // ── Görsel Yükleme ───────────────────────────────────────────────────────────

  Future<String?> _uploadImage(String storagePath) async {
    try {
      final picker = ImagePicker();
      final xFile =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (xFile == null) return null;

      setState(() => _isUploadingImage = true);
      final bytes = await xFile.readAsBytes();
      final ref = FirebaseStorage.instance.ref(storagePath);
      final task = await ref.putData(
          bytes, SettableMetadata(contentType: 'image/jpeg'));
      return await task.ref.getDownloadURL();
    } catch (e) {
      if (mounted) _showSnack('Görsel yüklenemedi: $e');
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Widget _buildImagesCard(ColorScheme cs) {
    final id = _institutionId();
    return _Section(
      title: 'Görseller',
      icon: Icons.photo_library_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Logo ──────────────────────────────────────────────────────────
          Text(
            'Logo',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: cs.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Randevu sayfasının üst kısmında gösterilir.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          _ImageUploadTile(
            url: _logoUrl,
            isUploading: _isUploadingImage,
            cs: cs,
            onUpload: () async {
              final url =
                  await _uploadImage('$id/booking/logo.jpg');
              if (url != null) setState(() => _logoUrl = url);
            },
            onRemove: () => setState(() => _logoUrl = ''),
          ),

          const Divider(height: 32),

          // ── Banner Görselleri ─────────────────────────────────────────────
          Text(
            'Tanıtım Görselleri',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: cs.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Logo altında en fazla 3 görsel gösterilir. Her görsele açıklama ekleyebilirsiniz.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _bannerUrls[i].isNotEmpty
                        ? cs.primary
                        : cs.surfaceContainerHighest,
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: _bannerUrls[i].isNotEmpty
                            ? cs.onPrimary
                            : cs.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Görsel ${i + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ImageUploadTile(
              url: _bannerUrls[i],
              captionController: _bannerCaptions[i],
              isUploading: _isUploadingImage,
              cs: cs,
              onUpload: () async {
                final url = await _uploadImage(
                    '$id/booking/banner_$i.jpg');
                if (url != null) setState(() => _bannerUrls[i] = url);
              },
              onRemove: () => setState(() => _bannerUrls[i] = ''),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickTime(int day, bool isStart) async {
    final current = isStart ? _dayStart[day]! : _dayEnd[day]!;
    final parts = current.split(':');
    final initial = TimeOfDay(
        hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isStart) {
          _dayStart[day] = formatted;
        } else {
          _dayEnd[day] = formatted;
        }
      });
    }
  }

  Future<void> _addClosedDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
      initialDate: now,
    );
    if (picked != null && mounted) {
      final fmt =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      if (!_closedDates.contains(fmt)) {
        setState(() => _closedDates.add(fmt));
      }
    }
  }

  String _formatClosedDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      const m = [
        'Oca','Şub','Mar','Nis','May','Haz','Tem','Ağu','Eyl','Eki','Kas','Ara'
      ];
      return '${d.day} ${m[d.month - 1]} ${d.year}';
    } catch (_) {
      return iso;
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Online Randevu Ayarları'),
        actions: const [HomeIconButton()],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_errorMessage!,
                        style: TextStyle(color: cs.error)),
                  ),
                )
              : Stack(
                  children: [
                    ListView(
                      padding:
                          const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      children: [
                        _StatusCard(
                          enabled: _bookingEnabled,
                          onChanged: (v) =>
                              setState(() => _bookingEnabled = v),
                        ),
                        const SizedBox(height: 16),
                        _buildSlugCard(cs),
                        const SizedBox(height: 16),
                        _buildAuthCard(),
                        const SizedBox(height: 16),
                        _buildRulesCard(),
                        const SizedBox(height: 16),
                        _buildDisplayCard(),
                        const SizedBox(height: 16),
                        _buildTextsCard(),
                        const SizedBox(height: 16),
                        _buildAiAssistantCard(cs),
                        const SizedBox(height: 16),
                        _buildImagesCard(cs),
                        const SizedBox(height: 16),
                        _buildWorkingHoursCard(cs),
                        const SizedBox(height: 16),
                        _buildClosedDatesCard(cs),
                      ],
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildSaveBar(cs),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSlugCard(ColorScheme cs) {
    final slug = _slugController.text.trim();
    return _Section(
      title: 'Randevu Linki',
      icon: Icons.link_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    slug.isEmpty
                        ? 'randevu.mebs.com.tr/—'
                        : 'randevu.mebs.com.tr/$slug',
                    style: TextStyle(
                      fontSize: 13,
                      color: slug.isEmpty
                          ? cs.onSurfaceVariant
                          : cs.onSurface,
                    ),
                  ),
                ),
                Icon(Icons.lock_outline_rounded,
                    size: 15, color: cs.onSurfaceVariant),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Randevu linki sistem tarafından atanır, değiştirilemez.',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: slug.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(
                        text: 'https://randevu.mebs.com.tr/$slug'));
                    _showSnack('Link kopyalandı.');
                  },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Linki kopyala'),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard() {
    final cs = Theme.of(context).colorScheme;
    return _Section(
      title: 'Kimlik Doğrulama',
      icon: Icons.verified_user_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_hasSmsProvider) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sms_failed_outlined, size: 18, color: cs.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
                        children: const [
                          TextSpan(
                            text: 'SMS sağlayıcınız mevcut değildir. '
                                'SMS gönderebilmek için temsilcinizle iletişime geçiniz.\n',
                          ),
                          TextSpan(
                            text: 'mebssoftware@gmail.com',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Opacity(
            opacity: _hasSmsProvider ? 1.0 : 0.45,
            child: IgnorePointer(
              ignoring: !_hasSmsProvider,
              child: _AuthOptionTile(
                value: 'otp',
                groupValue: _authMode,
                icon: Icons.sms_rounded,
                title: 'SMS Kodu (OTP)',
                subtitle: 'Danışanın telefonuna doğrulama kodu gönderilir',
                onChanged: (v) => setState(() => _authMode = v),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _AuthOptionTile(
            value: 'phone_birthdate',
            groupValue: _authMode,
            icon: Icons.cake_rounded,
            title: 'Telefon + Doğum Tarihi',
            subtitle: 'SMS gönderilmez, doğum tarihi ile kimlik doğrulanır',
            onChanged: (v) => setState(() => _authMode = v),
          ),
          if (_authMode == 'otp' && _hasSmsProvider) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: cs.secondary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'OTP kodu gönderimi için kurumun kayıtlı SMS sağlayıcısı kullanılır. '
                    'Mesaj formatı: "[Kurum adı] online sistemine giris kodunuz: XXXXXX"',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRulesCard() {
    return _Section(
      title: 'Rezervasyon Kuralları',
      icon: Icons.rule_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // maxDaysAhead
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('İleri tarih sınırı'),
              Text(
                '$_maxDaysAhead gün',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Slider(
            min: 7,
            max: 90,
            divisions: 83,
            value: _maxDaysAhead.toDouble(),
            label: '$_maxDaysAhead gün',
            onChanged: (v) => setState(() => _maxDaysAhead = v.round()),
          ),
          const Divider(height: 24),
          // minHoursBefore
          const Text('Minimum önceden (saat)'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [0, 1, 2, 4, 6, 12, 24].map((h) {
              return ChoiceChip(
                label: Text(h == 0 ? 'Yok' : '${h}s'),
                selected: _minHoursBefore == h,
                onSelected: (_) =>
                    setState(() => _minHoursBefore = h),
              );
            }).toList(),
          ),
          const Divider(height: 24),
          // slotMinutes
          const Text('Slot aralığı'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [15, 30, 45, 60].map((m) {
              return ChoiceChip(
                label: Text('$m dk'),
                selected: _slotMinutes == m,
                onSelected: (_) => setState(() => _slotMinutes = m),
              );
            }).toList(),
          ),
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aynı gün randevuya izin ver'),
            value: _allowSameDay,
            onChanged: (v) => setState(() => _allowSameDay = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hafta sonu açık'),
            value: _weekendOpen,
            onChanged: (v) => setState(() => _weekendOpen = v),
          ),
        ],
      ),
    );
  }

  Widget _buildDisplayCard() {
    return _Section(
      title: 'Görüntüleme Seçenekleri',
      icon: Icons.visibility_rounded,
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hizmet fiyatlarını göster'),
            subtitle: const Text(
                'Danışan randevu sayfasında hizmet fiyatlarını görebilir'),
            value: _showServicePrices,
            onChanged: (v) => setState(() => _showServicePrices = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hesap ekstresi göster'),
            subtitle: const Text(
                'Danışan bakiye ve ödeme durumunu görebilir'),
            value: _showAccountStatement,
            onChanged: (v) =>
                setState(() => _showAccountStatement = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Personel seçimine izin ver'),
            subtitle: const Text(
                'Danışan randevu sırasında hizmet için tanımlı personeli seçebilir'),
            value: _allowStaffSelection,
            onChanged: (v) =>
                setState(() => _allowStaffSelection = v),
          ),
        ],
      ),
    );
  }

  Widget _buildTextsCard() {
    return _Section(
      title: 'Metin İçerikleri',
      icon: Icons.text_fields_rounded,
      child: Column(
        children: [
          TextField(
            controller: _publicInfoController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Randevu sayfası bilgi metni',
              hintText: 'Randevu öncesi danışanlara gösterilecek bilgi...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _successTextController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Başarı mesajı',
              hintText: 'Randevu alındıktan sonra gösterilecek mesaj...',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiAssistantCard(ColorScheme cs) {
    return _Section(
      title: 'AI Rezervasyon Asistanı',
      icon: Icons.smart_toy_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Aktif/pasif toggle
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              color: _aiAssistantEnabled
                  ? cs.primaryContainer.withValues(alpha: 0.5)
                  : cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _aiAssistantEnabled
                    ? cs.primary.withValues(alpha: 0.35)
                    : cs.outlineVariant,
              ),
            ),
            child: SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              secondary: Icon(
                _aiAssistantEnabled
                    ? Icons.smart_toy_rounded
                    : Icons.smart_toy_outlined,
                color:
                    _aiAssistantEnabled ? cs.primary : cs.onSurfaceVariant,
              ),
              title: Text(
                _aiAssistantEnabled ? 'AI Asistan aktif' : 'AI Asistan pasif',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _aiAssistantEnabled
                      ? cs.onPrimaryContainer
                      : cs.onSurfaceVariant,
                ),
              ),
              subtitle: Text(
                _aiAssistantEnabled
                    ? 'Danışanlar yapay zeka ile randevu alabilir'
                    : 'Randevu sayfasında AI sekmesi gösterilmez',
                style: TextStyle(
                  fontSize: 12,
                  color: _aiAssistantEnabled
                      ? cs.onPrimaryContainer.withValues(alpha: 0.75)
                      : cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
              value: _aiAssistantEnabled,
              onChanged: (v) => setState(() => _aiAssistantEnabled = v),
            ),
          ),

          // Ek talimatlar alanı (yalnızca asistan aktifken gösterilir)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _aiAssistantEnabled
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.tune_rounded,
                              size: 16, color: cs.primary),
                          const SizedBox(width: 8),
                          const Text(
                            'Asistana Özel Talimatlar',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Asistanın nasıl davranacağını, hangi bilgileri '
                        'kullanacağını buraya yazın. Bu bilgiler yalnızca '
                        'AI asistanın sistem promptuna eklenir.',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _aiExtraContextController,
                        maxLines: 6,
                        maxLength: 1500,
                        decoration: const InputDecoration(
                          hintText:
                              'Örnek:\n'
                              '• Cihazlar: Syneron Candela GentleMax Pro, 755nm Alexandrite + 1064nm Nd:YAG\n'
                              '• Müşterileri öncelikle lazer epilasyon hizmetine yönlendir\n'
                              '• 18 yaş altı için velinin yazılı onayı gereklidir\n'
                              '• İlk seans öncesi patch test zorunludur',
                          alignLabelWithHint: true,
                          counterText: '',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${_aiExtraContextController.text.length}/1500',
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Örnek kullanım ipuçları
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color:
                                  cs.secondary.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.lightbulb_outline_rounded,
                                    size: 14, color: cs.secondary),
                                const SizedBox(width: 6),
                                Text(
                                  'Ne yazabilirim?',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSecondaryContainer,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...[
                              'Kullandığınız cihaz/makine marka ve modelleri',
                              'Öncelikli yönlendirmek istediğiniz hizmet',
                              'Yaş sınırı, sağlık uyarısı gibi özel kurallar',
                              'Asistanın vurgulayacağı avantajlar veya kampanyalar',
                              'Seans arası bekleme süresi gibi teknik bilgiler',
                            ].map(
                              (tip) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('• ',
                                        style: TextStyle(
                                            color:
                                                cs.onSecondaryContainer,
                                            fontSize: 12)),
                                    Expanded(
                                      child: Text(
                                        tip,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSecondaryContainer
                                              .withValues(alpha: 0.85),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkingHoursCard(ColorScheme cs) {
    return _Section(
      title: 'Çalışma Saatleri',
      icon: Icons.schedule_rounded,
      child: Column(
        children: [
          for (var i = 1; i <= 7; i++) ...[
            if (i > 1) const Divider(height: 20),
            _DayRow(
              dayName: _dayNames[i]!,
              isOpen: _dayOpen[i] ?? false,
              start: _dayStart[i] ?? '09:00',
              end: _dayEnd[i] ?? '18:00',
              isWeekend: i >= 6,
              onOpenChanged: (v) => setState(() => _dayOpen[i] = v),
              onStartTap: () => _pickTime(i, true),
              onEndTap: () => _pickTime(i, false),
              cs: cs,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClosedDatesCard(ColorScheme cs) {
    final sorted = List<String>.from(_closedDates)..sort();
    return _Section(
      title: 'Kapalı Günler',
      icon: Icons.event_busy_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Kapalı gün eklenmemiş.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sorted.map((d) {
                return Chip(
                  label: Text(_formatClosedDate(d)),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  onDeleted: () =>
                      setState(() => _closedDates.remove(d)),
                );
              }).toList(),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addClosedDate,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Kapalı gün ekle'),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
            top:
                BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSaving ? null : _save,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : const Text('Kaydet',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ─── Private helper widgets ──────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: enabled ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled
              ? cs.primary.withValues(alpha: 0.4)
              : cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Icon(
              enabled
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              key: ValueKey(enabled),
              color: enabled ? cs.primary : cs.onSurfaceVariant,
              size: 44,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enabled ? 'Online randevu aktif' : 'Online randevu pasif',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: enabled
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'Danışanlar online randevu alabilir'
                      : 'Danışanlar randevu alamaz, sayfa kapalıdır',
                  style: TextStyle(
                    fontSize: 12,
                    color: enabled
                        ? cs.onPrimaryContainer.withValues(alpha: 0.75)
                        : cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 19, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _AuthOptionTile extends StatelessWidget {
  const _AuthOptionTile({
    required this.value,
    required this.groupValue,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final String value;
  final String groupValue;
  final IconData icon;
  final String title;
  final String subtitle;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer
              : cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? cs.primary : cs.onSurfaceVariant,
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? cs.onPrimaryContainer
                          : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected
                          ? cs.onPrimaryContainer.withValues(alpha: 0.72)
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded,
                  color: cs.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.dayName,
    required this.isOpen,
    required this.start,
    required this.end,
    required this.isWeekend,
    required this.onOpenChanged,
    required this.onStartTap,
    required this.onEndTap,
    required this.cs,
  });

  final String dayName;
  final bool isOpen;
  final String start;
  final String end;
  final bool isWeekend;
  final ValueChanged<bool> onOpenChanged;
  final VoidCallback onStartTap;
  final VoidCallback onEndTap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            dayName,
            style: TextStyle(
              fontWeight:
                  isOpen ? FontWeight.w600 : FontWeight.w400,
              color: isOpen
                  ? cs.onSurface
                  : cs.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ),
        Switch(
          value: isOpen,
          onChanged: onOpenChanged,
        ),
        const SizedBox(width: 4),
        if (isOpen) ...[
          _TimeChip(
              label: start, onTap: onStartTap, cs: cs),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8),
            child: Text('–',
                style:
                    TextStyle(color: cs.onSurfaceVariant)),
          ),
          _TimeChip(label: end, onTap: onEndTap, cs: cs),
        ] else
          Text(
            'Kapalı',
            style: TextStyle(
                color: cs.onSurfaceVariant, fontSize: 13),
          ),
      ],
    );
  }
}

// ─── Görsel Yükleme Kutusu ────────────────────────────────────────────────────

class _ImageUploadTile extends StatelessWidget {
  const _ImageUploadTile({
    required this.url,
    required this.onUpload,
    required this.onRemove,
    required this.isUploading,
    required this.cs,
    this.captionController,
  });

  final String url;
  final VoidCallback onUpload;
  final VoidCallback onRemove;
  final bool isUploading;
  final ColorScheme cs;
  final TextEditingController? captionController;

  @override
  Widget build(BuildContext context) {
    final hasImage = url.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: isUploading ? null : onUpload,
          child: Container(
            height: 130,
            width: double.infinity,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: isUploading
                ? const Center(child: CircularProgressIndicator())
                : hasImage
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.network(
                              url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Icon(Icons.broken_image_rounded,
                                    color: cs.onSurfaceVariant),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _ImageActionBtn(
                                  icon: Icons.edit_rounded,
                                  onTap: onUpload,
                                  cs: cs,
                                ),
                                const SizedBox(width: 6),
                                _ImageActionBtn(
                                  icon: Icons.delete_rounded,
                                  onTap: onRemove,
                                  cs: cs,
                                  isDelete: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_rounded,
                              size: 32, color: cs.onSurfaceVariant),
                          const SizedBox(height: 6),
                          Text(
                            'Görsel ekle',
                            style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
          ),
        ),
        if (captionController != null) ...[
          const SizedBox(height: 8),
          TextField(
            controller: captionController,
            decoration: const InputDecoration(
              hintText: 'Açıklama (isteğe bağlı)...',
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ],
    );
  }
}

class _ImageActionBtn extends StatelessWidget {
  const _ImageActionBtn({
    required this.icon,
    required this.onTap,
    required this.cs,
    this.isDelete = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme cs;
  final bool isDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isDelete
              ? cs.errorContainer.withValues(alpha: 0.92)
              : cs.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isDelete ? cs.onErrorContainer : cs.onSurface,
        ),
      ),
    );
  }
}

// ─── Saat Chip ────────────────────────────────────────────────────────────────

class _TimeChip extends StatelessWidget {
  const _TimeChip(
      {required this.label,
      required this.onTap,
      required this.cs});

  final String label;
  final VoidCallback onTap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: cs.onPrimaryContainer,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

