import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_ciudadana/services/call_cleanup.dart';

void main() {
  test(
    'Una desconexión bloqueada no bloquea el servidor ni la salida',
    () async {
      final stuck = Completer<void>();
      var notified = false;
      final complete = await closeCallResources([
        () => stuck.future,
        () async {
          notified = true;
        },
      ], timeout: const Duration(milliseconds: 20));
      expect(complete, isFalse);
      expect(notified, isTrue);
      // A late SDK error must also be consumed, not become an uncaught error.
      stuck.completeError(StateError('late disconnect error'));
      await Future<void>.delayed(Duration.zero);
    },
  );
  test('Un error síncrono no evita detener el micrófono', () async {
    var stopped = false;
    expect(
      await closeCallResources([
        () => throw StateError('SDK error'),
        () async {
          stopped = true;
        },
      ]),
      isFalse,
    );
    expect(stopped, isTrue);
  });
  test(
    'Cancelar antes de conectarse no requiere desconectar una sala',
    () async {
      expect(await closeCallResources([]), isTrue);
    },
  );
}
