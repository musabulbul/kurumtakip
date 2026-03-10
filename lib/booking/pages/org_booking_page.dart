import 'package:flutter/material.dart';

import '../../core/utils/date_time_utils.dart';
import '../../services/booking_api_service.dart';
import '../../services/customer_service.dart';
import '../../services/org_public_service.dart';
import '../../services/phone_verification_service.dart';
import '../controllers/booking_flow_controller.dart';
import '../widgets/booking_status_views.dart';

class OrgBookingPage extends StatefulWidget {
  const OrgBookingPage({super.key, required this.slug});

  final String slug;

  @override
  State<OrgBookingPage> createState() => _OrgBookingPageState();
}

class _OrgBookingPageState extends State<OrgBookingPage> {
  late final BookingFlowController controller;

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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (controller.org == null) {
          return const Scaffold(
            body: BookingCenteredMessage(
              title: 'Kurum bulunamadı',
              message: 'Bağlantı hatalı olabilir. Lütfen kurumunuzla iletişime geçin.',
            ),
          );
        }

        if (!controller.org!.bookingEnabled || !controller.org!.bookingSettings.enabled) {
          return const Scaffold(
            body: BookingCenteredMessage(
              title: 'Online randevu kapalı',
              message: 'Bu kurum şu anda online randevu kabul etmiyor.',
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(controller.org!.name),
            centerTitle: false,
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _OrgInfoCard(controller: controller),
                      const SizedBox(height: 12),
                      if (controller.errorMessage != null)
                        _ErrorBox(message: controller.errorMessage!),
                      _buildStepView(),
                    ],
                  ),
                ),
              ),
            ),
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

class _OrgInfoCard extends StatelessWidget {
  const _OrgInfoCard({required this.controller});

  final BookingFlowController controller;

