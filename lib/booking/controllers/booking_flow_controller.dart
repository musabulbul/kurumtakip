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
  final PhoneVerificationService _phoneVerification;

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
  OrgService? selectedService;
  DateTime selectedDate = DateTime.now();
  List<BookingSlot> availableSlots = const [];
  BookingSlot? selectedSlot;
  String? createdBookingId;

  Future<void> initialize(String slug) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

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
    } catch (e) {
      errorMessage = 'Kurum bilgileri yüklenemedi: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> requestOtp(String inputPhone) async {
    phone = _customerService.normalizePhone(inputPhone);
    verificationToken = await _phoneVerification.requestCode(phone);
    errorMessage = null;
    notifyListeners();
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
      notifyListeners();
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
        notifyListeners();
        return;
      }
    }

    if (customer != null) {
      step = BookingStep.service;
    }
    notifyListeners();
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
    );
    step = BookingStep.service;
    errorMessage = null;
    notifyListeners();
  }

  void selectService(OrgService service) {
    selectedService = service;
    notifyListeners();
  }

  Future<void> loadAvailability(DateTime date) async {
    if (org == null || selectedService == null) return;
    selectedDate = date;
    selectedSlot = null;
    isSubmitting = true;
    notifyListeners();

    try {
      availableSlots = await _bookingApiService.fetchAvailability(
        query: AvailabilityQuery(
          orgId: org!.id,
          serviceId: selectedService!.id,
          date: date,
        ),
        settings: org!.bookingSettings,
        workingHours: org!.workingHours,
        service: selectedService!,
      );
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  void selectSlot(BookingSlot slot) {
    selectedSlot = slot;
    notifyListeners();
  }

  void nextFromService() {
    step = BookingStep.dateTime;
    notifyListeners();
  }

  void nextFromDateTime() {
    step = BookingStep.confirm;
    notifyListeners();
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
    notifyListeners();
  }

  Future<void> submitBooking() async {
    if (org == null || customer == null || selectedService == null || selectedSlot == null) {
      return;
    }

    isSubmitting = true;
    notifyListeners();

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
        ),
      );
      step = BookingStep.success;
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }
}
