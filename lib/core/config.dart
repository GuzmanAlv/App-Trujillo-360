class AppConfig {
  static const localPilot = bool.fromEnvironment('LOCAL_PILOT');
  static const usbBackend = bool.fromEnvironment('USB_BACKEND');
  static Duration backendRequestTimeout(Duration normal) =>
      Uri.tryParse(
            const String.fromEnvironment('BACKEND_URL'),
          )?.host.endsWith('.onrender.com') ==
          true
      ? const Duration(seconds: 90)
      : normal;
  static const mapsEnabled = bool.fromEnvironment('MAPS_ENABLED');
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const vapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
  static bool get firebaseConfigured => [
    firebaseApiKey,
    firebaseAppId,
    firebaseProjectId,
    firebaseSenderId,
  ].every((s) => s.isNotEmpty);
}
