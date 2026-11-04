import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'report_sender.dart';
import 'workflow_client.dart';

@pragma('vm:entry-point')
Future<void> backgroundMessage(RemoteMessage message) async {
  // FCM notification payloads are displayed by Android. Never display them twice.
}

class PushService extends ChangeNotifier {
  static final instance = PushService._();
  PushService._();
  static const channel = MethodChannel('trujillo360/proximity');
  final opened = StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic>? pending;
  Map<String, dynamic>? preferences;
  String? owner, deviceId, error;
  bool senderConfigured = false, permission = false, busy = false;
  bool started = false, signingOut = false;
  int generation = 0;
  final Set<String> seen = {};
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> start() async {
    if (started || !supported || Firebase.apps.isEmpty) return;
    started = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'openPush') {
        accept(
          Map<String, dynamic>.from(
            jsonDecode(call.arguments as String) as Map,
          ),
        );
      }
    });
    FirebaseMessaging.onBackgroundMessage(backgroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => accept(m.data));
    FirebaseMessaging.onMessage.listen((m) async {
      if (!valid(m.data)) return;
      final id = m.data['event_id']?.toString() ?? m.messageId;
      if (id == null || !seen.add(id)) return;
      try {
        await channel.invokeMethod<void>('showPush', {
          'id': id,
          'title': m.notification?.title ?? 'Trujillo 360',
          'body': m.notification?.body ?? 'Tienes un nuevo aviso.',
          'payload': jsonEncode(m.data),
        });
      } catch (_) {
        /* Permission may have been revoked in Android settings. */
      }
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      if (signingOut ||
          owner == null ||
          preferences == null ||
          deviceId == null) {
        return;
      }
      if (preferences!['citizen_enabled'] != true &&
          preferences!['operator_enabled'] != true) {
        return;
      }
      try {
        await register(token, Map<String, dynamic>.from(preferences!));
      } catch (_) {
        error =
            'No se pudo renovar el registro. Abre Notificaciones para reintentar.';
        notifyListeners();
      }
    });
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      generation++;
      owner = user?.uid;
      deviceId = null;
      preferences = null;
      error = null;
      busy = false;
      senderConfigured = false;
      seen.clear();
      notifyListeners();
      if (user != null) {
        signingOut = false;
        await refresh();
      }
    });
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) accept(initial.data);
    try {
      final raw = await channel.invokeMethod<String>('takePush');
      if (raw != null) {
        accept(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      }
    } catch (_) {
      /* Native bridge is optional outside Android. */
    }
  }

  bool valid(Map<String, dynamic> data) =>
      Firebase.apps.isNotEmpty &&
      FirebaseAuth.instance.currentUser != null &&
      data['account_uid'] == FirebaseAuth.instance.currentUser?.uid &&
      ['citizen', 'operator'].contains(data['kind']) &&
      RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch('${data['target_id']}');
  void accept(Map<String, dynamic> data) {
    if (!valid(data)) return;
    pending = data;
    opened.add(data);
  }

  Future<String> installation(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'push.device.$uid';
    final existing = prefs.getString(key);
    if (existing != null) return existing;
    final id = ReportSender.requestId();
    if (!await prefs.setString(key, id)) {
      throw StateError('No se pudo guardar el registro del dispositivo.');
    }
    return id;
  }

  Future<void> refreshPermission() async {
    if (!supported || Firebase.apps.isEmpty) return;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    permission =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    notifyListeners();
  }

  Future<void> refresh() async {
    final uid = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !supported) return;
    final ticket = ++generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final id = await installation(uid);
      final data = await WorkflowClient.request('GET', '/push/devices/$id');
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (ticket != generation ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      owner = uid;
      deviceId = id;
      preferences = data['preferences'] == null
          ? null
          : Map<String, dynamic>.from(data['preferences'] as Map);
      senderConfigured = data['sender_configured'] == true;
      permission =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (permission &&
          preferences != null &&
          (preferences!['citizen_enabled'] == true ||
              preferences!['operator_enabled'] == true)) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && ticket == generation) {
          await register(token, Map<String, dynamic>.from(preferences!));
        }
      }
    } catch (e) {
      if (ticket == generation) error = readable(e);
    } finally {
      if (ticket == generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> register(String token, Map<String, dynamic> values) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid != owner || signingOut || deviceId == null) {
      throw StateError('La sesión cambió.');
    }
    final result = await WorkflowClient.request(
      'PUT',
      '/push/devices/$deviceId',
      body: {
        'token': token,
        for (final key in [
          'citizen_enabled',
          'operator_enabled',
          'latitude',
          'longitude',
          'radius',
        ])
          key: values[key],
      },
    );
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;
    preferences = Map<String, dynamic>.from(result['preferences'] as Map);
    senderConfigured = result['sender_configured'] == true;
  }

  Future<void> save({
    required bool citizen,
    required bool operator,
    double? latitude,
    double? longitude,
    int radius = 500,
  }) async {
    if (!supported ||
        Firebase.apps.isEmpty ||
        FirebaseAuth.instance.currentUser == null) {
      throw StateError('Inicia sesión con Google en Android.');
    }
    if (citizen && (latitude == null || longitude == null)) {
      throw StateError('Elige tu zona en el mapa.');
    }
    final uid = FirebaseAuth.instance.currentUser!.uid;
    busy = true;
    error = null;
    var step = 'preparar el celular';
    notifyListeners();
    try {
      owner = uid;
      deviceId = await installation(owner!);
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('La sesión cambió.');
      }
      if (!citizen && !operator) {
        await WorkflowClient.request('DELETE', '/push/devices/$deviceId');
        preferences = null;
        await channel.invokeMethod<void>('clearPush');
        return;
      }
      step = 'pedir el permiso de notificaciones';
      final settings = await FirebaseMessaging.instance.requestPermission();
      permission =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!permission) {
        throw StateError(
          'Permiso bloqueado. Habilita las notificaciones en los ajustes del celular.',
        );
      }
      step = 'activar Firebase en el celular';
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      step = 'registrar el celular en Firebase';
      final token = await FirebaseMessaging.instance.getToken();
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('La sesión cambió.');
      }
      if (token == null) {
        throw StateError(
          'No se pudo registrar este celular. Reintenta con conexión a Internet.',
        );
      }
      step = 'guardar los avisos en el servidor';
      await register(token, {
        'citizen_enabled': citizen,
        'operator_enabled': operator,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
      });
    } catch (e) {
      error = e is StateError
          ? readable(e)
          : 'No se pudo $step. ${readable(e)}';
      // Log only the safe explanation, never raw exceptions or FCM tokens.
      debugPrint('PUSH_REGISTRATION: $error');
      throw StateError(error!);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> beforeSignOut() async {
    if (!supported ||
        Firebase.apps.isEmpty ||
        FirebaseAuth.instance.currentUser == null) {
      return;
    }
    signingOut = true;
    var revoked = false;
    try {
      final id = await installation(FirebaseAuth.instance.currentUser!.uid);
      await WorkflowClient.request(
        'DELETE',
        '/push/devices/$id',
      ).timeout(const Duration(seconds: 12));
      revoked = true;
    } catch (_) {
      /* Invalidating FCM token also revokes delivery. */
    }
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
      await FirebaseMessaging.instance.deleteToken();
      revoked = true;
    } catch (_) {}
    if (!revoked) {
      signingOut = false;
      throw StateError(
        'Conéctate a Internet para desvincular los avisos antes de cerrar sesión.',
      );
    }
    try {
      await channel.invokeMethod<void>('clearPush');
    } catch (_) {}
    pending = null;
    preferences = null;
  }

  static String readable(Object e) {
    if (e is StateError) return e.message;
    if (e is TimeoutException) {
      return 'La conexión tardó demasiado. Reintenta con Internet.';
    }
    if (e is MissingPluginException) {
      return 'Esta instalación no pudo cargar el servicio de notificaciones. Actualiza la app.';
    }
    final code = e is FirebaseException
        ? e.code
        : e is PlatformException
        ? e.code
        : null;
    if (code != null && RegExp(r'^[a-zA-Z0-9_/-]{1,80}$').hasMatch(code)) {
      return 'El servicio de Firebase respondió con el código $code. Reintenta.';
    }
    return 'No se pudo conectar el servicio de notificaciones. Reintenta.';
  }
}
