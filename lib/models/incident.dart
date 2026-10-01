import 'report.dart';

enum VerificationStatus {
  unverified('Sin verificar'),
  verified('Verificado'),
  dismissed('Descartado');

  const VerificationStatus(this.label);
  final String label;
}

/// Caso agrupado; la verificación no implica atención de una autoridad.
class Incident {
  Incident({
    required this.id,
    required List<Report> reports,
    this.status = VerificationStatus.unverified,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewReason,
  }) : reports = List.unmodifiable(reports) {
    if (id.isEmpty ||
        reports.isEmpty ||
        reports.any((r) => r.type != reports.first.type)) {
      throw const FormatException('Caso inválido');
    }
  }
  final String id;
  final List<Report> reports;
  final VerificationStatus status;
  final String? reviewedBy, reviewReason;
  final DateTime? reviewedAt;

  Report get anchor => reports.first;
  String get type => anchor.type;
  String get place => anchor.place;
  String get description => anchor.description;
  double get latitude => anchor.latitude;
  double get longitude => anchor.longitude;
  DateTime get createdAt => anchor.createdAt;
  int get reporterCount => reports
      .where((r) => r.hasKnownReporter)
      .map((r) => r.reporterId)
      .toSet()
      .length;
  bool get isVisible =>
      status != VerificationStatus.dismissed &&
      (status == VerificationStatus.verified || reporterCount >= 3);

  Incident withReport(Report report) => Incident(
    id: id,
    reports: [...reports, report],
    status: status,
    reviewedBy: reviewedBy,
    reviewedAt: reviewedAt,
    reviewReason: reviewReason,
  );
  Incident reviewed(
    VerificationStatus status,
    String reviewer,
    String reason,
    DateTime at,
  ) => Incident(
    id: id,
    reports: reports,
    status: status,
    reviewedBy: reviewer,
    reviewedAt: at,
    reviewReason: reason,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'reports': reports.map((r) => r.toJson()).toList(),
    'status': status.name,
    'reviewedBy': reviewedBy,
    'reviewedAt': reviewedAt?.toUtc().toIso8601String(),
    'reviewReason': reviewReason,
  };
  factory Incident.fromJson(Map<String, dynamic> json) {
    final status = VerificationStatus.values.byName(json['status'] as String);
    final reviewer = json['reviewedBy'] as String?;
    final reason = json['reviewReason'] as String?;
    final at = json['reviewedAt'] as String?;
    if (status != VerificationStatus.unverified &&
        (reviewer != 'demo-admin' ||
            reason == null ||
            reason.trim().isEmpty ||
            at == null)) {
      throw const FormatException('Revisión incompleta');
    }
    return Incident(
      id: json['id'] as String,
      reports: (json['reports'] as List)
          .map((r) => Report.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList(),
      status: status,
      reviewedBy: reviewer,
      reviewReason: reason,
      reviewedAt: at == null ? null : DateTime.parse(at).toUtc(),
    );
  }
}
