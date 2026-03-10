import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerProfile {
  final String id;
  final String orgId;
  final String fullName;
  final String phone;
  final DateTime? birthDate;
  final String? gender;
  final String? address;

  const CustomerProfile({
    required this.id,
    required this.orgId,
    required this.fullName,
    required this.phone,
    this.birthDate,
    this.gender,
    this.address,
  });

  factory CustomerProfile.fromMap(String id, Map<String, dynamic> map) {
    return CustomerProfile(
      id: id,
      orgId: (map['orgId'] as String?) ?? '',
      fullName: (map['fullName'] as String?) ?? '',
      phone: (map['phone'] as String?) ?? '',
      birthDate: _toDate(map['birthDate']),
      gender: map['gender'] as String?,
      address: map['address'] as String?,
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'orgId': orgId,
      'fullName': fullName,
      'phone': phone,
      'birthDate': birthDate,
      'gender': gender,
      'address': address,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