  @override
  Widget build(BuildContext context) {
    final org = controller.org!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(org.name, style: Theme.of(context).textTheme.headlineSmall),
            if ((org.phone ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Tel: ${org.phone}'),
            ],
            if ((org.address ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(org.address!),
            ],
            if ((org.bookingSettings.publicInfoText ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(org.bookingSettings.publicInfoText!),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhoneStep extends StatefulWidget {
  const _PhoneStep({required this.controller});

  final BookingFlowController controller;

  @override
  State<_PhoneStep> createState() => _PhoneStepState();
}

class _PhoneStepState extends State<_PhoneStep> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  DateTime? _birthDate;
  bool _otpRequested = false;

  @override
  Widget build(BuildContext context) {
    final authMode = widget.controller.org?.bookingSettings.authMode ?? 'phone_birthdate';
    final otpMode = authMode == 'otp';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              otpMode ? '1. Telefon doğrulama (OTP)' : '1. Telefon + doğum tarihi doğrulama',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefon numaranız'),
            ),
            if (!otpMode) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () async {
                  final selected = await showDatePicker(
                    context: context,
                    firstDate: DateTime(1940),
                    lastDate: DateTime.now(),
                    initialDate: DateTime(2000),
                  );
                  if (mounted) {
                    setState(() => _birthDate = selected);
                  }
                },
                child: Text(
                  _birthDate == null
                      ? 'Doğum tarihi seç'
                      : 'Doğum tarihi: ${DateTimeUtils.formatDate(_birthDate!)}',
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (otpMode) ...[
              ElevatedButton(
                onPressed: () async {
                  await widget.controller.requestOtp(_phoneController.text);
                  if (mounted) setState(() => _otpRequested = true);
                },
                child: const Text('Kod gönder'),
              ),
              if (_otpRequested) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'SMS kodu'),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () async {
                    final ok = await widget.controller.verifyOtp(_codeController.text);
                    if (!ok && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Kod doğrulanamadı.')),
                      );
                    }
                  },
                  child: const Text('Kodu onayla'),
                ),
              ],
            ] else ...[
              ElevatedButton(
                onPressed: () async {
                  if (_birthDate == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lütfen doğum tarihi seçin.')),
                    );
                    return;
                  }
                  await widget.controller.continueWithoutOtpWithBirthDate(
                    inputPhone: _phoneController.text,
                    birthDate: _birthDate!,
                  );
                },
                child: const Text('Devam et'),
              ),
            ],
            if (widget.controller.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                widget.controller.errorMessage!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
  String _gender = 'unknown';

  @override
  void initState() {
    super.initState();
    _birthDate = widget.controller.inputBirthDate;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('2. Müşteri bilgileri', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Ad Soyad'),
            ),
            const SizedBox(height: 10),
            TextField(
              enabled: false,
              decoration: InputDecoration(labelText: 'Telefon', hintText: widget.controller.phone),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _gender,
              decoration: const InputDecoration(labelText: 'Cinsiyet'),
              items: const [
                DropdownMenuItem(value: 'female', child: Text('Kadın')),
                DropdownMenuItem(value: 'male', child: Text('Erkek')),
                DropdownMenuItem(value: 'unknown', child: Text('Belirtmek istemiyorum')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _gender = value;
                });
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Adres (opsiyonel)'),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () async {
                final selected = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1940),
                  lastDate: DateTime.now(),
                  initialDate: DateTime(2000),
                );
                if (mounted) setState(() => _birthDate = selected);
              },
              child: Text(_birthDate == null
                  ? 'Doğum tarihi seç'
                  : 'Doğum tarihi: ${DateTimeUtils.formatDate(_birthDate!)}'),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () async {
                if (_birthDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Doğum tarihi zorunludur.')),
                  );
                  return;
                }
                if (_nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ad soyad zorunludur.')),
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
              child: const Text('Bilgileri kaydet ve devam et'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceStep extends StatelessWidget {
  const _ServiceStep({required this.controller});

  final BookingFlowController controller;

  @override
  Widget build(BuildContext context) {
    final showPrice = controller.org?.bookingSettings.showServicePrices == true;
    final showAccountStatement =
        controller.org?.bookingSettings.showAccountStatement == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('3. Hizmet seçimi', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (controller.services.isEmpty)
              const Text('Bu kurum için aktif hizmet bulunamadı.'),
            ...controller.services.map((service) {
              final selected = controller.selectedService?.id == service.id;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(service.name),
                subtitle: Text(
                  showPrice && service.price != null
                      ? '${service.durationMinutes} dk  •  ${service.price!.toStringAsFixed(2)} TL'
                      : '${service.durationMinutes} dk',
                ),
                trailing: selected ? const Icon(Icons.check_circle) : null,
                onTap: () => controller.selectService(service),
              );
            }),
            if (showAccountStatement) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Hesap Ekstresi'),
                      content: const Text(
                        'Bu kurum danışanların hesap ekstresi görüntülemesini açtı. '
                        'Detaylı ekstresi ekranı bir sonraki sürümde eklenecek.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Tamam'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.receipt_long),
                label: const Text('Hesap ekstresi görüntüle'),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: controller.selectedService == null ? null : controller.nextFromService,
              child: const Text('Tarih ve saat seçimine geç'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTimeStep extends StatefulWidget {
  const _DateTimeStep({required this.controller});

  final BookingFlowController controller;

  @override
  State<_DateTimeStep> createState() => _DateTimeStepState();
}

class _DateTimeStepState extends State<_DateTimeStep> {
  @override
  void initState() {
    super.initState();
    widget.controller.loadAvailability(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('4. Tarih ve saat', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                final now = DateTime.now();
                final selected = await showDatePicker(
                  context: context,
                  firstDate: now,
                  lastDate: now.add(
                    Duration(days: widget.controller.org?.bookingSettings.maxDaysAhead ?? 30),
                  ),
                  initialDate: widget.controller.selectedDate,
                );
                if (selected != null) {
                  await widget.controller.loadAvailability(selected);
                }
              },
              child: Text('Tarih: ${DateTimeUtils.formatDate(widget.controller.selectedDate)}'),
            ),
            const SizedBox(height: 12),
            if (widget.controller.isSubmitting)
              const Center(child: CircularProgressIndicator())
            else if (widget.controller.availableSlots.isEmpty)
              const Text('Seçilen tarih için uygun saat bulunamadı.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.controller.availableSlots.map((slot) {
                  final selected = widget.controller.selectedSlot?.start == slot.start;
                  return ChoiceChip(
                    label: Text(slot.label),
                    selected: selected,
                    onSelected: (_) => widget.controller.selectSlot(slot),
                  );
                }).toList(),
              ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: widget.controller.selectedSlot == null
                  ? null
                  : widget.controller.nextFromDateTime,
              child: const Text('Onay ekranına geç'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: widget.controller.back,
              child: const Text('Geri'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({required this.controller});

  final BookingFlowController controller;

  @override
  Widget build(BuildContext context) {
    final customer = controller.customer;
    final service = controller.selectedService;
    final slot = controller.selectedSlot;
    if (customer == null || service == null || slot == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('5. Son onay', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _Line(label: 'Kurum', value: controller.org!.name),
            _Line(label: 'Hizmet', value: service.name),
            _Line(label: 'Tarih', value: DateTimeUtils.formatDate(slot.start)),
            _Line(label: 'Saat', value: '${DateTimeUtils.formatTime(slot.start)} - ${DateTimeUtils.formatTime(slot.end)}'),
            _Line(label: 'Müşteri', value: customer.fullName),
            _Line(label: 'Telefon', value: customer.phone),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: controller.isSubmitting ? null : controller.submitBooking,
              child: controller.isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Rezervasyonu oluştur'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: controller.back, child: const Text('Geri')),
          ],
        ),
      ),
    );
  }
}

class _SuccessStep extends StatelessWidget {
  const _SuccessStep({required this.controller});

  final BookingFlowController controller;

  @override
  Widget build(BuildContext context) {
    return BookingCenteredMessage(
      title: 'Randevunuz oluşturuldu',
      message:
          'Rezervasyon numaranız: ${controller.createdBookingId ?? '-'}\n${controller.org?.bookingSettings.successText ?? 'Teşekkür ederiz.'}',
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text('$label:')),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(message, style: TextStyle(color: Colors.red.shade800)),
    );
  }
}
