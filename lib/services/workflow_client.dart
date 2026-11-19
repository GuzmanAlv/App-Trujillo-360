import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/config.dart';
import '../models/incident.dart';
import 'report_sender.dart';

class WorkflowClient {
  static Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool bytes = false,
  }) async {
    if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null) {
      throw StateError('Inicia sesión con Google en Configuración.');
    }
    final user = FirebaseAuth.instance.currentUser!;
    final base = Uri.tryParse(ReportSender.endpoint);
    final loopback =
        base != null &&
        (kDebugMode || AppConfig.usbBackend) &&
        base.scheme == 'http' &&
        ['localhost', '127.0.0.1'].contains(base.host);
    if (base == null ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        (!loopback && base.scheme != 'https')) {
      throw StateError('Servidor no configurado.');
    }
    final client = http.Client();
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final token = await user.getIdToken(attempt == 1);
        if (token == null) throw StateError('Sesión vencida.');
        final req =
            http.Request(
                method,
                base.resolve(path).replace(queryParameters: query),
              )
              ..followRedirects = false
              ..headers['Authorization'] = 'Bearer $token';
        if (body != null) {
          req.headers['Content-Type'] = 'application/json';
          req.body = jsonEncode(body);
        }
        final response =
            await (() async => http.Response.fromStream(
              await client.send(req),
            ))().timeout(
              AppConfig.backendRequestTimeout(const Duration(seconds: 30)),
            );
        if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
          throw StateError('La sesión cambió. Vuelve a abrir la pantalla.');
        }
        if (response.statusCode == 401 && attempt == 0) continue;
        if (response.statusCode != 200) {
          if (path.endsWith('/route')) {
            try {
              final error = jsonDecode(response.body);
              final detail = error is Map ? error['detail'] : null;
              final code = detail is Map ? detail['code'] : null;
              const routeErrors = {
                'REINFORCEMENT_CLOSED':
                    'La solicitud de refuerzos ya finalizó o caducó.',
                'SOS_PRIORITY':
                    'Primero llega al SOS ciudadano que tienes asignado. Después podrás trazar la ruta de refuerzos.',
                'ROUTES_NOT_CONFIGURED':
                    'SOS confirmado. Falta configurar Google Routes en el servidor.',
                'ROUTES_REJECTED':
                    'Google Routes rechazó la consulta. Revisa la clave, la API y su facturación.',
                'ROUTE_NOT_FOUND':
                    'No se encontró una ruta en vehículo para este destino.',
                'ROUTES_UNAVAILABLE':
                    'No se pudo consultar Google Routes. Puedes reintentar.',
                'ROUTES_RATE_LIMIT':
                    'Espera unos segundos antes de actualizar la ruta.',
                'ROUTE_CLOSED':
                    'El SOS ya no está activo o aún no está confirmado.',
              };
              if (routeErrors.containsKey(code)) {
                throw StateError(routeErrors[code]!);
              }
            } on FormatException {
              /* Use the regular HTTP message. */
            }
          }
          throw StateError(switch (response.statusCode) {
            401 => 'Sesión vencida. Vuelve a ingresar.',
            403 => 'Tu cuenta no está autorizada para esta operación.',
            404 =>
              'Esta función aún no está disponible en el servidor conectado.',
            409 =>
              path.startsWith('/operator/sos-cases/')
                  ? 'El caso cambió o la acción no está disponible. Recarga la ficha antes de continuar.'
                  : path.startsWith('/calls/')
                  ? 'La llamada terminó, ya fue atendida o tienes otra llamada activa.'
                  : 'El identificador ya fue usado con otros datos.',
            422 => 'Revisa los datos o el estado del caso.',
            _ =>
              'Servidor no disponible. No se confirmó ningún cambio. Vuelve a intentar.',
          });
        }
        return bytes ? response.bodyBytes : jsonDecode(response.body);
      }
      throw StateError('Sesión vencida.');
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> profile() async =>
      Map<String, dynamic>.from(await request('GET', '/me') as Map);
  static Future<Uint8List> photo(String incident, String photo) async =>
      await request(
            'GET',
            '/operator/incidents/$incident/photos/$photo',
            bytes: true,
          )
          as Uint8List;
  static Future<List<Map<String, dynamic>>> list(String path) async =>
      (await request('GET', path) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  static Future<bool> submitHelp(Incident i, String priority) async {
    final result = await request(
      'POST',
      '/help-requests',
      body: {
        'request_id': i.id,
        'category': i.type,
        'place': i.place,
        'description': i.description,
        'latitude': i.latitude,
        'longitude': i.longitude,
        'priority': priority,
      },
    );
    if (result is! Map ||
        result['request_id'] != i.id ||
        result['id'] is! String) {
      throw StateError(
        'No se pudo confirmar la recepción. Conserva los datos y reintenta.',
      );
    }
    return true;
  }
}
