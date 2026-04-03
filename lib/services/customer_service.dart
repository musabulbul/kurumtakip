import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/customer_profile.dart';
import '../utils/text_utils.dart';

class CustomerService {
  CustomerService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _danisanlarRef(String orgId) =>
      _firestore.collection('kurumlar').doc(orgId).collection('danisanlar');

  String normalizePhone(String value) {
    var digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('90') && digits.length == 12) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('0') && digits.length == 11) {
      digits = digits.substring(1);
    }
    return digits;
  }

  List<String> _phoneCandidates(String normalized) {
    final base = normalizePhone(normalized);
    if (base.isEmpty) return const [];
    return <String>{
      base,
      '0$base',
      '90$base',
      '+90$base',
    }.toList(growable: false);
  }

  DateTime? _parseBirthDate(dynamic rawBirth) {
    if (rawBirth is Timestamp) return rawBirth.toDate();
    if (rawBirth is DateTime) return rawBirth;
    if (rawBirth is! String) return null;
    final raw = rawBirth.trim();
    if (raw.isEmpty) return null;

    return DateTime.tryParse(raw) ??
        DateFormat('dd.MM.yyyy').tryParse(raw) ??
        DateFormat('dd/MM/yyyy').tryParse(raw) ??
        DateFormat('yyyy/MM/dd').tryParse(raw);
  }

  Future<CustomerProfile?> findByPhone({
    required String orgId,
    required String phone,
  }) async {
    final normalized = normalizePhone(phone);
    if (normalized.isEmpty) return null;
    final candidates = _phoneCandidates(normalized);
    final ref = _danisanlarRef(orgId);

    final result = candidates.length == 1
        ? await ref.where('telefon', isEqualTo: candidates.first).limit(1).get()
        : await ref.where('telefon', whereIn: candidates).limit(1).get();

    if (result.docs.isEmpty) return null;
    final doc = result.docs.first;
    final data = doc.data();
    final fullName = [
      (data['adi'] ?? '').toString().trim(),
      (data['soyadi'] ?? '').toString().trim(),
    ].where((s) => s.isNotEmpty).join(' ');

    return CustomerProfile(
      id: doc.id,
      orgId: orgId,
      fullName: fullName,
      phone: normalized,
      birthDate: _parseBirthDate(data['dogumtarihi']),
      gender: (data['cinsiyet'] as String?)?.trim(),
      address: (data['adres'] as String?)?.trim(),
      bakiye: (data['bakiye'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Creates or updates a danisan in `kurumlar/{orgId}/danisanlar`.
  ///
  /// [ekleyen] is stored only when creating a new record:
  ///   - pass `'Online'` for self-registration via the booking page
  ///   - pass the staff user's name when added manually
  Future<CustomerProfile> upsertCustomer({
    required String orgId,
    required String phone,
    required String fullName,
    DateTime? birthDate,
    String? gender,
    String? address,
    String? ekleyen,
  }) async {
    final normalized = normalizePhone(phone);
    final titledName = toTitleCaseTr(fullName);
    final candidates = _phoneCandidates(normalized);
    final ref = _danisanlarRef(orgId);

    final existing = candidates.length == 1
        ? await ref.where('telefon', isEqualTo: candidates.first).limit(1).get()
        : await ref.where('telefon', whereIn: candidates).limit(1).get();

    final parts =
        titledName.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    var firstName = titledName;
    var lastName = '';
    if (parts.length >= 2) {
      lastName = parts.removeLast();
      firstName = parts.join(' ');
    }

    final updatePayload = <String, dynamic>{
      'telefon': '+90$normalized',
      'adi': firstName,
      'soyadi': lastName,
      'adres': address ?? '',
      'kurumkodu': orgId,
      if (gender != null && gender.isNotEmpty) 'cinsiyet': gender,
      if (birthDate != null) 'dogumtarihi': DateFormat('yyyy-MM-dd').format(birthDate),
      'guncellenmeZamani': FieldValue.serverTimestamp(),
    };

    final String docId;
    if (existing.docs.isNotEmpty) {
      docId = existing.docs.first.id;
      await ref.doc(docId).set(updatePayload, SetOptions(merge: true));
    } else {
      final doc = ref.doc();
      docId = doc.id;
      await doc.set({
        ...updatePayload,
        'id': docId,
        if (ekleyen != null && ekleyen.isNotEmpty) 'ekleyen': ekleyen,
        'kayittarihi': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'olusturulmaZamani': FieldValue.serverTimestamp(),
      });
    }

    return CustomerProfile(
      id: docId,
      orgId: orgId,
      fullName: titledName,
      phone: normalized,
      birthDate: birthDate,
      gender: gender,
      address: address,
    );
  }

  bool birthDateMatches({
    required DateTime? expected,
    required DateTime? actual,
  }) {
    if (expected == null || actual == null) return false;
    return expected.year == actual.year &&
        expected.month == actual.month &&
        expected.day == actual.day;
  }
}
