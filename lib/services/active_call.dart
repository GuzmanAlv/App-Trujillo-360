import 'package:flutter/foundation.dart';
import 'dart:async';
import 'call_session.dart';

/// Prevents a second in-app incoming prompt while an audio screen is open.
class ActiveCall {
  static final id = ValueNotifier<String?>(null);
  static final session = ValueNotifier<CallSession?>(null);
  static VoidCallback? _listener;
  static bool bind(CallSession value) {
    final old = session.value;
    if (old != null && !identical(old, value) && !old.finished) return false;
    if (identical(old, value)) return true;
    if (old != null) release(old);
    session.value = value;
    id.value = value.callId;
    _listener = () {
      if (value.finished && !value.closing) {
        if (id.value == value.callId) id.value = null;
        if (value.minimized) {
          scheduleMicrotask(() {
            if (identical(session.value, value)) release(value);
          });
        }
      }
    };
    value.addListener(_listener!);
    return true;
  }

  static void release(CallSession value) {
    if (identical(session.value, value)) {
      if (_listener != null) value.removeListener(_listener!);
      _listener = null;
      session.value = null;
      if (id.value == value.callId) id.value = null;
    }
    value.dispose();
  }
}
