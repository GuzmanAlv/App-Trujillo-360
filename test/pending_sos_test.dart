import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alerta_ciudadana/services/pending_sos.dart';

void main() {
  test(
    'Retoma la misma solicitud y recibo solo para la cuenta propietaria',
    () async {
      SharedPreferences.setMockInitialValues({});
      final pending = <String, dynamic>{
        'request_id': 'same-id',
        'latitude': -8.1,
        'longitude': -79.0,
      };
      await PendingSos.save('owner', pending);
      expect(await PendingSos.read('other'), isNull);
      expect(await PendingSos.read('owner'), pending);
      pending['received_id'] = 'receipt';
      await PendingSos.save('owner', pending);
      expect((await PendingSos.read('owner'))!['request_id'], 'same-id');
      expect((await PendingSos.read('owner'))!['received_id'], 'receipt');
      await PendingSos.clear('owner');
      expect(await PendingSos.read('owner'), isNull);
    },
  );
}
