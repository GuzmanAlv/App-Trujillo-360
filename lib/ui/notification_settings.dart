import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/push_service.dart';
import '../services/workflow_client.dart';
import '../services/location_service.dart';
import 'map_panel.dart';

class NotificationSettings extends StatefulWidget {
  const NotificationSettings({super.key});
  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings>
    with WidgetsBindingObserver {
  final push = PushService.instance;
  bool citizen = false,
      operator = false,
      allowed = false,
      loading = true,
      locating = false;
  int radius = 500;
  LatLng? zone;
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
            zone = null;
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
        zone = p?['latitude'] == null
            ? null
            : LatLng(
                (p!['latitude'] as num).toDouble(),
                (p['longitude'] as num).toDouble(),
              );
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

  Future<void> locate() async {
    setState(() => locating = true);
    try {
      final p = await LocationService().current();
      if (mounted) setState(() => zone = LatLng(p.latitude, p.longitude));
    } catch (_) {
      if (mounted) {
        setState(
          () => note =
              'No se pudo obtener tu ubicación. Puedes elegir un punto en el mapa.',
        );
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> save() async {
    setState(() => note = null);
    try {
      await push.save(
        citizen: citizen,
        operator: operator,
        latitude: zone?.latitude,
        longitude: zone?.longitude,
        radius: radius,
      );
      if (mounted) {
        setState(
          () => note = !citizen && !operator
              ? 'Avisos desactivados en este celular.'
              : push.senderConfigured
              ? 'Preferencias guardadas. Recibirás avisos también fuera de la app.'
              : 'Preferencias guardadas. Falta habilitar el envío de Firebase en el servidor; los avisos aún no están operativos.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => note = PushService.readable(e));
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
                  title: const Text('Incidentes en mi zona'),
                  subtitle: const Text(
                    'Solo incidentes confirmados. También con la app cerrada.',
                  ),
                  value: citizen,
                  onChanged: push.busy
                      ? null
                      : (v) => setState(() => citizen = v),
                ),
                if (citizen) ...[
                  const Text(
                    'Elige el centro de tu zona. Se mantiene fijo aunque te muevas; no rastreamos tu ubicación en segundo plano.',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 260,
                    child: MapPanel(
                      selected: zone,
                      onPick: (p) => setState(() => zone = p),
                      overlays: {
                        if (zone != null)
                          Circle(
                            circleId: const CircleId('chosen-zone'),
                            center: zone!,
                            radius: radius.toDouble(),
                            fillColor: Colors.teal.withValues(alpha: .15),
                            strokeColor: Colors.teal,
                            strokeWidth: 2,
                          ),
                      },
                    ),
                  ),
                  TextButton.icon(
                    onPressed: locating ? null : locate,
                    icon: const Icon(Icons.my_location),
                    label: Text(
                      locating ? 'Buscando…' : 'Usar mi ubicación como centro',
                    ),
                  ),
                  Text(
                    zone == null
                        ? 'Todavía no elegiste una zona.'
                        : 'Centro: ${zone!.latitude.toStringAsFixed(5)}, ${zone!.longitude.toStringAsFixed(5)}',
                  ),
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
                      'Recibir avisos con urgencia Baja, Media o Alta.',
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
