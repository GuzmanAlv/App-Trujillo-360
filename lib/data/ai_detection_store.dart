import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/ai_detection.dart';

enum AiConnection { disconnected, listening, failed }

/// Bandeja temporal: no publica incidentes ni persiste evidencia.
class AiDetectionStore extends ChangeNotifier {
  final Map<String, AiDetection> _items = {};
  List<AiDetection> get items => List.unmodifiable(
    _items.values.toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt)),
  );
  AiConnection connection = AiConnection.disconnected;
  int rejectedEvents = 0;
  StreamSubscription<dynamic>? _subscription;
  int _generation = 0;
  bool _disposed = false;

  /// Recibe el stream de un WebSocket autenticado por el backend.
  Future<void> attach(Stream<dynamic> events) async {
    final generation = ++_generation;
    await _subscription?.cancel();
    if (_disposed || generation != _generation) return;
    connection = AiConnection.listening;
    notifyListeners();
    _subscription = events.listen(
      (event) {
        if (!_disposed && generation == _generation) ingest(event);
      },
      onError: (Object error) {
        if (_disposed || generation != _generation) return;
        connection = AiConnection.failed;
        notifyListeners();
      },
      onDone: () {
        if (_disposed || generation != _generation) return;
        if (connection != AiConnection.failed) {
          connection = AiConnection.disconnected;
        }
        notifyListeners();
      },
      cancelOnError: true,
    );
  }

  void ingest(dynamic event) {
    if (_disposed) return;
    try {
      if (event is! String || event.length > 16384) {
        throw const FormatException('Evento inválido');
      }
      final json = jsonDecode(event);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Se esperaba un objeto');
      }
      final detection = AiDetection.fromJson(json);
      // Los reenvíos no crean candidatos duplicados.
      if (_items.containsKey(detection.id)) return;
      _items[detection.id] = detection;
      if (_items.length > 200) _items.remove(items.last.id);
    } catch (_) {
      rejectedEvents++;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _subscription?.cancel();
    super.dispose();
  }
}
