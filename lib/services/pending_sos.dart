import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persist the idempotency key before sending and the receipt before opening audio.
class PendingSos {
  static String key(String owner) => 'sos.pending.$owner';
  static Future<Map<String, dynamic>?> read(String owner) async {
    final raw = (await SharedPreferences.getInstance()).getString(key(owner));
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      throw StateError(
        'No se pudo leer el SOS pendiente del teléfono. Revisa Mis Solicitudes antes de iniciar otro.',
      );
    }
  }

  static Future<void> save(String owner, Map<String, dynamic> value) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      key(owner),
      jsonEncode(value),
    )) {
      throw StateError(
        'No se pudo conservar el SOS en el teléfono. Libera espacio y reintenta.',
      );
    }
  }

  static Future<void> clear(String owner) async {
    await (await SharedPreferences.getInstance()).remove(key(owner));
  }
}
