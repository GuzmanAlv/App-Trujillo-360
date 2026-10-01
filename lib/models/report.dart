const incidentCategories = ['Robo', 'Auxilio', 'Agresión', 'Riesgo'];

/// Una observación individual. El autor es un perfil ficticio en esta demo.
class Report {
  const Report({
    required this.id,
    required this.reporterId,
    required this.type,
    required this.place,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });
  final String id, reporterId, type, place, description;
  final double latitude, longitude;
  final DateTime createdAt;
  bool get hasKnownReporter => reporterId != 'legacy';

  void validate() {
    if (id.trim().isEmpty ||
        reporterId.trim().isEmpty ||
        !incidentCategories.contains(type) ||
        place.trim().length < 3 ||
        place.length > 100 ||
        description.length > 500 ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      throw const FormatException('Reporte inválido');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'reporterId': reporterId,
    'type': type,
    'place': place,
    'description': description,
    'latitude': latitude,
    'longitude': longitude,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
  factory Report.fromJson(Map<String, dynamic> json, {bool legacy = false}) {
    final report = Report(
      id: json['id'] as String,
      reporterId: legacy ? 'legacy' : json['reporterId'] as String,
      type: json['type'] as String,
      place: json['place'] as String,
      description: json['description'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    );
    report.validate();
    return report;
  }
}
