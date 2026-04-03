import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/date_time_utils.dart';
import '../../models/booking_models.dart';
import '../../models/booking_settings.dart';
import '../../models/org_public_profile.dart';
import '../../models/org_service.dart';
import '../../services/booking_api_service.dart';
import '../../services/customer_service.dart';
import '../../services/org_public_service.dart';
import '../../services/phone_verification_service.dart';
import '../controllers/booking_flow_controller.dart';
import '../widgets/ai_booking_assistant.dart';
import '../widgets/booking_status_views.dart';

class OrgBookingPage extends StatefulWidget {
  const OrgBookingPage({super.key, required this.slug});

  final String slug;

  @override
  State<OrgBookingPage> createState() => _OrgBookingPageState();
}

class _OrgBookingPageState extends State<OrgBookingPage> {
  late final BookingFlowController controller;
  bool _chatOpen = false;

  @override
  void initState() {
    super.initState();
    controller = BookingFlowController(
      orgService: OrgPublicService(),
      customerService: CustomerService(),
      bookingApiService: BookingApiService(),
      phoneVerification: BypassPhoneVerificationService(),
    );
    controller.initialize(widget.slug);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.isLoading) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (controller.org == null) {
          return const Scaffold(
            body: BookingCenteredMessage(
              title: 'Kurum bulunamadı',
              message:
                  'Bağlantı hatalı olabilir. Lütfen kurumunuzla iletişime geçin.',
            ),
          );
        }

        if (!controller.org!.bookingEnabled ||
            !controller.org!.bookingSettings.enabled) {
          return const Scaffold(
            body: BookingCenteredMessage(
              title: 'Online randevu kapalı',
              message:
                  'Bu kurum şu anda online randevu kabul etmiyor.',
            ),
          );
        }

        final aiEnabled =
            controller.org!.bookingSettings.aiAssistantEnabled;
        final aiExtraContext =
            controller.org!.bookingSettings.aiExtraContext;

        final isSuccess = controller.step == BookingStep.success;

        final formBody = SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _OrgInfoCard(controller: controller),
                    if (!isSuccess) ...[
                      const SizedBox(height: 12),
                      _BookingStepIndicator(step: controller.step),
                    ],
                    if (controller.customer != null && !isSuccess) ...[
                      const SizedBox(height: 12),
                      _CustomerWelcomeCard(controller: controller),
                    ],
                    const SizedBox(height: 12),
                    if (controller.errorMessage != null)
                      _ErrorBox(message: controller.errorMessage!),
                    _buildStepView(),
                    // Sohbet penceresi açıkken altta boşluk bırak
                    if (aiEnabled) const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ),
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(controller.org!.name),
            centerTitle: false,
          ),
          body: Stack(
            children: [
              // ── Ana içerik: klasik rezervasyon formu ──────────────────────
              formBody,

              // ── Yüzen AI sohbet paneli (yalnızca AI açıksa) ───────────────
              if (aiEnabled)
                _FloatingChatPanel(
                  isOpen: _chatOpen,
                  onToggle: () => setState(() => _chatOpen = !_chatOpen),
                  orgProfile: controller.org!,
                  services: controller.services,
                  bookingApiService: BookingApiService(),
                  bookingSettings: controller.org!.bookingSettings,
                  workingHours: controller.org!.workingHours,
                  aiExtraContext: aiExtraContext,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStepView() {
    switch (controller.step) {
      case BookingStep.phone:
        return _PhoneStep(controller: controller);
      case BookingStep.customer:
        return _CustomerStep(controller: controller);
      case BookingStep.service:
        return _ServiceStep(controller: controller);
      case BookingStep.dateTime:
        return _DateTimeStep(controller: controller);
      case BookingStep.confirm:
        return _ConfirmStep(controller: controller);
      case BookingStep.success:
        return _SuccessStep(controller: controller);
    }
  }
}

// ─── Floating Chat Panel ─────────────────────────────────────────────────────

class _FloatingChatPanel extends StatefulWidget {
  const _FloatingChatPanel({
    required this.isOpen,
    required this.onToggle,
    required this.orgProfile,
    required this.services,
    required this.bookingApiService,
    required this.bookingSettings,
    required this.workingHours,
    this.aiExtraContext,
  });

  final bool isOpen;
  final VoidCallback onToggle;
  final OrgPublicProfile orgProfile;
  final List<OrgService> services;
  final BookingApiService bookingApiService;
  final BookingSettings bookingSettings;
  final WorkingHours workingHours;
  final String? aiExtraContext;

  @override
  State<_FloatingChatPanel> createState() => _FloatingChatPanelState();
}

class _FloatingChatPanelState extends State<_FloatingChatPanel> {
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isWide = screenWidth > 600;

    // Panel boyutları
    final panelWidth = isWide ? 380.0 : screenWidth - 32.0;
    final panelHeight = isWide
        ? (screenHeight * 0.65).clamp(400.0, 560.0)
        : screenHeight * 0.6;

    return Positioned(
      right: 16,
      bottom: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sohbet paneli ─────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            alignment: Alignment.bottomRight,
            child: widget.isOpen
                ? Container(
                    width: panelWidth,
                    height: panelHeight,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Column(
                        children: [
                          // Panel başlık çubuğu
                          Container(
                            height: 48,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.smart_toy_rounded,
                                    size: 18,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'AI Randevu Asistanı',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.close,
                                      size: 18,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary),
                                  onPressed: widget.onToggle,
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Kapat',
                                ),
                              ],
                            ),
                          ),
                          // AI asistan içeriği
                          Expanded(
                            child: AiBookingAssistant(
                              orgProfile: widget.orgProfile,
                              services: widget.services,
                              bookingApiService: widget.bookingApiService,
                              bookingSettings: widget.bookingSettings,
                              workingHours: widget.workingHours,
                              aiExtraContext: widget.aiExtraContext,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // ── FAB butonu ────────────────────────────────────────────────
          FloatingActionButton.extended(
            onPressed: widget.onToggle,
            icon: Icon(
              widget.isOpen
                  ? Icons.chat_bubble_rounded
                  : Icons.smart_toy_rounded,
            ),
            label: Text(widget.isOpen ? 'Kapat' : 'AI Asistan'),
            elevation: 4,
          ),
        ],
      ),
    );
  }
}

