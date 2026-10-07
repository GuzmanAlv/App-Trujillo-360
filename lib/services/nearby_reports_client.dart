import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/incident.dart';
import 'report_sender.dart';

String? get currentReportOwner =>
    Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;

Future<List<Incident>> fetchNearbyReports(
  double latitude,
  double longitude,
) async {
  if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null) {
    throw StateError('Inicia sesión para consultar reportes de la comunidad.');
  }
  final user = FirebaseAuth.instance.currentUser!;
  final base = Uri.parse(ReportSender.endpoint);
  final local =
      kDebugMode &&
      base.scheme == 'http' &&
      ['localhost', '127.0.0.1'].contains(base.host);
  if (base.host.isEmpty ||
      base.userInfo.isNotEmpty ||
      (!local && base.scheme != 'https')) {
    throw StateError('Servidor no configurado.');
  }
  final client = http.Client();
  try {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await user.getIdToken(attempt == 1);
      if (token == null) throw StateError('Sesión requerida.');
      final request =
          http.Request(
              'GET',
              base
                  .resolve('/incidents/nearby')
                  .replace(
                    queryParameters: {
                      'latitude': '$latitude',
                      'longitude': '$longitude',
                      'radius': '3000',
                    },
                  ),
            )
            ..followRedirects = false
            ..headers['Authorization'] = 'Bearer $token';
      final response = await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 && attempt == 0) continue;
      if (response.statusCode != 200) {
        throw StateError(
          'No se pudieron consultar los reportes de la comunidad.',
        );
      }
      if (currentReportOwner != user.uid) {
        throw StateError('La sesión cambió. Vuelve a actualizar.');
      }
      return (jsonDecode(response.body) as List).map((raw) {
        final j = Map<String, dynamic>.from(raw as Map);
        return Incident.fromJson({
          'id': j['id'],
          'type': j['category'],
          'place': 'Incidente de la comunidad',
          'description': '',
          'latitude': j['latitude'],
          'longitude': j['longitude'],
          'createdAt': j['occurred_at'],
          'remoteId': j['id'],
          'remoteStatus': j['status'],
          'corroborationCount': j['corroboration_count'],
          'needsReview': j['needs_review'],
        });
      }).toList();
    }
    throw StateError('Sesión vencida.');
  } finally {
    client.close();
  }
}
