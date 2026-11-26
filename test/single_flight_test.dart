import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_ciudadana/services/single_flight.dart';

void main() {
  test(
    'simultaneous reads share work but completed results are not cached',
    () async {
      final reads = SingleFlight();
      final gate = Completer<int>();
      var count = 0;
      Future<int> work() {
        count++;
        return gate.future;
      }

      final a = reads.run('user1/map', work);
      final b = reads.run('user1/map', work);
      expect(count, 1);
      gate.complete(7);
      expect(await a, 7);
      expect(await b, 7);
      expect(await reads.run('user1/map', () async => ++count), 2);
    },
  );
  test('different accounts stay separate and failures permit retry', () async {
    final reads = SingleFlight();
    final gate = Completer<int>();
    final a = reads.run('user1/map', () => gate.future);
    expect(await reads.run('user2/map', () async => 2), 2);
    gate.complete(1);
    expect(await a, 1);
    await expectLater(
      reads.run<int>('user1/map', () => throw StateError('offline')),
      throwsStateError,
    );
    expect(await reads.run('user1/map', () async => 3), 3);
  });
}
