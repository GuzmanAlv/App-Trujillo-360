import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'backend_profile.dart';

/// Firebase persists the session; no tokens are stored in local preferences.
class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key});

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  static Future<void>? googleInitialization;
  bool busy = false;
  String? error;

  Future<void> changeSession({required bool signOut}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (signOut) {
        await FirebaseAuth.instance.signOut();
        if (googleInitialization != null) {
          await GoogleSignIn.instance.signOut();
        }
      } else {
        try {
          await (googleInitialization ??= GoogleSignIn.instance.initialize());
        } catch (_) {
          googleInitialization = null;
          rethrow;
        }
        final account = await GoogleSignIn.instance.authenticate();
        final token = account.authentication.idToken;
        if (token == null) {
          throw StateError('Missing Google ID token');
        }
        await FirebaseAuth.instance.signInWithCredential(
          GoogleAuthProvider.credential(idToken: token),
        );
      }
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        error =
            'No se pudo acceder con Google. Revisa tu conexión y vuelve a intentar. '
            'Si persiste, revisa la configuración de acceso de la aplicación.';
      }
    } on FirebaseAuthException catch (e) {
      error = switch (e.code) {
        'network-request-failed' =>
          'Comprueba tu conexión a Internet e intenta nuevamente.',
        'user-disabled' => 'Esta cuenta está deshabilitada.',
        'operation-not-allowed' =>
          'El acceso con Google todavía no está habilitado en Firebase.',
        'account-exists-with-different-credential' =>
          'Esta cuenta ya utiliza otro método de acceso.',
        _ => 'No se pudo completar el acceso. Intenta nuevamente.',
      };
    } catch (_) {
      error =
          'No se pudo completar la operación. Revisa la configuración de Google e intenta nuevamente.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        Firebase.apps.isEmpty) {
      return const ListTile(
        leading: Icon(Icons.person_outline),
        title: Text('Mi cuenta'),
        subtitle: Text(
          'El acceso con Google requiere la aplicación Android configurada con Firebase.',
        ),
      );
    }
    final auth = FirebaseAuth.instance;
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      initialData: auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AccountAvatar(
                      photoUrl: user?.photoURL,
                      name: user?.displayName,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        user == null
                            ? 'Mi cuenta'
                            : (user.displayName?.trim().isNotEmpty == true
                                  ? user.displayName!
                                  : 'Usuario'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (user == null)
                  const Text(
                    'Inicia sesión para identificarte en Trujillo 360.',
                  ),
                if (user?.email != null) Text(user!.email!),
                if (user != null) const Text('Sesión iniciada con Firebase.'),
                if (user != null)
                  BackendProfile(key: ValueKey(user.uid), user: user),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => changeSession(signOut: user != null),
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(user == null ? Icons.login : Icons.logout),
                  label: Text(
                    busy
                        ? 'Procesando…'
                        : user == null
                        ? 'Continuar con Google'
                        : 'Cerrar sesión',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      semanticsLabel: error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, this.photoUrl, this.name});
  final String? photoUrl, name;
  @override
  Widget build(BuildContext context) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2);
    final initials = parts
        .map((p) => String.fromCharCode(p.runes.first))
        .join()
        .toUpperCase();
    final url = Uri.tryParse(photoUrl ?? '');
    final fallback = CircleAvatar(
      radius: 24,
      child: initials.isEmpty
          ? const Icon(Icons.person_outline)
          : Text(initials),
    );
    return Semantics(
      label: 'Foto de perfil',
      image: true,
      child: SizedBox(
        width: 48,
        height: 48,
        child: url?.scheme == 'https' && url!.host.isNotEmpty
            ? ClipOval(
                child: Image.network(
                  url.toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : fallback,
                ),
              )
            : fallback,
      ),
    );
  }
}
