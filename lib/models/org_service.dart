class OrgService {
  final String id;
  final String orgId;
  final String name;
  final int durationMinutes;
  final double? price;
  final bool active;
  final String? category;
  final String? description;

  const OrgService({
    required this.id,
    required this.orgId,
    required this.name,
    required this.durationMinutes,
    required this.active,
    this.price,
    this.category,
    this.description,
  });

  factory OrgService.fromMap(String id, Map<String, dynamic> map) {
    return OrgService(
      id: id,
      orgId: (map['orgId'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 30,
      price: (map['price'] as num?)?.toDouble(),
      active: map['active'] != false,
      category: map['category'] as String?,
      description: map['description'] as String?,
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
    };
  }
}
