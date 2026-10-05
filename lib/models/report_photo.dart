class ReportPhoto {
  const ReportPhoto({required this.id, required this.fileName});
  final String id;

  /// Relative name in the application's persistent photo directory.
  final String fileName;
  Map<String, dynamic> toJson() => {'id': id, 'fileName': fileName};
  factory ReportPhoto.fromJson(Map<String, dynamic> json) => ReportPhoto(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
  );
}
