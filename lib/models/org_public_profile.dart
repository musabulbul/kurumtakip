import 'booking_settings.dart';

class OrgPublicProfile {
  final String id;
  final String name;
  final String slug;
  final String? district;
  final String? phone;
  final String? address;
  final String? logoUrl;
  final bool bookingEnabled;
  final BookingSettings bookingSettings;
  final WorkingHours workingHours;

  const OrgPublicProfile({
    required this.id,
    required this.name,
    required this.slug,
    required this.bookingEnabled,
    required this.bookingSettings,
    required this.workingHours,
    this.district,
    this.phone,
    this.address,
    this.logoUrl,
  });

  factory OrgPublicProfile.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    return OrgPublicProfile(
      id: id,
      name: (map['name'] as String?) ?? '',
      slug: (map['slug'] as String?) ?? '',
      district: map['district'] as String?,
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      logoUrl: map['logoUrl'] as String?,
      bookingEnabled: map['bookingEnabled'] == true,
      bookingSettings: BookingSettings.fromMap(
        map['bookingSettings'] is Map
            ? Map<String, dynamic>.from(map['bookingSettings'] as Map)
            : null,
      ),
      workingHours: WorkingHours.fromMap(
        map['workingHours'] is Map
            ? Map<String, dynamic>.from(map['workingHours'] as Map)
            : null,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'slug': slug,
      'district': district,
      'phone': phone,
      'address': address,
      'logoUrl': logoUrl,
      'bookingEnabled': bookingEnabled,
      'bookingSettings': bookingSettings.toMap(),
      'workingHours': workingHours.toMap(),
    };
  }
}
