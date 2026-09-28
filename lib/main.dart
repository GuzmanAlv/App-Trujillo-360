import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'data/incident_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final store = IncidentStore(await SharedPreferences.getInstance())..load();
    runApp(TrujilloApp(store: store));
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'No se pudo iniciar el almacenamiento. Reabre la aplicación.',
            ),
          ),
        ),
      ),
    );
  }
}
