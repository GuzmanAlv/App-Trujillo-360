class Incident {
  const Incident({
    required this.id,
    required this.type,
    required this.place,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });
  final String id, type, place, description;
  final double latitude, longitude;
  final DateTime createdAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'place': place,
    'description': description,
    'latitude': latitude,
    'longitude': longitude,
    'createdAt': createdAt.toIso8601String(),
  };
  factory Incident.fromJson(Map<String, dynamic> j) {
    final lat = (j['latitude'] as num).toDouble();
    final lng = (j['longitude'] as num).toDouble();
    if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
      throw const FormatException('Coordenadas inválidas');
    }
    return Incident(
      id: j['id'] as String,
      type: j['type'] as String,
      place: j['place'] as String,
      description: j['description'] as String,
      latitude: lat,
      longitude: lng,
      createdAt: DateTime.parse(j['createdAt'] as String),
    );
  }
}
