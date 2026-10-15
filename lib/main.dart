import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'data/incident_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StartupApp());
}

class StartupApp extends StatefulWidget {
  const StartupApp({super.key});
  @override
  State<StartupApp> createState() => _StartupAppState();
}

class _StartupAppState extends State<StartupApp> {
  IncidentStore? store;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    setState(() => failed = false);
    try {
      await Firebase.initializeApp();
      final loaded = IncidentStore(await SharedPreferences.getInstance())
        ..load();
      if (mounted) setState(() => store = loaded);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (store != null) return TrujilloApp(store: store!);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xfff4f6f2),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/branding/logo.png', width: 280),
                const SizedBox(height: 32),
                if (!failed) ...[
                  const CircularProgressIndicator(color: Color(0xff087f68)),
                  const SizedBox(height: 16),
                  const Text('Cargando Trujillo 360…'),
                ] else ...[
                  const Text(
                    'No se pudo iniciar Firebase o el almacenamiento. Revisa la configuración y vuelve a intentar.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: initialize,
                    child: const Text('Reintentar'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
