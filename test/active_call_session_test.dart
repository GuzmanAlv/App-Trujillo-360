import 'package:alerta_ciudadana/services/active_call.dart';
import 'package:alerta_ciudadana/services/call_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    final session = ActiveCall.session.value;
    if (session != null) ActiveCall.release(session);
    await Future<void>.delayed(Duration.zero);
  });

  test('Minimizar conserva la misma sesión y bloquea otra llamada', () async {
    final call = CallSession(callId: 'one', operator: true);
    final other = CallSession(callId: 'two', operator: true);
    expect(ActiveCall.bind(call), isTrue);
    call.minimized = true;
    expect(ActiveCall.session.value, same(call));
    expect(call.finished, isFalse);
    expect(ActiveCall.id.value, 'one');
    expect(ActiveCall.bind(other), isFalse);
    expect(ActiveCall.bind(call), isTrue);
    expect(ActiveCall.session.value, same(call));
    other.dispose();
  });

  test(
    'Colgar desde la barra compacta libera la sesión y el bloqueo',
    () async {
      final call = CallSession(callId: 'one', operator: true);
      ActiveCall.bind(call);
      call.minimized = true;
      expect(await call.finish(), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(ActiveCall.session.value, isNull);
      expect(ActiveCall.id.value, isNull);
      // Page disposal may arrive after the compact bar has already released it.
      call.dispose();
    },
  );
}
