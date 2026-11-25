import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deduplicates the map poll and foreground FCM event for the same arrival.
class CitizenArrivalAlerts extends ValueNotifier<String?>
    with WidgetsBindingObserver {
  CitizenArrivalAlerts._() : super(null);
  static final instance = CitizenArrivalAlerts._();
  static const channel = MethodChannel('trujillo360/proximity');
  Timer? _hide;
  final _pending = <String>{};
  bool _started = false;
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    if (Firebase.apps.isNotEmpty) {
      FirebaseAuth.instance.authStateChanges().listen((_) => clear());
    }
  }

  static String seenKey(String uid, String id) => 'sos.arrived.$uid.$id';
  Future<void> receive(String caseId, {bool notification = true}) async {
    final uid = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final key = seenKey(uid, caseId);
    if (!_pending.add(key)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (prefs.getBool(key) == true ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      await prefs.setBool(key, true);
      if (FirebaseAuth.instance.currentUser?.uid != uid) return;
      value = caseId;
      _hide?.cancel();
      _hide = Timer(const Duration(seconds: 5), () => value = null);
      try {
        await channel.invokeMethod('sosArrivalSignal');
        if (notification) {
          await channel.invokeMethod('showPush', {
            'id': 'arrival_$caseId',
            'title': 'La policía llegó al lugar',
            'body': 'El operador ya se encuentra en la zona de tu SOS.',
            'quiet': true,
            'payload': jsonEncode({
              'kind': 'sos_arrival',
              'target_id': caseId,
              'account_uid': uid,
              'event_id': 'arrival_$caseId',
            }),
          });
        }
      } catch (_) {
        /* The map banner remains available without Android. */
      }
    } finally {
      _pending.remove(key);
    }
  }

  void clear() {
    _hide?.cancel();
    value = null;
    unawaited(
      channel.invokeMethod('stopSosArrivalSignal').catchError((Object _) {}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) clear();
  }
}
