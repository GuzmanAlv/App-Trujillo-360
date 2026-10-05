import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class BackendProfile extends StatefulWidget {
  const BackendProfile({super.key, required this.user});
  final User user;
  @override
  State<BackendProfile> createState() => _BackendProfileState();
}

class _BackendProfileState extends State<BackendProfile> {
  static const endpoint = String.fromEnvironment('BACKEND_URL');
  bool busy = false;
  String status = 'Perfil del servidor pendiente.';
  @override
  void initState() {
    super.initState();
    if (endpoint.isNotEmpty) sync();
  }

  Future<void> sync() async {
    if (busy) return;
    setState(() => busy = true);
    final client = http.Client();
    try {
      final base = Uri.parse(endpoint);
      final localDebug =
          kDebugMode &&
          base.scheme == 'http' &&
          ['127.0.0.1', 'localhost'].contains(base.host);
      if ((!localDebug && base.scheme != 'https') ||
          base.host.isEmpty ||
          base.userInfo.isNotEmpty) {
        throw const FormatException();
      }
      for (var attempt = 0; attempt < 2; attempt++) {
        final token = await widget.user.getIdToken(attempt == 1);
        if (token == null) throw StateError('Sesión requerida');
        final request = http.Request('GET', base.resolve('/me'))
          ..followRedirects = false
          ..headers['Authorization'] = 'Bearer $token';
        final response = await (() async => http.Response.fromStream(
          await client.send(request),
        ))().timeout(const Duration(seconds: 15));
        if (response.statusCode == 401 && attempt == 0) continue;
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['id'] is! String || data['status'] != 'active') {
            throw const FormatException();
          }
          status = 'Cuenta conectada a Supabase.';
        } else {
          status = switch (response.statusCode) {
            401 =>
              'La sesión no fue aceptada. Cierra sesión e ingresa nuevamente.',
            403 => 'Tu cuenta está suspendida.',
            _ => 'El servidor no está disponible. Intenta nuevamente.',
          };
        }
        break;
      }
    } catch (_) {
      status =
          'No se pudo conectar tu cuenta. Comprueba que el servidor esté iniciado.';
    } finally {
      client.close();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        endpoint.isEmpty
            ? 'Conexión al servidor pendiente de configurar.'
            : status,
      ),
      if (endpoint.isNotEmpty)
        TextButton(
          onPressed: busy ? null : sync,
          child: Text(busy ? 'Conectando cuenta…' : 'Actualizar conexión'),
        ),
    ],
  );
}
