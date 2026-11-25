import 'package:flutter/services.dart';

/// Map and case page can overlap while routes animate. One inactive view must
/// not cancel the incoming alert still owned by the other view.
class SosAlarm {
  static const channel = MethodChannel('trujillo360/proximity');
  static final _owners = <Object>{};
  static Future<void> update(Object owner, bool enabled) async {
    if (enabled) {
      _owners.add(owner);
    } else {
      _owners.remove(owner);
    }
    try {
      await channel.invokeMethod<void>('sosIncomingAlarm', {
        'enabled': _owners.isNotEmpty,
      });
    } catch (_) {
      /* Visual controls remain available. */
    }
  }
}
