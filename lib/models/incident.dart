import 'report_photo.dart';

class Incident {
  const Incident({
    required this.id,
    required this.type,
    required this.place,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.ownerUid,
    this.remoteId,
    this.remoteStatus = 'pending',
    this.attention = 'none',
    this.corroborationCount = 0,
    this.needsReview = false,
    this.photos = const [],
    this.priority,
  });
  final String id, type, place, description;
  final double latitude, longitude;
  final DateTime createdAt;
  final String? ownerUid, remoteId;
  final String remoteStatus, attention;
  final int corroborationCount;
  final bool needsReview;
  final List<ReportPhoto> photos;
  final String? priority;
  bool get isCommunityVisible =>
      !needsReview &&
      (remoteStatus == 'verified' ||
          (remoteStatus == 'corroborated' && corroborationCount >= 3));
  bool recentAt(DateTime now) =>
      !createdAt.isAfter(now) &&
      now.difference(createdAt) < const Duration(days: 7);
  String get deliveryLabel => remoteId != null
      ? (remoteStatus == 'corroborated'
            ? 'Corroborado por la comunidad'
            : remoteStatus == 'verified'
            ? 'Verificado'
            : remoteStatus == 'closed'
            ? 'Cerrado'
            : remoteStatus == 'discarded'
            ? 'Descartado'
            : needsReview
            ? 'Enviado · Requiere revisión'
            : 'Enviado · $corroborationCount de 3 cuentas')
      : ownerUid != null
      ? 'Pendiente de envío'
      : 'Solo en este dispositivo';
  Incident delivered(
    String serverId, {
    String status = 'pending',
    int count = 1,
    bool review = false,
  }) => Incident(
    id: id,
    type: type,
    place: place,
    description: description,
    latitude: latitude,
    longitude: longitude,
    createdAt: createdAt,
    ownerUid: ownerUid,
    remoteId: serverId,
    remoteStatus: status,
    attention: attention,
    corroborationCount: count,
    needsReview: review,
    photos: photos,
    priority: priority,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'place': place,
    'description': description,
    'latitude': latitude,
    'longitude': longitude,
    'createdAt': createdAt.toIso8601String(),
    'ownerUid': ownerUid,
    'remoteId': remoteId,
    'remoteStatus': remoteStatus,
    'attention': attention,
    'corroborationCount': corroborationCount,
    'needsReview': needsReview,
    'photos': photos.map((photo) => photo.toJson()).toList(),
    'priority': priority,
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
      ownerUid: j['ownerUid'] as String?,
      remoteId: j['remoteId'] as String?,
      remoteStatus: j['remoteStatus'] as String? ?? 'pending',
      attention: j['attention'] as String? ?? 'none',
      corroborationCount:
          j['corroborationCount'] as int? ?? (j['remoteId'] == null ? 0 : 1),
      needsReview: j['needsReview'] as bool? ?? false,
      priority: j['priority'] as String?,
      photos: ((j['photos'] as List?) ?? const [])
          .map(
            (photo) =>
                ReportPhoto.fromJson(Map<String, dynamic>.from(photo as Map)),
          )
          .toList(),
    );
  }
}
