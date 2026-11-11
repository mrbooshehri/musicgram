import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/upnp_cast_session.dart';
import 'package:upnp_client/upnp_client.dart';

void main() {
  test('stops receiver and retries a rejected track transition', () async {
    final actions = <String>[];
    await setCastTransportUri(
      setUri: () async {
        actions.add('set');
        if (actions.length == 1) throw UPnPException(errorCode: 701);
      },
      stop: () async => actions.add('stop'),
    );
    expect(actions, ['set', 'stop', 'set']);
  });
  test('does not stop or retry unrelated receiver errors', () async {
    var stopped = false;
    await expectLater(
      setCastTransportUri(
        setUri: () async => throw UPnPException(errorCode: 714),
        stop: () async {
          stopped = true;
        },
      ),
      throwsA(isA<UPnPException>()),
    );
    expect(stopped, isFalse);
  });
}
