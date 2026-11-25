import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:alerta_ciudadana/services/call_session.dart';
import 'package:alerta_ciudadana/services/workflow_client.dart';

class RecoveryRoom extends Fake implements Room {
  int disconnects = 0;
  @override
  Future<void> disconnect() async {
    disconnects++;
  }

  @override
  void removeListener(void Function() callback) {}
  @override
  Future<bool> dispose() async => true;
}

void main() {
  testWidgets(
    'Una transferencia desconecta la sala anterior y conserva la búsqueda del mismo SOS',
    (tester) async {
      final room = RecoveryRoom();
      final call =
          CallSession(
              callId: 'case',
              operator: false,
              room: room,
              readStatus: () async => {
                'state': 'waiting_assignment',
                'can_join': false,
              },
            )
            ..joined = true
            ..joinedRoom = 'previous-room';
      await call.refresh();
      expect(room.disconnects, 1);
      expect(call.joined, isFalse);
      expect(call.finished, isFalse);
      expect(call.message, contains('otro operador'));
      call.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'Un fallo temporal conserva el audio y se recupera; autorización denegada lo corta',
    (tester) async {
      final room = RecoveryRoom();
      var offline = true;
      var denied = false;
      final call = CallSession(
        callId: 'case',
        operator: true,
        room: room,
        readStatus: () async {
          if (denied) throw WorkflowFailure('Sin acceso', status: 403);
          if (offline) throw WorkflowFailure('Servidor temporal', status: 503);
          return {'state': 'accepted', 'can_join': true};
        },
      )..joined = true;
      await call.refresh();
      expect(room.disconnects, 0);
      await tester.pump(const Duration(seconds: 30));
      offline = false;
      await call.refresh();
      expect(call.failure, isNull);
      await tester.pump(const Duration(seconds: 40));
      expect(room.disconnects, 0);
      offline = true;
      await call.refresh();
      await tester.pump(const Duration(seconds: 61));
      expect(room.disconnects, 1);
      denied = true;
      await call.refresh();
      expect(call.finished, isTrue);
      expect(room.disconnects, 2);
      call.dispose();
      await tester.pump();
    },
  );
}
