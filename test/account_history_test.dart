import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_ciudadana/models/incident.dart';
import 'package:alerta_ciudadana/services/my_reports_client.dart';
import 'package:alerta_ciudadana/ui/account_panel.dart';

Incident report(String id, String? owner, {String? remoteId}) => Incident(
  id: id,
  ownerUid: owner,
  remoteId: remoteId,
  type: 'Robo',
  place: 'Prueba',
  description: '',
  latitude: 0,
  longitude: 0,
  createdAt: DateTime(2026),
);
void main() {
  test(
    'El historial recupera reportes remotos, conserva pendientes y aísla cuentas',
    () {
      final local = [
        report('same', 'a'),
        report('pending', 'a'),
        report('other', 'b'),
        report('anonymous', null),
      ];
      final remote = [
        report('same', 'a', remoteId: 'server'),
        report('new-phone', 'a', remoteId: 'server2'),
      ];
      final result = mergeMyReports('a', remote, local);
      expect(result.map((i) => i.id).toSet(), {'same', 'pending', 'new-phone'});
      expect(result.firstWhere((i) => i.id == 'same').remoteId, 'server');
      expect(mergeMyReports(null, remote, local), isEmpty);
      expect(mergeMyReports('b', remote, local).single.id, 'other');
    },
  );
  testWidgets('Foto ausente usa iniciales y sin nombre usa icono', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AccountAvatar(name: 'Ana Torres')),
      ),
    );
    expect(find.text('AT'), findsOneWidget);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AccountAvatar())),
    );
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });
}
