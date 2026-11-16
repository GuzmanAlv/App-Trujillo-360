import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

class SosShortcutSettings extends StatefulWidget {
  const SosShortcutSettings({super.key});

  @override
  State<SosShortcutSettings> createState() => _SosShortcutSettingsState();
}

class _SosShortcutSettingsState extends State<SosShortcutSettings>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('trujillo360/proximity');
  bool enabled = false;
  bool testOnly = true;
  bool permission = false;
  bool busy = true;
  String? message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    try {
      final status = await channel.invokeMapMethod<String, dynamic>(
        'sosVolumeStatus',
      );
      if (!mounted) return;
      setState(() {
        enabled = status?['enabled'] == true;
        testOnly = status?['test_only'] != false;
        permission = status?['permission'] == true;
        busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          message = 'Este acceso solo está disponible en Android.';
        });
      }
    }
  }

  Future<void> save({required bool active, required bool trial}) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (active && !trial) {
        if (FirebaseAuth.instance.currentUser == null) {
          throw StateError(
            'Inicia sesión con Google antes de activar el SOS real.',
          );
        }
        if (await Geolocator.checkPermission() != LocationPermission.always) {
          throw StateError(
            'Permite la ubicación todo el tiempo en los ajustes del celular para enviar el SOS con la pantalla apagada.',
          );
        }
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Activar SOS real'),
            content: const Text(
              'Desde ahora, tres pulsaciones de volumen abajo enviarán tu ubicación al operador, incluso con la pantalla apagada. La vibración larga confirma recepción por el servidor.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Activar'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      await channel.invokeMethod<void>('setSosVolume', {
        'enabled': active,
        'test_only': trial,
      });
      if (mounted) {
        setState(() {
          enabled = active;
          testOnly = trial;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          message = error is StateError
              ? error.message.toString()
              : 'No se pudo guardar la opción.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SOS con botón de volumen')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Pulsa volumen abajo tres veces en menos de 2 segundos. Prueba primero con la app abierta, después cerrada y con el teléfono bloqueado.',
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Activar gesto en este celular'),
          value: enabled,
          onChanged: busy
              ? null
              : (value) => save(active: value, trial: testOnly),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Solo probar detección'),
          subtitle: const Text(
            'Dos vibraciones cortas indican que se detectó el gesto. No envía SOS ni avisa al operador.',
          ),
          value: testOnly,
          onChanged: busy
              ? null
              : (value) => save(active: enabled, trial: value),
        ),
        const SizedBox(height: 12),
        Text(
          permission
              ? 'Permiso de accesibilidad: activado'
              : 'Permiso de accesibilidad: pendiente',
        ),
        TextButton.icon(
          onPressed: busy
              ? null
              : () => channel.invokeMethod<void>('openSosAccessibility'),
          icon: const Icon(Icons.settings_accessibility),
          label: const Text('Abrir ajustes de accesibilidad'),
        ),
        const Text(
          'En Accesibilidad, activa “SOS con botón de volumen”. El permiso se configura en este celular. Puedes desactivarlo allí en cualquier momento.',
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              message!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 20),
        const Text(
          'En modo real: una vibración breve indica que se detectó el gesto. Una vibración larga confirma que el servidor recibió el SOS; tres vibraciones cortas indican que falló y debes reintentar. La recepción no confirma atención inmediata.',
        ),
      ],
    ),
  );
}
