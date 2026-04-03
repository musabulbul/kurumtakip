import 'package:flutter/foundation.dart';

import '../../models/booking_models.dart';
import '../../models/customer_profile.dart';
import '../../models/org_public_profile.dart';
import '../../models/org_service.dart';
import '../../services/booking_api_service.dart';
import '../../services/customer_service.dart';
import '../../services/org_public_service.dart';
import '../../services/phone_verification_service.dart';

enum BookingStep {
  phone,
  customer,
  service,
  dateTime,
  confirm,
  success,
}

class BookingFlowController extends ChangeNotifier {
  BookingFlowController({
    required OrgPublicService orgService,
    required CustomerService customerService,
    required BookingApiService bookingApiService,
    required PhoneVerificationService phoneVerification,
  })  : _orgService = orgService,
        _customerService = customerService,
        _bookingApiService = bookingApiService,
        _phoneVerification = phoneVerification;

  final OrgPublicService _orgService;
  final CustomerService _customerService;
  final BookingApiService _bookingApiService;
  PhoneVerificationService _phoneVerification;
  bool _isDisposed = false;

  void _notify() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  bool isLoading = true;
  bool isSubmitting = false;
  String? errorMessage;
  OrgPublicProfile? org;
  List<OrgService> services = const [];
  BookingStep step = BookingStep.phone;

  String phone = '';
  DateTime? inputBirthDate;
  String? verificationToken;
  CustomerProfile? customer;
  List<Map<String, dynamic>> pastReservations = const [];
  List<CustomerPackage> customerPackages = const [];
  String notes = '';
  OrgService? selectedService;
  String? selectedPackageId;
  String? selectedPackageName;
  String? selectedPackageOperationId;
  DateTime selectedDate = DateTime.now();
  List<BookingSlot> availableSlots = const [];
  BookingSlot? selectedSlot;
  String? createdBookingId;
  int _availabilityRequestId = 0;

  // Personel seçimi
  List<Map<String, dynamic>> availableStaff = const [];
  /// null = "Farketmez" seçili
  String? selectedStaffId;
  String? selectedStaffName;

  Future<void> initialize(String slug) async {
    isLoading = true;
    errorMessage = null;
    _notify();

    try {
      org = await _orgService.findBySlug(slug);
      if (org == null) {
        errorMessage = 'Kurum bulunamadı';
        return;
      }

      services = await _orgService.listActiveServices(org!.id);
      if (services.isNotEmpty) {
        selectedService = services.first;
      }
      if (org!.bookingEnabled && org!.bookingSettings.enabled) {
        step = BookingStep.phone;
      }

      // OTP modu aktifse backend SMS servisi üzerinden doğrulama yap.
      if (org!.bookingSettings.authMode == 'otp') {
        _phoneVerification = SmsOtpPhoneVerificationService(
          orgId: org!.id,
          orgName: org!.name,
        );
      }
    } catch (e) {
      errorMessage = 'Kurum bilgileri yüklenemedi: $e';
    } finally {
      isLoading = false;
      _notify();
    }
  }

  Future<void> requestOtp(String inputPhone) async {
    phone = _customerService.normalizePhone(inputPhone);
    verificationToken = await _phoneVerification.requestCode(phone);
    errorMessage = null;
    _notify();
  }

  Future<bool> verifyOtp(String code) async {
    if (verificationToken == null) return false;
    final ok = await _phoneVerification.verifyCode(
      verificationToken: verificationToken!,
      smsCode: code,
    );
    if (ok) {
      await _loadExistingCustomer(skipBirthDateValidation: true);
    }
    return ok;
  }

  Future<void> continueWithoutOtp(String inputPhone) async {
    phone = _customerService.normalizePhone(inputPhone);
    errorMessage = null;
    await _loadExistingCustomer(skipBirthDateValidation: true);
  }

