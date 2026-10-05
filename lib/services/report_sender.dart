import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../data/incident_store.dart';
import '../models/incident.dart';
import 'photo_store.dart';

class ReportSender {
  static const endpoint = String.fromEnvironment('BACKEND_URL');
  static final Set<String> _sending = {};
  static String requestId() {
    final rng = Random.secure();
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Future<String> send(Incident report, IncidentStore store) async {
    if (report.remoteId != null) return 'Este reporte ya fue enviado.';
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != report.ownerUid) {
      return 'Inicia sesión con la cuenta que creó este reporte.';
    }
    if (!_sending.add(report.id)) return 'El reporte se está enviando.';
    final client = http.Client();
    try {
      final base = Uri.parse(endpoint);
      final local =
          kDebugMode &&
          base.scheme == 'http' &&
          ['localhost', '127.0.0.1'].contains(base.host);
      if (base.host.isEmpty ||
          base.userInfo.isNotEmpty ||
          (!local && base.scheme != 'https')) {
        return 'Falta configurar la conexión al servidor. El reporte queda pendiente.';
      }
      final photos = <Map<String, String>>[];
      for (final photo in report.photos) {
        final bytes = await PhotoStore.read(photo);
        if (bytes.length > PhotoStore.maxBytes) throw const FormatException();
        photos.add({'id': photo.id, 'content_base64': base64Encode(bytes)});
      }
      for (var attempt = 0; attempt < 2; attempt++) {
        final token = await user.getIdToken(attempt == 1);
        if (token == null) return 'Inicia sesión nuevamente para enviar.';
        final request = http.Request('POST', base.resolve('/reports'))
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode({
            'request_id': report.id,
            'category': report.type,
            'place': report.place,
            'description': report.description,
            'latitude': report.latitude,
            'longitude': report.longitude,
            'occurred_at': report.createdAt.toUtc().toIso8601String(),
            'photos': photos,
          });
        final response = await (() async => http.Response.fromStream(
          await client.send(request),
        ))().timeout(const Duration(seconds: 60));
        if (response.statusCode == 401 && attempt == 0) continue;
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['request_id'] != report.id ||
              data['id'] is! String ||
              (report.photos.isNotEmpty &&
                  data['photo_count'] != report.photos.length)) {
            throw const FormatException();
          }
          if (!await store.add(report.delivered(data['id'] as String))) {
            return 'Recibido por el servidor. No se pudo actualizar la copia local; reintenta para sincronizarla.';
          }
          return 'Reporte enviado. Pendiente de verificación.';
        }
        return switch (response.statusCode) {
          401 => 'Sesión vencida. Inicia sesión nuevamente.',
          403 => 'Tu cuenta no tiene permitido enviar reportes.',
          409 => 'Conflicto de envío. Conservamos el reporte para revisión.',
          422 =>
            'Revisa los datos y las fotos (JPEG o PNG, hasta 2 MB). El reporte no puede tener más de siete días.',
          413 =>
            'Las fotos superan el tamaño permitido. El reporte se conservó en este dispositivo.',
          _ =>
            'Servidor no disponible. El reporte queda pendiente para reintentar.',
        };
      }
      return 'No se pudo validar tu sesión.';
    } catch (_) {
      return 'No se confirmó el envío. El reporte queda pendiente; puedes reintentar sin duplicarlo.';
    } finally {
      client.close();
      _sending.remove(report.id);
    }
  }
}
