/// Contrato v1 propuesto para candidatos de agresión emitidos por el servidor.
/// La confianza del modelo no equivale a una confirmación humana.
class AiDetection {
  const AiDetection({
    required this.id,
    required this.cameraId,
    required this.modelVersion,
    required this.confidence,
    required this.latitude,
    required this.longitude,
    required this.detectedAt,
  });

  final String id, cameraId, modelVersion;
  final double confidence, latitude, longitude;
  final DateTime detectedAt;

  factory AiDetection.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty || value.length > 200) {
        throw FormatException('Campo inválido: $key');
      }
      return value;
    }

    double number(String key, double min, double max) {
      final value = json[key];
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw FormatException('Campo inválido: $key');
      }
      return value.toDouble();
    }

    if (json['schemaVersion'] != 1 || json['type'] != 'aggression_candidate') {
      throw const FormatException('Tipo o versión de detección no compatible');
    }
    final timestamp = text('detectedAt');
    if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(timestamp)) {
      throw const FormatException('detectedAt requiere zona horaria');
    }
    return AiDetection(
      id: text('id'),
      cameraId: text('cameraId'),
      modelVersion: text('modelVersion'),
      confidence: number('confidence', 0, 1),
      latitude: number('latitude', -90, 90),
      longitude: number('longitude', -180, 180),
      detectedAt: DateTime.parse(timestamp).toUtc(),
    );
  }
}
