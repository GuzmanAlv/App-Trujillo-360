import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/incident.dart';
import 'report_sender.dart';

class RemoteReportDetails {
  const RemoteReportDetails({
    required this.status,
    required this.receivedAt,
    required this.photos,
  });
  final String status;
  final DateTime receivedAt;
  final List<Uint8List> photos;
}

Future<RemoteReportDetails> fetchReportDetails(Incident report) async {
  if (Firebase.apps.isEmpty) throw StateError('Sesión requerida');
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || user.uid != report.ownerUid || report.remoteId == null) {
    throw StateError('Inicia sesión con la cuenta que creó el reporte');
  }
  final base = Uri.parse(ReportSender.endpoint);
  final local =
      kDebugMode &&
      base.scheme == 'http' &&
      ['localhost', '127.0.0.1'].contains(base.host);
  if (base.host.isEmpty ||
      base.userInfo.isNotEmpty ||
      (!local && base.scheme != 'https')) {
    throw StateError('Servidor no configurado');
  }
  final client = http.Client();
  try {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await user.getIdToken(attempt == 1);
      if (token == null) throw StateError('Sesión requerida');
      final request =
          http.Request('GET', base.resolve('/reports/${report.remoteId}'))
            ..followRedirects = false
            ..headers['Authorization'] = 'Bearer $token';
      final response = await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(const Duration(seconds: 30));
      if (response.statusCode == 401 && attempt == 0) continue;
      if (response.statusCode != 200) throw StateError('Detalle no disponible');
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['id'] != report.remoteId || json['request_id'] != report.id) {
        throw const FormatException();
      }
      return RemoteReportDetails(
        status: json['status'] as String,
        receivedAt: DateTime.parse(json['received_at'] as String),
        photos: (json['photos'] as List)
            .map((photo) => base64Decode(photo['content_base64'] as String))
            .toList(),
      );
    }
    throw StateError('Sesión vencida');
  } finally {
    client.close();
  }
}
