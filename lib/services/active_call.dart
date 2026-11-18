import 'package:flutter/foundation.dart';

/// Prevents a second in-app incoming prompt while an audio screen is open.
class ActiveCall {
  static final id = ValueNotifier<String?>(null);
}
