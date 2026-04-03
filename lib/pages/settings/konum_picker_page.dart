import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class KonumPickerPage extends StatefulWidget {
  const KonumPickerPage({super.key, this.initialLocation});

  final LatLng? initialLocation;

  @override
  State<KonumPickerPage> createState() => _KonumPickerPageState();
}

class _KonumPickerPageState extends State<KonumPickerPage> {
  static const _defaultCenter = LatLng(39.9334, 32.8597); // Ankara

  late final MapController _mapController;
  final _searchController = TextEditingController();

  LatLng? _selected;
  bool _isSearching = false;
  List<_NominatimResult> _results = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selected = widget.initialLocation;
    _searchController.addListener(_onSearchChanged);

    // flutter_map'te initialCenter bazen geç uygulanır;
    // harita render edildikten sonra move() ile konumu garantile.
    if (widget.initialLocation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(widget.initialLocation!, 15);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController.dispose();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {}); // clear butonunu reaktif yap
    _debounce?.cancel();
    final text = _searchController.text.trim();
    if (text.isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), () => _search(text));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isSearching = true;
      _results = [];
    });
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query.trim(),
        'format': 'json',
        'limit': '6',
        'countrycodes': 'tr',
        'addressdetails': '0',
      });
      final res = await http
          .get(uri, headers: {
            'User-Agent': 'kurumtakip/1.0 (contact@mebs.com.tr)',
            'Accept-Language': 'tr',
          })
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && mounted) {
        final list = jsonDecode(res.body) as List<dynamic>;
        setState(() {
          _results = list
              .map((e) {
                final m = e as Map<String, dynamic>;
                return _NominatimResult(
                  label: (m['display_name'] as String?) ?? '',
                  lat: double.tryParse(
                          m['lat']?.toString() ?? '') ??
                      0,
                  lng: double.tryParse(
                          m['lon']?.toString() ?? '') ??
                      0,
                );
              })
              .where((r) => r.label.isNotEmpty)
              .toList();
        });
      }
    } on TimeoutException {
      if (mounted) _showToast('Arama zaman aşımına uğradı.');
    } catch (e) {
      if (mounted) _showToast('Arama hatası: $e');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _showToast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  void _pickResult(_NominatimResult r) {
    final point = LatLng(r.lat, r.lng);
    setState(() {
      _selected = point;
      _results = [];
      _searchController.clear();
    });
    _mapController.move(point, 15);
  }

  void _onMapTap(TapPosition _, LatLng point) {
    setState(() {
      _selected = point;
      _results = [];
    });
  }

  void _confirm() => Navigator.of(context).pop(_selected);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initialCenter =
        widget.initialLocation ?? _defaultCenter;
    final initialZoom = widget.initialLocation != null ? 15.0 : 6.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Konum Seç'),
        actions: [
          if (_selected != null)
            TextButton(
              onPressed: _confirm,
              child: Text(
                'Seç',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // ── Harita ──────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: initialZoom,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.mebs.kurumtakip',
              ),
              if (_selected != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selected!,
                      width: 44,
                      height: 44,
                      alignment: Alignment.bottomCenter,
                      child: Icon(
                        Icons.location_pin,
                        color: cs.error,
                        size: 44,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ── Arama kutusu ────────────────────────────────────────
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _search,
                    decoration: InputDecoration(
                      hintText: 'Adres veya yer ara...',
                      prefixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            )
                          : const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _results = []);
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).cardColor,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
                if (_results.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          MediaQuery.of(context).size.height * 0.35,
                    ),
                    child: Material(
                      elevation: 4,
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(12)),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _results.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = _results[i];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.location_on_outlined,
                              size: 20,
                              color: cs.primary,
                            ),
                            title: Text(
                              r.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            onTap: () => _pickResult(r),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Alt buton / ipucu ──────────────────────────────────
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: _selected == null
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Haritaya dokunarak konum seçin',
                        style: TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _confirm,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text(
                      'Bu Konumu Seç',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NominatimResult {
  const _NominatimResult({
    required this.label,
    required this.lat,
    required this.lng,
  });
  final String label;
  final double lat;
  final double lng;
}