  Future<void> continueWithoutOtpWithBirthDate({
    required String inputPhone,
    required DateTime birthDate,
  }) async {
    phone = _customerService.normalizePhone(inputPhone);
    inputBirthDate = birthDate;
    errorMessage = null;
    await _loadExistingCustomer(skipBirthDateValidation: false);
  }

  Future<void> _loadExistingCustomer({required bool skipBirthDateValidation}) async {
    if (org == null) return;
    customer = await _customerService.findByPhone(orgId: org!.id, phone: phone);
    if (customer == null) {
      step = BookingStep.customer;
      _notify();
      return;
    }

    if (!skipBirthDateValidation) {
      final matches = _customerService.birthDateMatches(
        expected: inputBirthDate,
        actual: customer!.birthDate,
      );
      if (!matches) {
        customer = null;
        errorMessage = 'Telefon numarası bulundu ancak doğum tarihi eşleşmiyor.';
        step = BookingStep.phone;
        _notify();
        return;
      }
    }

    if (customer != null) {
      step = BookingStep.service;
      _loadCustomerData();
    }
    _notify();
  }

  Future<void> _loadCustomerData() async {
    if (org == null || customer == null) return;
    try {
      final results = await Future.wait([
        _bookingApiService.fetchPastReservations(
          orgId: org!.id,
          customerId: customer!.id,
        ),
        _bookingApiService.fetchCustomerPackages(
          orgId: org!.id,
          customerId: customer!.id,
        ),
      ]);
      pastReservations =
          (results[0] as List).cast<Map<String, dynamic>>();
      customerPackages =
          (results[1] as List).cast<CustomerPackage>();
      _notify();
    } catch (_) {}
  }

  Future<void> saveCustomer({
    required String fullName,
    DateTime? birthDate,
    String? gender,
    String? address,
  }) async {
    if (org == null) return;
    customer = await _customerService.upsertCustomer(
      orgId: org!.id,
      phone: phone,
      fullName: fullName,
      birthDate: birthDate ?? inputBirthDate,
      gender: gender,
      address: address,
      ekleyen: 'Online',
    );
    step = BookingStep.service;
    errorMessage = null;
    _notify();
  }

  void selectService(OrgService service) {
    selectedService = service;
    selectedPackageId = null;
    selectedPackageName = null;
    selectedPackageOperationId = null;
    selectedStaffId = null;
    selectedStaffName = null;
    availableStaff = const [];
    _notify();
    _loadStaffForService(service);
  }

  void selectServiceFromPackage({
    required OrgService service,
    required String packageId,
    required String packageName,
    required String operationId,
  }) {
    selectedService = service;
    selectedPackageId = packageId;
    selectedPackageName = packageName;
    selectedPackageOperationId = operationId;
    selectedStaffId = null;
    selectedStaffName = null;
    availableStaff = const [];
    _notify();
    _loadStaffForService(service);
  }

  Future<void> _loadStaffForService(OrgService service) async {
    if (org == null) return;
    final allowStaff = org!.bookingSettings.allowStaffSelection;
    if (!allowStaff || service.personelIds.isEmpty) {
      availableStaff = const [];
      _notify();
      return;
    }
    try {
      final staff = await _bookingApiService.fetchStaffForService(
        orgId: org!.id,
        personelIds: service.personelIds,
      );
      availableStaff = staff;
    } catch (_) {
      availableStaff = const [];
    }
    _notify();
  }

  void selectStaff(String? staffId, String? staffName) {
    selectedStaffId = staffId;
    selectedStaffName = staffName;
    _notify();
  }

  /// Paket operasyonu için services listesinden eşleşen servisi bulur,
  /// yoksa paket verisiyle minimal bir OrgService oluşturur.
  OrgService resolveServiceForPackageOp(CustomerPackageOp op) {
    for (final s in services) {
      if (s.id == op.operationId) return s;
    }
    for (final s in services) {
      if (s.name.toLowerCase() == op.operationName.toLowerCase()) return s;
    }
    return OrgService(
      id: op.operationId,
      orgId: org!.id,
      name: op.operationName,
      durationMinutes: org!.bookingSettings.slotMinutes,
      active: true,
    );
  }

