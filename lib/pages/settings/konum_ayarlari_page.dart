import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/institution_controller.dart';
import '../../controllers/user_controller.dart';
import '../../utils/permission_utils.dart';
import 'konum_picker_page.dart';

class KonumAyarlariPage extends StatefulWidget {
  const KonumAyarlariPage({super.key});

  @override
  State<KonumAyarlariPage> createState() => _KonumAyarlariPageState();
}

class _KonumAyarlariPageState extends State<KonumAyarlariPage> {
  final _user = Get.find<UserController>();
  final _institution = Get.find<InstitutionController>();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  final _ilController = TextEditingController();
  final _districtController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();

  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!isManagerUser(_user.data)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu sayfaya sadece yöneticiler erişebilir.'),
          ),
        );
        Navigator.of(context).maybePop();
        return;
      }
      _load();
    });
  }

  @override
  void dispose() {
    _ilController.dispose();
    _districtController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String _institutionId() =>
      (_institution.data['kurumkodu'] ?? '').toString();

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

      _ilController.text = (data['il'] as String?) ?? '';
      _districtController.text =
          (data['district'] as String?) ?? (data['ilce'] as String?) ?? '';
      _addressController.text =
          (data['address'] as String?) ?? (data['adres'] as String?) ?? '';
      _phoneController.text = (data['phone'] as String?) ??
          (data['ilgiliKisiTelefon'] as String?) ??
          '';
      _latitude = (data['latitude'] as num?)?.toDouble();
      _longitude = (data['longitude'] as num?)?.toDouble();

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Bilgiler yüklenemedi: $e';
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
      final payload = <String, dynamic>{
        'il': _ilController.text.trim(),
        'district': _districtController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
      };
      if (_latitude != null && _longitude != null) {
        payload['latitude'] = _latitude;
        payload['longitude'] = _longitude;
      }
      await FirebaseFirestore.instance
          .collection('kurumlar')
          .doc(id)
          .set(payload, SetOptions(merge: true));
      if (!mounted) return;
      _showSnack('Konum bilgileri kaydedildi.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Kaydetme başarısız: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _openPicker() async {
    final initial = (_latitude != null && _longitude != null)
        ? LatLng(_latitude!, _longitude!)
        : null;
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => KonumPickerPage(initialLocation: initial),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _latitude = result.latitude;
        _longitude = result.longitude;
      });
    }
  }

  Future<void> _openInMaps() async {
    Uri? uri;
    if (_latitude != null && _longitude != null) {
      uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$_latitude,$_longitude');
    }
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showSnack('Harita açılamadı.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Konum Ayarları'),
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
                        _buildAddressCard(cs),
                        const SizedBox(height: 16),
                        _buildLocationCard(cs),
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

  Widget _buildAddressCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on_rounded, size: 19, color: cs.primary),
                const SizedBox(width: 8),
                const Text(
                  'Kurum Adresi',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ilController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'İl',
                hintText: 'Örn: İstanbul',
                prefixIcon: Icon(Icons.location_city_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _districtController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'İlçe',
                hintText: 'Örn: Kadıköy',
                prefixIcon: Icon(Icons.map_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Açık Adres',
                hintText: 'Mahalle, sokak, bina numarası...',
                alignLabelWithHint: true,
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 44),
                  child: Icon(Icons.home_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefon',
                hintText: '0212 000 00 00',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(ColorScheme cs) {
    final hasLocation = _latitude != null && _longitude != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pin_drop_rounded, size: 19, color: cs.primary),
                const SizedBox(width: 8),
                const Text(
                  'Harita Konumu',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Haritadan konum seçerek danışanların kurumunuzu kolayca bulmasını sağlayabilirsiniz.',
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (hasLocation) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color:
                          cs.primary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on_rounded,
                        color: cs.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Konum seçildi',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: cs.onPrimaryContainer,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onPrimaryContainer
                                  .withValues(alpha: 0.7),
                              fontFeatures: const [],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openPicker,
                      icon: const Icon(Icons.edit_location_alt_rounded,
                          size: 18),
                      label: const Text('Değiştir'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openInMaps,
                      icon: const Icon(Icons.open_in_new_rounded,
                          size: 18),
                      label: const Text('Haritada Aç'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              OutlinedButton.icon(
                onPressed: _openPicker,
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Haritadan Konum Seç'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSaveBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : const Text(
                'Kaydet',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}
