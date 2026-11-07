import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/cast_network_address.dart';

void main() {
  test(
    'selects a local source address instead of the renderer address',
    () async {
      final renderer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(renderer.close);
      final connections = renderer.listen((socket) => socket.destroy());
      addTearDown(connections.cancel);
      final chosen = await selectCastAddress(
        '127.0.0.1',
        renderer.port,
      addresses: () async => [
        InternetAddress('192.0.2.5'),
        InternetAddress('127.0.0.2'),
      ],
        allowLoopback: true,
      );
      expect(chosen.address, '127.0.0.2');
      expect(chosen.address, isNot(renderer.address.address));
    },
  );

  test('reports when no usable local address can reach the renderer', () async {
    await expectLater(
      selectCastAddress('192.0.2.1', 80, addresses: () async => []),
      throwsA(isA<StateError>()),
    );
  });
}
