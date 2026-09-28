import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Adaptador opcional. La interfaz sigue en modo local hasta implementar
/// autenticación y acordar los endpoints reales con FastAPI.
class BackendClient {
  BackendClient({
    required this.baseUrl,
    required this.token,
    http.Client? client,
  }) : client = client ?? http.Client() {
    if (baseUrl.scheme != 'https') {
      throw ArgumentError('La API debe utilizar HTTPS.');
    }
  }
  final Uri baseUrl;
  final String token;
  final http.Client client;
  Future<List<dynamic>> getIncidents() async {
    final response = await client
        .get(
          baseUrl.resolve('incidents'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('La API devolvió ${response.statusCode}.');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Usar una URL WSS autenticada mediante un ticket efímero del backend.
  WebSocketChannel events(Uri url) {
    if (url.scheme != 'wss') {
      throw ArgumentError('Los eventos deben utilizar WSS.');
    }
    return WebSocketChannel.connect(url);
  }

  void dispose() => client.close();
}
