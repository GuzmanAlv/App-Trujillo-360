import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alerta_ciudadana/services/push_service.dart';

void main() {
  test('Firebase diagnostics expose a code without sensitive details', () {
    final error = FirebaseException(
      plugin: 'firebase_messaging',
      code: 'unknown',
      message: 'private-token-and-account-details',
    );
    expect(PushService.readable(error), contains('unknown'));
    expect(PushService.readable(error), isNot(contains('private-token')));
  });

  test('Platform diagnostics never expose message or details', () {
    final error = PlatformException(
      code: 'permission-denied',
      message: 'private-message',
      details: {'token': 'private-token'},
    );
    expect(PushService.readable(error), contains('permission-denied'));
    expect(PushService.readable(error), isNot(contains('private-')));
  });

  test('Unstructured codes are not displayed', () {
    expect(
      PushService.readable(PlatformException(code: 'secret: value')),
      isNot(contains('secret')),
    );
  });

  test('Timeout and missing plugin provide actionable explanations', () {
    expect(
      PushService.readable(TimeoutException('private-url')),
      contains('tardó demasiado'),
    );
    expect(
      PushService.readable(MissingPluginException('private-details')),
      contains('Actualiza la app'),
    );
  });
}
