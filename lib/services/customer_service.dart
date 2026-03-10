import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/customer_profile.dart';

class CustomerService {
  CustomerService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

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

  Future<CustomerProfile?> findByPhone({
    required String orgId,
    required String phone,
  }) async {
    final normalized = normalizePhone(phone);
    if (normalized.isEmpty) return null;

    final query = await _firestore
        .collection('customers')
        .where('orgId', isEqualTo: orgId)
        .where('phone', isEqualTo: normalized)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      return CustomerProfile.fromMap(doc.id, doc.data());
    }

    final legacy = await _firestore
        .collection('kurumlar')
        .doc(orgId)
        .collection('danisanlar')
        .where('telefon', isEqualTo: normalized)
        .limit(1)
        .get();

    if (legacy.docs.isEmpty) return null;
    final doc = legacy.docs.first;
    final data = doc.data();
    final fullName = [
      (data['adi'] ?? '').toString().trim(),
      (data['soyadi'] ?? '').toString().trim(),
    ].where((item) => item.isNotEmpty).join(' ');

    DateTime? birthDate;
    final rawBirth = data['dogumtarihi'];
    if (rawBirth is Timestamp) {
      birthDate = rawBirth.toDate();
    } else if (rawBirth is String && rawBirth.trim().isNotEmpty) {
      birthDate = DateTime.tryParse(rawBirth.trim());
      birthDate ??= DateFormat('dd.MM.yyyy').tryParse(rawBirth.trim());
    }

    return CustomerProfile(
      id: doc.id,
      orgId: orgId,
      fullName: fullName,
      phone: normalized,
      birthDate: birthDate,
      gender: (data['cinsiyet'] as String?)?.trim(),
      address: (data['adres'] as String?)?.trim(),
    );
  }

  Future<CustomerProfile> upsertCustomer({
    required String orgId,
    required String phone,
    required String fullName,
    DateTime? birthDate,
    String? gender,
    String? address,
  }) async {
    final normalized = normalizePhone(phone);
    final existing = await findByPhone(orgId: orgId, phone: normalized);

    if (existing != null) {
      final updated = CustomerProfile(
        id: existing.id,
        orgId: orgId,
        fullName: fullName,
        phone: normalized,
        birthDate: birthDate,
        gender: gender,
        address: address,
      );
      await _firestore.collection('customers').doc(existing.id).set(
            updated.toMap(),
            SetOptions(merge: true),
          );
      await _upsertLegacyDanisan(
        orgId: orgId,
        phone: normalized,
        fullName: fullName,
        birthDate: birthDate,
        gender: gender,
        address: address,
      );
      return updated;
    }

    final ref = _firestore.collection('customers').doc();
    final created = CustomerProfile(
      id: ref.id,
      orgId: orgId,
      fullName: fullName,
      phone: normalized,
      birthDate: birthDate,
      gender: gender,
      address: address,
    );

    await ref.set({
      ...created.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _upsertLegacyDanisan(
      orgId: orgId,
      phone: normalized,
      fullName: fullName,
      birthDate: birthDate,
      gender: gender,
      address: address,
    );

    return created;
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

  Future<void> _upsertLegacyDanisan({
    required String orgId,
    required String phone,
    required String fullName,
    DateTime? birthDate,
    String? gender,
    String? address,
  }) async {
    final legacyRef = _firestore
        .collection('kurumlar')
        .doc(orgId)
        .collection('danisanlar');

    final existingLegacy =
        await legacyRef.where('telefon', isEqualTo: phone).limit(1).get();

    final parts =
        fullName.trim().split(RegExp(r'\s+')).where((item) => item.isNotEmpty).toList();
    var firstName = fullName.trim();
    var lastName = '';
    if (parts.length >= 2) {
      lastName = parts.removeLast();
      firstName = parts.join(' ');
    }

    final payload = <String, dynamic>{
      'telefon': phone,
      'adi': firstName,
      'soyadi': lastName,
      'adres': address ?? '',
      'kurumkodu': orgId,
      if (gender != null && gender.isNotEmpty) 'cinsiyet': gender,
      if (birthDate != null) 'dogumtarihi': DateFormat('yyyy-MM-dd').format(birthDate),
      'guncellenmeZamani': FieldValue.serverTimestamp(),
    };

    if (existingLegacy.docs.isNotEmpty) {
      await legacyRef.doc(existingLegacy.docs.first.id).set(payload, SetOptions(merge: true));
      return;
    }

    final doc = legacyRef.doc();
    await doc.set({
      ...payload,
      'id': doc.id,
      'kayittarihi': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'olusturulmaZamani': FieldValue.serverTimestamp(),
    });
  }
}
