class AppConfig {
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
