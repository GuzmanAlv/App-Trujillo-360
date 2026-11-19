import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SosNavigation {
  static final caseChanges = ValueNotifier<({String id, bool closed})?>(null);
  static void caseUpdated(Map<String, dynamic> row) {
    caseChanges.value = (
      id: '${row['id']}',
      closed: row['decision'] == 'discarded' || row['attention'] == 'resolved',
    );
  }

  static final mapRequested = ValueNotifier(0);
  static void showMap() {
    mapRequested.value++;
  }

  static final request =
      ValueNotifier<({String caseId, String owner, int serial})?>(null);
  static int _serial = 0;
  static void open(String caseId) {
    final owner = FirebaseAuth.instance.currentUser?.uid;
    if (owner != null) {
      request.value = (caseId: caseId, owner: owner, serial: ++_serial);
    }
  }
}
