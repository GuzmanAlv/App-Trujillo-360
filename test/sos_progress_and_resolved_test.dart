import 'package:alerta_ciudadana/models/incident.dart';
import 'package:alerta_ciudadana/services/active_call.dart';
import 'package:alerta_ciudadana/services/proximity_alerts.dart';
import 'package:alerta_ciudadana/ui/sos_progress_feedback.dart';
import 'package:alerta_ciudadana/ui/map_panel.dart';
import 'package:alerta_ciudadana/ui/report_style.dart';
import 'package:alerta_ciudadana/core/config.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Tocar un caso resuelto muestra fecha sin abrir el formulario',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final now = DateTime.now();
      final closed = Incident(
        id: 'closed',
        type: 'Robo',
        place: '',
        description: '',
        latitude: -8.1,
        longitude: -79,
        createdAt: now.subtract(const Duration(hours: 3)),
        remoteStatus: 'closed',
        resolvedAt: now,
        attention: 'resolved',
      );
      final active = Incident(
        id: 'active',
        type: 'Auxilio',
        place: '',
        description: '',
        latitude: -8.1,
        longitude: -79,
        createdAt: now,
        remoteStatus: 'verified',
      );
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MapPanel(
            incidents: [closed, active],
            onIncident: (_) => opened++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(MapPanel));
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final root =
          state.build(tester.element(find.byType(MapPanel))) as ClipRRect;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final map =
          ((root.child as Stack).children.first as Positioned).child
              as GoogleMap;
      final marker = map.markers.singleWhere(
        (m) => m.markerId.value == 'closed',
      );
      expect(marker.infoWindow.title, contains('Caso resuelto'));
      expect(
        marker.infoWindow.snippet,
        contains(reportDateTime(closed.createdAt)),
      );
      marker.onTap!();
      expect(opened, 0);
      map.markers.singleWhere((m) => m.markerId.value == 'active').onTap!();
      expect(opened, 1);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
    skip: !AppConfig.mapsEnabled,
  );
  test('Resolved incident stays seven days after closure and never alerts', () {
    final now = DateTime.utc(2026, 11, 19, 12);
    Incident resolved(DateTime at, {String status = 'closed'}) => Incident(
      id: 'resolved',
      type: 'Auxilio',
      place: '',
      description: '',
      latitude: -8.1,
      longitude: -79,
      remoteStatus: status,
      createdAt: now.subtract(const Duration(days: 8)),
      attention: 'resolved',
      resolvedAt: at,
    );
    final entry = resolved(now.subtract(const Duration(days: 6)));
    expect(entry.isCommunityVisible && entry.recentAt(now), isTrue);
    expect(
      resolved(now.subtract(const Duration(days: 7))).recentAt(now),
      isFalse,
    );
    expect(
      resolved(now.add(const Duration(seconds: 1))).recentAt(now),
      isFalse,
    );
    expect(resolved(now, status: 'discarded').isCommunityVisible, isFalse);
    expect(Incident.fromJson(entry.toJson()).resolvedAt, entry.resolvedAt);
    final recent = Incident(
      id: 'recent',
      type: 'Robo',
      place: '',
      description: '',
      latitude: -8.1,
      longitude: -79,
      createdAt: now,
      remoteStatus: 'closed',
      resolvedAt: now,
    );
    expect(ProximityAlertPolicy().collect([recent], (_) => 20, now), isEmpty);
  });

  testWidgets(
    'Progress cue stops for calls, background, resolution and disposal',
    (tester) async {
      const channel = MethodChannel('trujillo360/proximity');
      final sent = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'sosProgressSignal') {
          sent.add((call.arguments as Map)['mode'] as String);
        }
        return null;
      });
      addTearDown(() {
        ActiveCall.id.value = null;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      Future<void> show(String? mode) => tester.pumpWidget(
        MaterialApp(
          home: SosProgressFeedback(mode: mode, child: const SizedBox()),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await show('citizen');
      await tester.pump();
      expect(sent.last, 'citizen');
      await tester.pump(const Duration(seconds: 8));
      expect(sent.where((s) => s == 'citizen').length, 2);
      ActiveCall.id.value = 'call';
      await tester.pump();
      expect(sent.last, 'none');
      ActiveCall.id.value = null;
      await tester.pump();
      expect(sent.last, 'citizen');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(sent.last, 'none');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(sent.last, 'citizen');
      await show('operator');
      await tester.pump();
      expect(sent.last, 'operator');
      await show(null);
      await tester.pump();
      expect(sent.last, 'none');
      await show('operator');
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(sent.last, 'none');
    },
  );
}
