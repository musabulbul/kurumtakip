import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/org_public_profile.dart';
import '../models/org_service.dart';

class OrgPublicService {
  OrgPublicService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<OrgPublicProfile?> _getOrgFromAnyCollection(String orgId) async {
    final orgDoc = await _firestore.collection('orgs').doc(orgId).get();
    if (orgDoc.exists && orgDoc.data() != null) {
      return OrgPublicProfile.fromMap(orgDoc.id, _normalizeOrgMap(orgDoc.data()!));
    }

    final legacyDoc = await _firestore.collection('kurumlar').doc(orgId).get();
    if (legacyDoc.exists && legacyDoc.data() != null) {
      return OrgPublicProfile.fromMap(
        legacyDoc.id,
        _normalizeOrgMap(legacyDoc.data()!),
      );
    }

    return null;
  }

  Map<String, dynamic> _normalizeOrgMap(Map<String, dynamic> raw) {
    final rootSettings = raw['settings'] is Map
        ? Map<String, dynamic>.from(raw['settings'] as Map)
        : <String, dynamic>{};
    final onlineBookingSettings = rootSettings['onlineBooking'] is Map
        ? Map<String, dynamic>.from(rootSettings['onlineBooking'] as Map)
        : <String, dynamic>{};

    final settings = raw['bookingSettings'] is Map
        ? Map<String, dynamic>.from(raw['bookingSettings'] as Map)
        : onlineBookingSettings;
    settings['enabled'] = settings['enabled'] ?? (raw['bookingEnabled'] == true);
    settings['maxDaysAhead'] = settings['maxDaysAhead'] ?? 30;
    settings['minHoursBefore'] = settings['minHoursBefore'] ?? 2;
    settings['slotMinutes'] = settings['slotMinutes'] ?? 15;
    settings['allowSameDay'] = settings['allowSameDay'] ?? true;
    settings['weekendOpen'] = settings['weekendOpen'] ?? false;
    settings['authMode'] = settings['authMode'] ?? 'phone_birthdate';
    settings['showServicePrices'] = settings['showServicePrices'] ?? false;
    settings['showAccountStatement'] = settings['showAccountStatement'] ?? false;

    final workingHours = raw['workingHours'] is Map
        ? Map<String, dynamic>.from(raw['workingHours'] as Map)
        : (settings['workingHours'] is Map
            ? Map<String, dynamic>.from(settings['workingHours'] as Map)
            : <String, dynamic>{});

    return {
      'name': raw['name'] ?? raw['kurumadi'] ?? '',
      'slug': raw['slug'] ?? '',
      'district': raw['district'] ?? raw['ilce'],
      'phone': raw['phone'] ?? raw['ilgiliKisiTelefon'],
      'address': raw['address'] ?? raw['adres'],
      'logoUrl': raw['logoUrl'] ?? raw['logo'],
      'bookingEnabled': raw['bookingEnabled'] == true,
      'bookingSettings': settings,
      'workingHours': workingHours,
    };
  }

  Future<OrgPublicProfile?> findBySlug(String slug) async {
    final normalizedSlug = slug.trim().toLowerCase();
    if (normalizedSlug.isEmpty) return null;

    // Fast path: direct slug mapping with document id = slug.
    final mappingRef = _firestore.collection('orgSlugs').doc(normalizedSlug);
    final mappingDoc = await mappingRef.get();
    if (mappingDoc.exists) {
      final mappingData = mappingDoc.data() ?? <String, dynamic>{};
      if (mappingData['active'] == false) return null;

      final orgId = (mappingData['orgId'] as String?)?.trim();
      if (orgId != null && orgId.isNotEmpty) {
        final profile = await _getOrgFromAnyCollection(orgId);
        if (profile != null) {
          return profile;
        }
      }
    }

    // Fallback: query slug in orgs first.
    final orgQuery = await _firestore
        .collection('orgs')
        .where('slug', isEqualTo: normalizedSlug)
        .limit(1)
        .get();
    if (orgQuery.docs.isNotEmpty) {
      final doc = orgQuery.docs.first;
      return OrgPublicProfile.fromMap(doc.id, _normalizeOrgMap(doc.data()));
    }

    // Legacy fallback: query slug field in kurumlar.
    final legacyQuery = await _firestore
        .collection('kurumlar')
        .where('slug', isEqualTo: normalizedSlug)
        .limit(1)
        .get();
    if (legacyQuery.docs.isEmpty) return null;
    final legacyDoc = legacyQuery.docs.first;
    return OrgPublicProfile.fromMap(
      legacyDoc.id,
      _normalizeOrgMap(legacyDoc.data()),
    );
  }

  Future<List<OrgService>> listActiveServices(String orgId) async {
    final query = await _firestore
        .collection('orgs')
        .doc(orgId)
        .collection('services')
        .where('active', isEqualTo: true)
        .get();

    if (query.docs.isNotEmpty) {
      final items = query.docs
          .map((doc) => OrgService.fromMap(doc.id, doc.data()))
          .toList(growable: false);
      items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return items;
    }

    final legacyQuery = await _firestore
        .collection('kurumlar')
        .doc(orgId)
        .collection('services')
        .where('active', isEqualTo: true)
        .get();

    final legacyItems = legacyQuery.docs
        .map((doc) => OrgService.fromMap(doc.id, doc.data()))
        .toList(growable: false);
    legacyItems.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return legacyItems;
  }
}
