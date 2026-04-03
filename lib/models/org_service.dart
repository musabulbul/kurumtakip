class OrgService {
  final String id;
  final String orgId;
  final String name;
  final int durationMinutes;
  final double? price;
  final bool active;
  final String? category;
  final String? categoryName;
  final String? description;
  final List<String> mekanIds;
  final List<String> personelIds;

  const OrgService({
    required this.id,
    required this.orgId,
    required this.name,
    required this.durationMinutes,
    required this.active,
    this.price,
    this.category,
    this.categoryName,
    this.description,
    this.mekanIds = const [],
    this.personelIds = const [],
  });

  factory OrgService.fromMap(String id, Map<String, dynamic> map) {
    final rawMekanIds = map['mekanIds'];
    final rawPersonelIds = map['personelIds'];
    return OrgService(
      id: id,
      orgId: (map['orgId'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 30,
      price: (map['price'] as num?)?.toDouble(),
      active: map['active'] != false,
      category: map['category'] as String?,
      description: map['description'] as String?,
      mekanIds: rawMekanIds is List
          ? rawMekanIds.whereType<String>().toList()
          : const [],
      personelIds: rawPersonelIds is List
          ? rawPersonelIds.whereType<String>().toList()
          : const [],
    );
  }

  /// Creates an [OrgService] from a legacy `islemler` document map.
  factory OrgService.fromIslem(
    String id,
    String orgId,
    Map<String, dynamic> map,
  ) {
    final rawMekanIds = map['mekanIds'];
    final rawPersonelIds = map['personelIds'];
    return OrgService(
      id: id,
      orgId: orgId,
      name: (map['adi'] as String?) ?? '',
      durationMinutes: (map['sureDakika'] as num?)?.toInt() ?? 30,
      price: (map['fiyat'] as num?)?.toDouble(),
      active: map['onlineAktif'] == true,
      category: map['kategoriId'] as String?,
      categoryName: map['kategoriAdi'] as String?,
      description: map['aciklama'] as String?,
      mekanIds: rawMekanIds is List
          ? rawMekanIds.whereType<String>().toList()
          : const [],
      personelIds: rawPersonelIds is List
          ? rawPersonelIds.whereType<String>().toList()
          : const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'orgId': orgId,
      'name': name,
      'durationMinutes': durationMinutes,
      'price': price,
      'active': active,
      'category': category,
      'description': description,
      'mekanIds': mekanIds,
      'personelIds': personelIds,
    };
  }
}
