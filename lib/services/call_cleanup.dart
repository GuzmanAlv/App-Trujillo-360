import 'dart:async';

/// Each cleanup runs independently; an unavailable SDK/server cannot trap navigation.
Future<bool> closeCallResources(
  Iterable<Future<void> Function()> actions, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  final results = await Future.wait(
    actions.map((action) async {
      try {
        await Future<void>.sync(action).timeout(timeout);
        return true;
      } catch (_) {
        return false;
      }
    }),
  );
  return results.every((result) => result);
}