  Future<void> loadAvailability(DateTime date) async {
    if (org == null || selectedService == null) return;
    final requestId = ++_availabilityRequestId;
    selectedDate = date;
    selectedSlot = null;
    errorMessage = null;
    isSubmitting = true;
    _notify();

    try {
      final slots = await _bookingApiService.fetchAvailability(
        query: AvailabilityQuery(
          orgId: org!.id,
          serviceId: selectedService!.id,
          date: date,
          mekanIds: selectedService!.mekanIds,
          staffId: selectedStaffId,
        ),
        settings: org!.bookingSettings,
        workingHours: org!.workingHours,
        service: selectedService!,
      );
      if (requestId != _availabilityRequestId) return;
      availableSlots = slots;
    } catch (e) {
      if (requestId != _availabilityRequestId) return;
      availableSlots = const [];
      errorMessage = 'Müsaitlik alınamadı. Lütfen tekrar deneyin.';
      debugPrint('availability error: $e');
    } finally {
      if (requestId != _availabilityRequestId) return;
      isSubmitting = false;
      _notify();
    }
  }

  void selectSlot(BookingSlot slot) {
    selectedSlot = slot;
    _notify();
  }

  void nextFromService() {
    step = BookingStep.dateTime;
    _notify();
  }

  void nextFromDateTime() {
    step = BookingStep.confirm;
    _notify();
  }

  void back() {
    switch (step) {
      case BookingStep.customer:
        step = BookingStep.phone;
        break;
      case BookingStep.service:
        step = BookingStep.customer;
        break;
      case BookingStep.dateTime:
        step = BookingStep.service;
        break;
      case BookingStep.confirm:
        step = BookingStep.dateTime;
        break;
      case BookingStep.phone:
      case BookingStep.success:
        break;
    }
    _notify();
  }

  Future<List<AccountStatementEntry>> fetchAccountStatement() {
    if (org == null || customer == null) return Future.value(const []);
    return _bookingApiService.fetchAccountStatement(
      orgId: org!.id,
      customerId: customer!.id,
    );
  }

  /// Başarı ekranından hizmet seçim adımına döner.
  /// Müşteri bilgileri ve geçmiş rezervasyonlar korunur.
  void goToServiceStep() {
    selectedSlot = null;
    selectedDate = DateTime.now();
    notes = '';
    createdBookingId = null;
    selectedStaffId = null;
    selectedStaffName = null;
    availableStaff = const [];
    step = BookingStep.service;
    _loadCustomerData();
    _notify();
  }

  Future<void> submitBooking() async {
    if (org == null || customer == null || selectedService == null || selectedSlot == null) {
      return;
    }

    isSubmitting = true;
    _notify();

    try {
      createdBookingId = await _bookingApiService.createBooking(
        BookingDraft(
          orgId: org!.id,
          customerId: customer!.id,
          customerName: customer!.fullName,
          customerPhone: customer!.phone,
          serviceId: selectedService!.id,
          serviceName: selectedService!.name,
          bookingDate: DateTime(selectedSlot!.start.year, selectedSlot!.start.month, selectedSlot!.start.day),
          startTime: selectedSlot!.start,
          endTime: selectedSlot!.end,
          notes: notes.trim().isEmpty ? null : notes.trim(),
          staffId: selectedStaffId,
          staffName: selectedStaffName,
          mekanId: selectedSlot!.mekanId,
          paketId: selectedPackageId,
          paketAdi: selectedPackageName,
          paketOperationId: selectedPackageOperationId,
        ),
      );
      step = BookingStep.success;
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isSubmitting = false;
      _notify();
    }
  }
}