// ─── Step Indicator ──────────────────────────────────────────────────────────

class _BookingStepIndicator extends StatelessWidget {
  const _BookingStepIndicator({required this.step});

  final BookingStep step;

  static const _labels = ['Giriş', 'Hizmet', 'Tarih', 'Onay'];

  int get _currentIndex {
    switch (step) {
      case BookingStep.phone:
      case BookingStep.customer:
        return 0;
      case BookingStep.service:
        return 1;
      case BookingStep.dateTime:
        return 2;
      case BookingStep.confirm:
        return 3;
      case BookingStep.success:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = _currentIndex;

    return Row(
      children: List.generate(_labels.length * 2 - 1, (i) {
        if (i.isOdd) {
          // Connector line
          final stepIdx = (i - 1) ~/ 2;
          final done = stepIdx < current - 1;
          final active = stepIdx == current - 1;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 2,
              color: (done || active) ? cs.primary : cs.outlineVariant,
            ),
          );
        }
        // Step circle
        final idx = i ~/ 2;
        final done = idx < current;
        final active = idx == current;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? cs.primary
                    : active
                        ? cs.primaryContainer
                        : cs.surfaceContainerHighest,
                border: Border.all(
                  color: (done || active)
                      ? cs.primary
                      : cs.outlineVariant,
                  width: active ? 2 : 1,
                ),
              ),
              child: Center(
                child: done
                    ? Icon(Icons.check_rounded,
                        size: 14, color: cs.onPrimary)
                    : Text(
                        '${idx + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: active
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _labels[idx],
              style: TextStyle(
                fontSize: 10,
                fontWeight: active || done
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: active || done
                    ? cs.primary
                    : cs.onSurfaceVariant,
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ─── Org Info Card ───────────────────────────────────────────────────────────

class _OrgInfoCard extends StatelessWidget {
  const _OrgInfoCard({required this.controller});

  final BookingFlowController controller;

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final org = controller.org!;
    final cs = Theme.of(context).colorScheme;
    final hasLogo = (org.logoUrl ?? '').isNotEmpty;

    // Adres satırı: adres, ilçe, il
    final addressParts = [
      if ((org.address ?? '').isNotEmpty) org.address!,
      if ((org.district ?? '').isNotEmpty) org.district!,
      if ((org.il ?? '').isNotEmpty) org.il!,
    ];
    final fullAddress = addressParts.join(', ');

    // Harita linki
    String? mapsUrl;
    if (org.latitude != null && org.longitude != null) {
      mapsUrl =
          'https://www.google.com/maps/search/?api=1&query=${org.latitude},${org.longitude}';
    } else if ((org.mapsLink ?? '').isNotEmpty) {
      mapsUrl = org.mapsLink;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Başlık bandı ──────────────────────────────────────
          Container(
            color: cs.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (hasLogo) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      org.logoUrl!,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        org.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      if (addressParts.length > 1) ...[
                        const SizedBox(height: 2),
                        Text(
                          [
                            if ((org.district ?? '').isNotEmpty) org.district!,
                            if ((org.il ?? '').isNotEmpty) org.il!,
                          ].join(' / '),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onPrimaryContainer.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Tanıtım görselleri ────────────────────────────────
          Builder(builder: (context) {
            final banners = org.bookingSettings.bannerImages
                .where((b) => b.url.isNotEmpty)
                .toList();
            if (banners.isEmpty) return const SizedBox.shrink();
            return SizedBox(
              height: banners.any((b) => b.caption.isNotEmpty) ? 186 : 158,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: banners.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final b = banners[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          b.url,
                          width: 180,
                          height: 130,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 180,
                            height: 130,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.broken_image_rounded,
                                color: cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                      if (b.caption.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        SizedBox(
                          width: 180,
                          child: Text(
                            b.caption,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            );
          }),

          // ── İletişim & konum bilgileri ─────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((org.phone ?? '').isNotEmpty)
                  _OrgInfoRow(
                    icon: Icons.phone_rounded,
                    text: org.phone!,
                    onTap: () => _launch('tel:${org.phone!}'),
                    cs: cs,
                  ),
                if (fullAddress.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _OrgInfoRow(
                    icon: Icons.location_on_rounded,
                    text: fullAddress,
                    cs: cs,
                  ),
                ],
                if (mapsUrl != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _launch(mapsUrl!),
                    icon: const Icon(Icons.map_rounded, size: 16),
                    label: const Text('Haritada Aç'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                  ),
                ],
                if ((org.bookingSettings.publicInfoText ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: cs.secondary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 15,
                            color: cs.secondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            org.bookingSettings.publicInfoText!,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrgInfoRow extends StatelessWidget {
  const _OrgInfoRow({
    required this.icon,
    required this.text,
    required this.cs,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final ColorScheme cs;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: cs.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: onTap != null ? cs.primary : cs.onSurfaceVariant,
              decoration:
                  onTap != null ? TextDecoration.underline : null,
            ),
          ),
        ),
      ],
    );
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: content);
    }
    return content;
  }
}

// ─── Step 1: Phone ───────────────────────────────────────────────────────────

class _PhoneStep extends StatefulWidget {
  const _PhoneStep({required this.controller});

  final BookingFlowController controller;

  @override
  State<_PhoneStep> createState() => _PhoneStepState();
}

class _PhoneStepState extends State<_PhoneStep> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  DateTime? _birthDate;
  bool _otpRequested = false;
  int _resendCooldown = 0;
  Timer? _resendTimer;

  void _startResendCooldown() {
    _resendCooldown = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) t.cancel();
      });
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authMode =
        widget.controller.org?.bookingSettings.authMode ?? 'phone_birthdate';
    final otpMode = authMode == 'otp';
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StepHeader(
              index: 1,
              title: otpMode
                  ? 'Telefon doğrulama'
                  : 'Kimlik doğrulama',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefon numaranız',
                hintText: '05xx xxx xx xx',
                prefixIcon: Icon(Icons.phone_rounded),
              ),
            ),
            if (!otpMode) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final selected = await showDatePicker(
                    context: context,
                    firstDate: DateTime(1940),
                    lastDate: DateTime.now(),
                    initialDate: DateTime(2000),
                  );
                  if (mounted) setState(() => _birthDate = selected);
                },
                icon: const Icon(Icons.cake_rounded, size: 18),
                label: Text(
                  _birthDate == null
                      ? 'Doğum tarihinizi seçin'
                      : 'Doğum tarihi: ${DateTimeUtils.formatDate(_birthDate!)}',
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (otpMode) ...[
              ElevatedButton.icon(
                onPressed: widget.controller.isSubmitting
                    ? null
                    : () async {
                        final phone = _phoneController.text.trim();
                        if (phone.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Lütfen telefon numaranızı girin.')),
                          );
                          return;
                        }
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await widget.controller.requestOtp(phone);
                          if (mounted) {
                            setState(() => _otpRequested = true);
                            _startResendCooldown();
                          }
                        } catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text(e.toString())),
                          );
                        }
                      },
                icon: widget.controller.isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: const Text('Kod gönder'),
              ),
              if (_otpRequested) ...[
                const SizedBox(height: 8),
                Text(
                  'SMS kodunuz gönderildi. Lütfen kontrol edin.',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'SMS kodu',
                    prefixIcon: Icon(Icons.lock_rounded),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: widget.controller.isSubmitting
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await widget.controller
                              .verifyOtp(_codeController.text);
                          if (!ok) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Kod hatalı. Lütfen tekrar deneyin.')),
                            );
                          }
                        },
                  child: const Text('Kodu onayla'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _resendCooldown > 0
                      ? null
                      : () {
                          setState(() {
                            _otpRequested = false;
                            _codeController.clear();
                          });
                        },
                  child: Text(
                    _resendCooldown > 0
                        ? 'Tekrar gönder ($_resendCooldown sn)'
                        : 'Kodu tekrar gönder',
                  ),
                ),
              ],
            ] else ...[
              ElevatedButton(
                onPressed: () async {
                  if (_birthDate == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Lütfen doğum tarihinizi seçin.')),
                    );
                    return;
                  }
                  await widget.controller
                      .continueWithoutOtpWithBirthDate(
                    inputPhone: _phoneController.text,
                    birthDate: _birthDate!,
                  );
                },
                child: const Text('Devam et'),
              ),
            ],
            if (widget.controller.errorMessage != null) ...[
              const SizedBox(height: 12),
              _InlineError(
                  message: widget.controller.errorMessage!, cs: cs),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Step 2: Customer Form ───────────────────────────────────────────────────

class _CustomerStep extends StatefulWidget {
  const _CustomerStep({required this.controller});

  final BookingFlowController controller;

  @override
  State<_CustomerStep> createState() => _CustomerStepState();
}

class _CustomerStepState extends State<_CustomerStep> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  DateTime? _birthDate;
  String _gender = 'BELİRTİLMEDİ';

  @override
  void initState() {
    super.initState();
    _birthDate = widget.controller.inputBirthDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _StepHeader(index: 1, title: 'Bilgilerinizi girin'),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Ad Soyad',
                prefixIcon: Icon(Icons.person_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Telefon',
                hintText: widget.controller.phone,
                prefixIcon: const Icon(Icons.phone_rounded),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(
                labelText: 'Cinsiyet',
                prefixIcon: Icon(Icons.wc_rounded),
              ),
              items: const [
                DropdownMenuItem(value: 'KADIN', child: Text('Kadın')),
                DropdownMenuItem(value: 'ERKEK', child: Text('Erkek')),
                DropdownMenuItem(
                    value: 'BELİRTİLMEDİ',
                    child: Text('Belirtmek istemiyorum')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _gender = v);
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final selected = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1940),
                  lastDate: DateTime.now(),
                  initialDate: _birthDate ?? DateTime(2000),
                );
                if (mounted) setState(() => _birthDate = selected);
              },
              icon: const Icon(Icons.cake_rounded, size: 18),
              label: Text(_birthDate == null
                  ? 'Doğum tarihi seç'
                  : 'Doğum tarihi: ${DateTimeUtils.formatDate(_birthDate!)}'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Adres (opsiyonel)',
                prefixIcon: Icon(Icons.location_on_rounded),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () async {
                if (_nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Ad soyad zorunludur.')),
                  );
                  return;
                }
                if (_birthDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Doğum tarihi zorunludur.')),
                  );
                  return;
                }
                await widget.controller.saveCustomer(
                  fullName: _nameController.text.trim(),
                  birthDate: _birthDate,
                  gender: _gender,
                  address: _addressController.text.trim(),
                );
              },
              child: const Text('Kaydet ve devam et'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step 3: Service ─────────────────────────────────────────────────────────

class _ServiceStep extends StatelessWidget {
  const _ServiceStep({required this.controller});

  final BookingFlowController controller;

  @override
  Widget build(BuildContext context) {
    final allowStaff =
        controller.org?.bookingSettings.allowStaffSelection == true;
    final serviceSelected = controller.selectedService != null;
    final showStaffSection = allowStaff && serviceSelected;
    final showNextButton = showStaffSection;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _StepHeader(index: 2, title: 'Hizmet seçin'),
            const SizedBox(height: 16),
            _PastReservationsSection(controller: controller),
            // Paketler
            if (controller.customerPackages.isNotEmpty) ...[
              _CustomerPackagesSection(controller: controller),
              const SizedBox(height: 4),
            ],
            // Bireysel / paket dışı hizmetler
            if (controller.services.isNotEmpty)
              _NonPackageServicesSection(controller: controller)
            else if (controller.customerPackages.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Bu kurum için aktif hizmet bulunamadı.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            // Personel seçimi (servis seçilince görünür)
            if (showStaffSection)
              _StaffSelectionSection(controller: controller),
            // Personel seçimi aktifse devam butonu burada
            if (showNextButton) ...[
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: controller.nextFromService,
                child: const Text('Devam et'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Customer Packages Section ────────────────────────────────────────────────

class _CustomerPackagesSection extends StatefulWidget {
  const _CustomerPackagesSection({required this.controller});
  final BookingFlowController controller;

  @override
  State<_CustomerPackagesSection> createState() =>
      _CustomerPackagesSectionState();
}

class _CustomerPackagesSectionState extends State<_CustomerPackagesSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final packages = widget.controller.customerPackages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.inventory_2_rounded, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Paketlerim (${packages.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 20,
                  color: cs.primary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          ...packages.map((pkg) => _PackageCard(pkg: pkg, controller: widget.controller)),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.pkg, required this.controller});

  final CustomerPackage pkg;
  final BookingFlowController controller;

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  void _showOperationSheet(BuildContext context) {
    final usableOps = pkg.islemler.where((op) => op.hasRemaining).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.inventory_2_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pkg.paketAdi,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                        Text('Randevu almak istediğiniz işlemi seçin',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...usableOps.map((op) {
                final progress = op.sinirsiz || op.seansSayisi <= 0
                    ? 1.0
                    : op.kalanSeans / op.seansSayisi;
                return Column(
                  children: [
                    ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      leading: Icon(Icons.spa_rounded,
                          color: cs.primary, size: 20),
                      title: Text(op.operationName,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text(
                        op.sinirsiz
                            ? 'Sınırsız seans  •  ${op.yapilanSeans} yapıldı'
                            : '${op.kalanSeans} seans kaldı',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      trailing: Icon(Icons.arrow_forward_ios_rounded,
                          size: 14, color: cs.outline),
                      onTap: () {
                        final service = controller.resolveServiceForPackageOp(op);
                        controller.selectServiceFromPackage(
                          service: service,
                          packageId: pkg.id,
                          packageName: pkg.paketAdi,
                          operationId: op.operationId,
                        );
                        Navigator.pop(ctx);
                        final allowStaffSelection =
                            controller.org?.bookingSettings.allowStaffSelection == true;
                        if (!allowStaffSelection) {
                          controller.nextFromService();
                        }
                      },
                    ),
                    if (!op.sinirsiz && op.seansSayisi > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor:
                                cs.outlineVariant.withValues(alpha: 0.3),
                            valueColor: AlwaysStoppedAnimation(
                                Colors.green.shade600),
                          ),
                        ),
                      ),
                  ],
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalSessions =
        pkg.islemler.fold<int>(0, (s, o) => s + (o.sinirsiz ? 0 : o.seansSayisi));
    final doneSessions =
        pkg.islemler.fold<int>(0, (s, o) => s + o.yapilanSeans);
    final remainingSessions =
        pkg.islemler.fold<int>(0, (s, o) => s + (o.sinirsiz ? 0 : o.kalanSeans));
    final hasSinirsiz = pkg.islemler.any((o) => o.sinirsiz);
    final hasUsable = pkg.hasUsableOps;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Paket başlığı ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.45),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        pkg.paketAdi,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (pkg.suresiz)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Süresiz',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      )
                    else if (pkg.bitisTarihi != null)
                      Text(
                        'Son: ${_fmtDate(pkg.bitisTarihi!)}',
                        style: TextStyle(
                            fontSize: 11, color: cs.onPrimaryContainer.withValues(alpha: 0.7)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // Stats row
                Row(
                  children: [
                    _StatBadge(
                        label: 'Toplam',
                        value: hasSinirsiz ? '∞' : '$totalSessions'),
                    const SizedBox(width: 6),
                    _StatBadge(label: 'Yapılan', value: '$doneSessions'),
                    const SizedBox(width: 6),
                    _StatBadge(
                        label: 'Kalan',
                        value: hasSinirsiz ? '∞' : '$remainingSessions',
                        highlight: hasUsable),
                  ],
                ),
              ],
            ),
          ),
          // ── İşlem listesi ──────────────────────────────────────────
          ...pkg.islemler.map((op) {
            final progress = op.sinirsiz || op.seansSayisi <= 0
                ? 1.0
                : op.yapilanSeans / op.seansSayisi;
            final disabled = !op.hasRemaining;
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        disabled
                            ? Icons.remove_circle_outline_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 15,
                        color: disabled
                            ? cs.outline.withValues(alpha: 0.5)
                            : Colors.green.shade600,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          op.operationName,
                          style: TextStyle(
                            fontSize: 13,
                            color: disabled
                                ? cs.onSurface.withValues(alpha: 0.4)
                                : cs.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        op.sinirsiz
                            ? '${op.yapilanSeans} yapıldı'
                            : '${op.yapilanSeans}/${op.seansSayisi}',
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant.withValues(
                                alpha: disabled ? 0.4 : 0.8)),
                      ),
                    ],
                  ),
                  if (!op.sinirsiz && op.seansSayisi > 0) ...[
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor:
                            cs.outlineVariant.withValues(alpha: 0.25),
                        valueColor: AlwaysStoppedAnimation(
                          disabled
                              ? cs.outlineVariant
                              : Colors.green.shade600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            );
          }),
          // ── Randevu Al butonu ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: FilledButton.icon(
              onPressed:
                  hasUsable ? () => _showOperationSheet(context) : null,
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: const Text('Randevu Al'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? cs.primary.withValues(alpha: 0.12)
            : cs.onPrimaryContainer.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: highlight ? cs.primary : cs.onPrimaryContainer,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: highlight
                  ? cs.primary.withValues(alpha: 0.8)
                  : cs.onPrimaryContainer.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Non-Package Services Section ─────────────────────────────────────────────

class _NonPackageServicesSection extends StatefulWidget {
  const _NonPackageServicesSection({required this.controller});
  final BookingFlowController controller;

  @override
  State<_NonPackageServicesSection> createState() =>
      _NonPackageServicesSectionState();
}

class _NonPackageServicesSectionState
    extends State<_NonPackageServicesSection> {
  final Map<String, bool> _expandedCategories = {};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showPrice =
        widget.controller.org?.bookingSettings.showServicePrices == true;
    final allowStaffSelection =
        widget.controller.org?.bookingSettings.allowStaffSelection == true;
    final services = widget.controller.services;
    final hasPackages = widget.controller.customerPackages.isNotEmpty;

    // Group by category
    final Map<String, List<OrgService>> byCategory = {};
    final List<String> categoryOrder = [];
    for (final s in services) {
      final catKey = s.category ?? '__none__';
      if (!byCategory.containsKey(catKey)) {
        byCategory[catKey] = [];
        categoryOrder.add(catKey);
      }
      byCategory[catKey]!.add(s);
    }

    final multipleCategories = categoryOrder.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(Icons.grid_view_rounded,
                  size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                hasPackages ? 'Paket Dışı İşlemler' : 'Hizmetler',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ...categoryOrder.map((catKey) {
          final catServices = byCategory[catKey]!;
          final catName = catServices.first.categoryName ??
              catServices.first.category ??
              'Genel';
          final expanded = _expandedCategories[catKey] ?? false;

          if (!multipleCategories) {
            // Sadece tek kategori varsa direkt listele
            return Column(
              children: catServices
                  .map((s) => _buildServiceTile(
                        s,
                        showPrice,
                        cs,
                        allowStaffSelection,
                      ))
                  .toList(),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(
                      () => _expandedCategories[catKey] = !expanded),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color:
                          cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.folder_rounded,
                            size: 16, color: cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            catName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                        Text(
                          '${catServices.length}',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (expanded) ...[
                ...catServices
                    .map((s) => _buildServiceTile(
                          s,
                          showPrice,
                          cs,
                          allowStaffSelection,
                        )),
                const SizedBox(height: 4),
              ],
            ],
          );
        }),
      ],
    );
  }

  Widget _buildServiceTile(
    OrgService service,
    bool showPrice,
    ColorScheme cs,
    bool allowStaffSelection,
  ) {
    final controller = widget.controller;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ListTile(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(service.name),
        subtitle: Text(
          showPrice && service.price != null
              ? '${service.durationMinutes} dk  •  ${service.price!.toStringAsFixed(0)} TL'
              : '${service.durationMinutes} dk',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing:
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: cs.outline),
        onTap: () {
          controller.selectService(service);
          if (!allowStaffSelection) {
            controller.nextFromService();
          }
        },
      ),
    );
  }
}

// ─── Step 3.5: Staff Selection ────────────────────────────────────────────────

class _StaffSelectionSection extends StatelessWidget {
  const _StaffSelectionSection({required this.controller});

  final BookingFlowController controller;

  @override
  Widget build(BuildContext context) {
    final allowStaff =
        controller.org?.bookingSettings.allowStaffSelection == true;
    final staff = controller.availableStaff;

    if (!allowStaff) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        Row(
          children: [
            Icon(Icons.person_rounded, size: 15, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'Personel Seçin',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // "Farketmez" seçeneği
        _buildStaffTile(
          context: context,
          cs: cs,
          id: null,
          name: 'Farketmez',
          subtitle: 'Müsait olan personeli otomatik ata',
          isSelected: controller.selectedStaffId == null,
          onTap: () => controller.selectStaff(null, null),
        ),
        ...staff.map((s) {
          final id = s['id'] as String;
          final adi = (s['adi'] as String?) ?? '';
          final soyadi = (s['soyadi'] as String?) ?? '';
          final ad = [adi, soyadi].where((v) => v.isNotEmpty).join(' ');
          return _buildStaffTile(
            context: context,
            cs: cs,
            id: id,
            name: ad,
            isSelected: controller.selectedStaffId == id,
            onTap: () => controller.selectStaff(id, ad),
          );
        }),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildStaffTile({
    required BuildContext context,
    required ColorScheme cs,
    required String? id,
    required String name,
    String? subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? cs.primaryContainer.withValues(alpha: 0.6)
            : cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? cs.primary : cs.outlineVariant,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: isSelected
              ? cs.primary
              : cs.surfaceContainerHighest,
          child: id == null
              ? Icon(Icons.shuffle_rounded,
                  size: 14,
                  color: isSelected ? cs.onPrimary : cs.onSurfaceVariant)
              : Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
        ),
        title: Text(
          name,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 13,
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle,
                style:
                    TextStyle(fontSize: 11, color: cs.onSurfaceVariant))
            : null,
        trailing: isSelected
            ? Icon(Icons.check_circle_rounded,
                size: 18, color: cs.primary)
            : null,
        onTap: onTap,
      ),
    );
  }
}

// ─── Step 4: Date & Time ─────────────────────────────────────────────────────

class _DateTimeStep extends StatefulWidget {
  const _DateTimeStep({required this.controller});

  final BookingFlowController controller;

  @override
  State<_DateTimeStep> createState() => _DateTimeStepState();
}

class _DateTimeStepState extends State<_DateTimeStep> {
  static const _shortDays = [
    '', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'
  ];
  static const _shortMonths = [
    '', 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.loadAvailability(widget.controller.selectedDate);
    });
  }

  List<DateTime> _quickDates() {
    final now = DateTime.now();
    final maxDays =
        widget.controller.org?.bookingSettings.maxDaysAhead ?? 30;
    final count = maxDays < 14 ? maxDays : 14;
    return List.generate(count, (i) => now.add(Duration(days: i)));
  }

  String _formatQuickDate(DateTime d) {
    final today = DateTime.now();
    final isToday = d.year == today.year &&
        d.month == today.month &&
        d.day == today.day;
    if (isToday) return 'Bugün';
    return '${_shortDays[d.weekday]}\n${d.day} ${_shortMonths[d.month]}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final maxDays =
        widget.controller.org?.bookingSettings.maxDaysAhead ?? 30;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _StepHeader(index: 3, title: 'Tarih ve saat seçin'),
            const SizedBox(height: 16),

            // Quick date strip
            SizedBox(
              height: 70,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _quickDates().map((d) {
                  final sel = widget.controller.selectedDate.year ==
                          d.year &&
                      widget.controller.selectedDate.month == d.month &&
                      widget.controller.selectedDate.day == d.day;
                  return GestureDetector(
                    onTap: () =>
                        widget.controller.loadAvailability(d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 56,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: sel
                            ? cs.primary
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              sel ? cs.primary : cs.outlineVariant,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _formatQuickDate(d),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: sel
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: sel
                                ? cs.onPrimary
                                : cs.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),

            // More dates button
            TextButton.icon(
              onPressed: () async {
                final selected = await showDatePicker(
                  context: context,
                  firstDate: now,
                  lastDate: now.add(Duration(days: maxDays)),
                  initialDate: widget.controller.selectedDate,
                );
                if (selected != null) {
                  await widget.controller
                      .loadAvailability(selected);
                }
              },
              icon: const Icon(Icons.calendar_month_rounded,
                  size: 16),
              label: Text(
                  'Takvimden seç: ${DateTimeUtils.formatDate(widget.controller.selectedDate)}'),
              style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft),
            ),
            const Divider(height: 20),

            // Slots
            if (widget.controller.isSubmitting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (widget.controller.availableSlots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Seçilen tarih için uygun saat bulunamadı.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    widget.controller.availableSlots.map((slot) {
                  final sel = widget.controller.selectedSlot
                          ?.start ==
                      slot.start;
                  return ChoiceChip(
                    label: Text(slot.label),
                    selected: sel,
                    onSelected: (_) =>
                        widget.controller.selectSlot(slot),
                  );
                }).toList(),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: widget.controller.selectedSlot == null
                  ? null
                  : widget.controller.nextFromDateTime,
              child: const Text('Onay ekranına geç'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: widget.controller.back,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Geri'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step 5: Confirm ─────────────────────────────────────────────────────────

class _ConfirmStep extends StatefulWidget {
  const _ConfirmStep({required this.controller});

  final BookingFlowController controller;

  @override
  State<_ConfirmStep> createState() => _ConfirmStepState();
}

class _ConfirmStepState extends State<_ConfirmStep> {
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.controller.customer;
    final service = widget.controller.selectedService;
    final slot = widget.controller.selectedSlot;
    final cs = Theme.of(context).colorScheme;

    if (customer == null || service == null || slot == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _StepHeader(index: 4, title: 'Randevu özeti'),
            const SizedBox(height: 16),

            // Summary box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                children: [
                  _ConfirmLine(
                      icon: Icons.business_rounded,
                      label: 'Kurum',
                      value: widget.controller.org!.name),
                  _ConfirmLine(
                      icon: Icons.medical_services_rounded,
                      label: 'Hizmet',
                      value: service.name),
                  _ConfirmLine(
                      icon: Icons.calendar_today_rounded,
                      label: 'Tarih',
                      value: DateTimeUtils.formatDate(slot.start)),
                  _ConfirmLine(
                      icon: Icons.access_time_rounded,
                      label: 'Saat',
                      value:
                          '${DateTimeUtils.formatTime(slot.start)} – ${DateTimeUtils.formatTime(slot.end)}'),
                  _ConfirmLine(
                      icon: Icons.person_rounded,
                      label: 'İsim',
                      value: customer.fullName),
                  _ConfirmLine(
                      icon: Icons.phone_rounded,
                      label: 'Telefon',
                      value: customer.phone,
                      isLast: true),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Optional notes
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Not ekle (opsiyonel)',
                hintText: 'Randevuya eklemek istediğiniz bir not...',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: widget.controller.isSubmitting
                  ? null
                  : () {
                      widget.controller.notes =
                          _notesController.text;
                      widget.controller.submitBooking();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                minimumSize: const Size.fromHeight(52),
              ),
              child: widget.controller.isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Rezervasyonu oluştur',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: widget.controller.back,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Geri'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step 6: Success ─────────────────────────────────────────────────────────

class _SuccessStep extends StatelessWidget {
  const _SuccessStep({required this.controller});

  final BookingFlowController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.green.shade200, width: 2),
              ),
              child: Icon(Icons.check_rounded,
                  size: 48, color: Colors.green.shade600),
            ),
            const SizedBox(height: 20),
            const Text(
              'Randevunuz Oluşturuldu!',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            if ((controller.createdBookingId ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Randevu No: ${controller.createdBookingId}',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimaryContainer,
                      fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              controller.org?.bookingSettings.successText?.isNotEmpty ==
                      true
                  ? controller.org!.bookingSettings.successText!
                  : 'Teşekkür ederiz. Randevunuzu hatırlatmak için sizi arayabiliriz.',
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.6),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: controller.goToServiceStep,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Yeni Randevu Al'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: controller.goToServiceStep,
                icon: const Icon(Icons.history_rounded),
                label: const Text('Rezervasyonlarımı Gör'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Customer Welcome Card ────────────────────────────────────────────────────

class _CustomerWelcomeCard extends StatefulWidget {
  const _CustomerWelcomeCard({required this.controller});
  final BookingFlowController controller;

  @override
  State<_CustomerWelcomeCard> createState() => _CustomerWelcomeCardState();
}

class _CustomerWelcomeCardState extends State<_CustomerWelcomeCard> {
  bool _statementExpanded = false;
  Future<List<AccountStatementEntry>>? _statementFuture;

  void _toggleStatement() {
    setState(() {
      _statementExpanded = !_statementExpanded;
      if (_statementExpanded && _statementFuture == null) {
        _statementFuture = widget.controller.fetchAccountStatement();
      }
    });
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '-';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _fmtPrice(double v) =>
      v.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+\.)'), (m) => '${m[1]}.');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final customer = widget.controller.customer!;
    final showStatement =
        widget.controller.org?.bookingSettings.showAccountStatement == true;

    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: cs.primary,
                  radius: 20,
                  child: Text(
                    customer.fullName.isNotEmpty
                        ? customer.fullName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hoş geldiniz, ${customer.fullName}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: cs.onPrimaryContainer),
                      ),
                      Text(
                        customer.phone,
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onPrimaryContainer.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (showStatement) ...[
              const SizedBox(height: 12),
              Material(
                color: cs.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _toggleStatement,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.account_balance_wallet_rounded,
                            size: 18,
                            color: cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(
                          'Hesap Ekstresi',
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withValues(alpha: 0.75)),
                        ),
                        const Spacer(),
                        Text(
                          '${customer.bakiye < 0 ? '-' : ''}${customer.bakiye.abs().toStringAsFixed(2)} TL',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: customer.bakiye < 0
                                  ? cs.error
                                  : Colors.green.shade700),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          customer.bakiye < 0 ? 'borç' : 'bakiye',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _statementExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_statementExpanded) ...[
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: FutureBuilder<List<AccountStatementEntry>>(
                    future: _statementFuture,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final entries = snap.data ?? [];
                      if (entries.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Henüz hareket bulunmuyor.',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 13)),
                        );
                      }
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowHeight: 36,
                          dataRowMinHeight: 34,
                          dataRowMaxHeight: 48,
                          columnSpacing: 12,
                          headingTextStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface),
                          dataTextStyle: const TextStyle(fontSize: 11),
                          columns: const [
                            DataColumn(label: Text('Tarih')),
                            DataColumn(label: Text('İşlem')),
                            DataColumn(label: Text('Borç'), numeric: true),
                            DataColumn(label: Text('Ödeme'), numeric: true),
                            DataColumn(label: Text('Bakiye'), numeric: true),
                          ],
                          rows: entries.map((e) {
                            final bal = e.balance;
                            return DataRow(cells: [
                              DataCell(Text(_fmtDate(e.date),
                                  style: const TextStyle(fontSize: 11))),
                              DataCell(ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 200),
                                child: Text(e.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11)),
                              )),
                              DataCell(Text(
                                e.debit > 0 ? '${_fmtPrice(e.debit)} TL' : '',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: e.debit > 0 ? cs.error : null),
                              )),
                              DataCell(Text(
                                e.credit > 0 ? '${_fmtPrice(e.credit)} TL' : '',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: e.credit > 0
                                        ? Colors.green.shade700
                                        : null),
                              )),
                              DataCell(Text(
                                '${bal < 0 ? '-' : ''}${_fmtPrice(bal.abs())} TL',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: bal < 0
                                        ? cs.error
                                        : Colors.green.shade700),
                              )),
                            ]);
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Past Reservations Section ────────────────────────────────────────────────

class _PastReservationsSection extends StatefulWidget {
  const _PastReservationsSection({required this.controller});
  final BookingFlowController controller;

  @override
  State<_PastReservationsSection> createState() =>
      _PastReservationsSectionState();
}

class _PastReservationsSectionState extends State<_PastReservationsSection> {
  bool _expanded = false;

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _formatResDate(dynamic value) {
    DateTime? dt;
    if (value is Timestamp) dt = value.toDate();
    if (dt == null) return '—';
    return '${_pad(dt.day)}.${_pad(dt.month)}.${dt.year}';
  }

  String _formatResTime(Map<String, dynamic> data) {
    final sm = data['startMinutes'];
    if (sm == null) return '';
    final minutes = sm is int ? sm : int.tryParse(sm.toString()) ?? 0;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reservations = widget.controller.pastReservations;
    if (reservations.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Geçmiş Randevularınız (${reservations.length})',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: cs.primary),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: cs.primary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 8),
          ...reservations.map((r) {
            final opName = (r['operationName'] as String? ?? '').trim();
            final status = (r['status'] as String? ?? '').trim();
            final dateStr = _formatResDate(r['date']);
            final timeStr = _formatResTime(r);
            final isCancelled =
                status == 'iptal' || status == 'cancelled';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 10, top: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCancelled
                          ? cs.error.withValues(alpha: 0.5)
                          : cs.primary.withValues(alpha: 0.6),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      opName.isNotEmpty ? opName : 'Randevu',
                      style: TextStyle(
                        fontSize: 13,
                        decoration: isCancelled
                            ? TextDecoration.lineThrough
                            : null,
                        color: isCancelled
                            ? cs.onSurface.withValues(alpha: 0.45)
                            : cs.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    timeStr.isNotEmpty
                        ? '$dateStr  $timeStr'
                        : dateStr,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
        ],
        const Divider(height: 16),
      ],
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.index, required this.title});

  final int index;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: cs.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$index',
              style: TextStyle(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style:
              Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
        ),
      ],
    );
  }
}

class _ConfirmLine extends StatelessWidget {
  const _ConfirmLine({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 10),
          SizedBox(
              width: 72,
              child: Text('$label:',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 13))),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.cs});

  final String message;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 16, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: cs.onErrorContainer, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withValues(alpha: 0.3)),
      ),
      child: Text(message,
          style: TextStyle(color: cs.onErrorContainer)),
    );
  }
}
