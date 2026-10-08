import 'dart:convert';
import 'dart:typed_data';
import 'nearby_reports_client.dart';

class CommunityPhoto {
  const CommunityPhoto({required this.id, required this.reportId});
  final String id, reportId;
}

Future<List<CommunityPhoto>> fetchCommunityPhotos(String incidentId) async {
  final response = await authenticatedCommunityGet(
    '/incidents/$incidentId/photos',
    const {},
  );
  return (jsonDecode(response.body) as List)
      .map(
        (row) => CommunityPhoto(
          id: row['id'] as String,
          reportId: row['report_id'] as String,
        ),
      )
      .toList();
}

Future<Uint8List> fetchCommunityPhoto(
  String incidentId,
  String photoId,
) async => (await authenticatedCommunityGet(
  '/incidents/$incidentId/photos/$photoId',
  const {},
)).bodyBytes;
