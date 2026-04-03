import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

/// Admin paneli — tüm kurumların AI asistanına uygulanacak
/// global sistem talimatlarını yönetir.
/// Firestore: sistem/ai_ayarlari dokümanı kullanılır.
class AiPlatformSettingsPage extends StatefulWidget {
  const AiPlatformSettingsPage({super.key});

  @override
  State<AiPlatformSettingsPage> createState() =>
      _AiPlatformSettingsPageState();
}

class _AiPlatformSettingsPageState extends State<AiPlatformSettingsPage> {
  static const _docPath = 'sistem/ai_ayarlari';

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  // Global sistem promptu için controller
  final _globalPromptCtrl = TextEditingController();

  // Örnek talimatları göster/gizle
  bool _showExamples = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _globalPromptCtrl.dispose();
    super.dispose();
  }

  /// Firestore'dan global AI ayarlarını yükler.
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final doc = await FirebaseFirestore.instance.doc(_docPath).get();
      if (doc.exists) {
        final data = doc.data() ?? <String, dynamic>{};
        _globalPromptCtrl.text =
            (data['globalSystemPrompt'] as String?) ?? '';
      }
    } catch (e) {
      _errorMessage = 'Ayarlar yüklenemedi: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Global AI ayarlarını Firestore'a kaydeder.
  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.doc(_docPath).set(
        {
          'globalSystemPrompt': _globalPromptCtrl.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Global AI ayarları kaydedildi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydetme başarısız: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Platform Ayarları'),
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
                        // ── Bilgi kartı ──────────────────────────────────
                        _InfoCard(cs: cs),
                        const SizedBox(height: 16),

                        // ── Global sistem promptu ────────────────────────
                        _Section(
                          title: 'Global Sistem Talimatları',
                          icon: Icons.psychology_rounded,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Buraya girilen talimatlar tüm kurumların AI '
                                'asistanına otomatik olarak eklenir. '
                                'Her kurum kendi özel talimatlarını da '
                                'Online Randevu Ayarları bölümünden girebilir.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _globalPromptCtrl,
                                maxLines: 12,
                                decoration: InputDecoration(
                                  labelText: 'Global sistem talimatları',
                                  hintText:
                                      'Tüm kurumlara uygulanacak genel kurallar '
                                      've davranış talimatları...',
                                  alignLabelWithHint: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ── Örnek talimatlar ─────────────────────────────
                        _ExamplesSection(
                          cs: cs,
                          expanded: _showExamples,
                          onToggle: () =>
                              setState(() => _showExamples = !_showExamples),
                          onInsert: (text) {
                            final current = _globalPromptCtrl.text.trim();
                            _globalPromptCtrl.text =
                                current.isEmpty ? text : '$current\n$text';
                          },
                        ),
                      ],
                    ),

                    // ── Kaydet butonu ─────────────────────────────────────
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _SaveBar(isSaving: _isSaving, onSave: _save, cs: cs),
                    ),
                  ],
                ),
    );
  }
}

// ─── Bilgi Kartı ─────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.admin_panel_settings_rounded,
                  color: cs.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Platform Düzeyinde AI Kontrolü',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Bu sayfada girilen talimatlar, sisteme kayıtlı tüm kurumların '
            'AI asistanına en üst öncelikle eklenir. '
            'Platform genelinde uyulmasını istediğiniz kuralları buraya yazın.',
            style: TextStyle(
              fontSize: 13,
              color: cs.onPrimaryContainer.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 10),
          // Öncelik sırası gösterimi
          _PriorityRow(
            items: const [
              '1. Global Talimatlar (bu sayfa)',
              '2. Kurum Bilgileri (Firestore)',
              '3. Kuruma Özel Talimatlar (yönetici)',
            ],
            cs: cs,
          ),
        ],
      ),
    );
  }
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({required this.items, required this.cs});
  final List<String> items;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Prompt öncelik sırası:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 4),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 2),
            child: Text(
              item,
              style: TextStyle(
                fontSize: 12,
                color: cs.onPrimaryContainer.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Örnek Talimatlar Bölümü ─────────────────────────────────────────────────

class _ExamplesSection extends StatelessWidget {
  const _ExamplesSection({
    required this.cs,
    required this.expanded,
    required this.onToggle,
    required this.onInsert,
  });

  final ColorScheme cs;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(String text) onInsert;

  static const _examples = [
    (
      baslik: 'Rakip kurum yasağı',
      icerik:
          'Hiçbir koşulda rakip kurumlardan veya diğer işletmelerden bahsetme. '
              'Yalnızca kendi kurumunun hizmetlerini tanıt.',
    ),
    (
      baslik: 'Fiyat pazarlığı yasağı',
      icerik:
          'Fiyat indirimi veya pazarlık konusunda asla taahhütte bulunma. '
              'Fiyat soruşturmalarını kurumla iletişime geçmeye yönlendir.',
    ),
    (
      baslik: 'Önce randevuya yönlendir',
      icerik:
          'Müşteri herhangi bir hizmet hakkında soru sorarsa, '
              'önce randevu almaya teşvik et. Detaylı bilgiyi randevu sonrasına bırak.',
    ),
    (
      baslik: 'Profesyonel ton',
      icerik:
          'Her zaman samimi ama profesyonel bir dil kullan. '
              'Argo, aşırı samimi veya gayri resmi ifadelerden kaçın.',
    ),
    (
      baslik: 'Tıbbi tavsiyeden kaçın',
      icerik:
          'Tanı, tedavi veya ilaç önerisi gibi tıbbi tavsiyelerde bulunma. '
              'Sağlık konularında doktora yönlendir.',
    ),
    (
      baslik: 'Veri gizliliği',
      icerik:
          'Müşteri verilerini asla başka biriyle paylaşma, üçüncü taraf '
              'servislere yönlendirme. Gizlilik politikasına uy.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          // Başlık / aç-kapat
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline_rounded,
                      size: 19, color: cs.secondary),
                  const SizedBox(width: 8),
                  Text(
                    'Örnek Talimatlar',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const Spacer(),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // Örnekler listesi
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tıklayarak metin alanına ekleyin:',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _examples.map((ex) {
                      return ActionChip(
                        avatar: Icon(Icons.add_rounded,
                            size: 16, color: cs.primary),
                        label: Text(ex.baslik,
                            style: const TextStyle(fontSize: 12)),
                        onPressed: () => onInsert(ex.icerik),
                        tooltip: ex.icerik,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Kaydet Butonu ───────────────────────────────────────────────────────────

class _SaveBar extends StatelessWidget {
  const _SaveBar(
      {required this.isSaving,
      required this.onSave,
      required this.cs});

  final bool isSaving;
  final VoidCallback onSave;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
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
        onPressed: isSaving ? null : onSave,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: isSaving
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

// ─── Section Widget ──────────────────────────────────────────────────────────

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
