import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
import '../services/push_service.dart';
import '../services/workflow_client.dart';
import '../services/location_service.dart';

class NotificationSettings extends StatefulWidget {
  const NotificationSettings({super.key});
  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings>
    with WidgetsBindingObserver {
  final push = PushService.instance;
  bool citizen = false, operator = false, allowed = false, loading = true;
  int radius = 500;
  String? note;
  int generation = 0;
  StreamSubscription<User?>? session;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Firebase.apps.isNotEmpty) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      session = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user?.uid != uid && mounted) {
          generation++;
          setState(() {
            citizen = false;
            operator = false;
            allowed = false;
            loading = false;
            note = 'La sesión cambió. Regresa y vuelve a abrir Notificaciones.';
          });
        }
      });
    }
    load();
  }

  @override
  void dispose() {
    generation++;
    session?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      push.refreshPermission().catchError((Object _) {});
      push.startTracking().catchError((Object _) {});
    }
  }

  Future<void> load() async {
    final ticket = ++generation;
    setState(() {
      loading = true;
      note = null;
    });
    try {
      final profile = await WorkflowClient.profile();
      await push.refresh();
      if (!mounted || ticket != generation) return;
      final p = push.preferences;
      setState(() {
        allowed =
            ['operator', 'admin'].contains(profile['role']) &&
            profile['status'] == 'active';
        citizen = p?['citizen_enabled'] == true;
        operator = allowed && p?['operator_enabled'] == true;
        radius = p?['radius'] as int? ?? 500;
        note = push.error;
      });
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(() => note = PushService.readable(e));
      }
    } finally {
      if (mounted && ticket == generation) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    setState(() => note = null);
    try {
      double? latitude, longitude;
      if (citizen) {
        final current = await LocationService().current();
        latitude = current.latitude;
        longitude = current.longitude;
        if (await Geolocator.checkPermission() != LocationPermission.always) {
          if (mounted) {
            setState(
              () => note =
                  'En los ajustes de la app, cambia Ubicación a “Permitir todo el tiempo”. Luego vuelve y guarda las preferencias.',
            );
          }
          await Geolocator.openAppSettings();
          return;
        }
      }
      await push.save(
        citizen: citizen,
        operator: operator,
        latitude: latitude,
        longitude: longitude,
        radius: radius,
        moving: citizen,
      );
      if (mounted) {
        setState(
          () => note = !citizen && !operator
              ? 'Avisos desactivados en este celular.'
              : push.senderConfigured
              ? 'Preferencias guardadas. Tu ubicación se actualizará automáticamente para las alertas.'
              : 'Preferencias guardadas. Falta habilitar el envío de Firebase en el servidor; los avisos aún no están operativos.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              note = e is LocationFailure ? e.message : PushService.readable(e),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notificaciones')),
    body: ListenableBuilder(
      listenable: push,
      builder: (context, _) => loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  push.permission
                      ? 'Permiso de notificaciones: concedido'
                      : 'Permiso de notificaciones: pendiente o desactivado',
                ),
                TextButton.icon(
                  onPressed: () async {
                    await PushService.channel.invokeMethod<void>(
                      'openNotificationSettings',
                    );
                  },
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Abrir ajustes del celular'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Incidentes cerca de mí'),
                  subtitle: const Text(
                    'Incidentes confirmados cerca de donde estés, también con la app cerrada.',
                  ),
                  value: citizen,
                  onChanged: push.busy
                      ? null
                      : (v) => setState(() => citizen = v),
                ),
                if (citizen) ...[
                  const Text(
                    'La ubicación se actualiza automáticamente mientras estos avisos estén activos. Android mostrará una notificación permanente. Necesitas el permiso “Permitir todo el tiempo”.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: radius,
                    decoration: const InputDecoration(
                      labelText: 'Radio de avisos',
                    ),
                    items: [100, 500, 1000, 2000, 3000]
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text('$r metros'),
                          ),
                        )
                        .toList(),
                    onChanged: push.busy
                        ? null
                        : (r) => setState(() => radius = r!),
                  ),
                ],
                if (allowed)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Nuevos reportes para el operador'),
                    subtitle: const Text(
                      'Recibir avisos de nuevos reportes y solicitudes SOS.',
                    ),
                    value: operator,
                    onChanged: push.busy
                        ? null
                        : (v) => setState(() => operator = v),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: push.busy ? null : save,
                  child: Text(
                    push.busy ? 'Guardando…' : 'Guardar preferencias',
                  ),
                ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(note!),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Se necesita Internet. La entrega puede demorarse por la conexión o el ahorro de batería; no es un canal de atención de emergencias.',
                ),
                TextButton(
                  onPressed: push.busy ? null : load,
                  child: const Text('Actualizar estado'),
                ),
              ],
            ),
    ),
  );
}
