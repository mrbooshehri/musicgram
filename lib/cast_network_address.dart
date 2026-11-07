import 'dart:io';

/// Finds a local interface that can connect to the selected renderer.
Future<InternetAddress> selectCastAddress(
  String host,
  int port, {
  Future<List<InternetAddress>> Function()? addresses,
  bool allowLoopback = false,
}) async {
  final candidates = addresses == null
      ? [
          for (final interface in await NetworkInterface.list(
            type: InternetAddressType.IPv4,
          ))
            ...interface.addresses,
        ]
      : await addresses();
  for (final address in candidates) {
    if (address.type != InternetAddressType.IPv4 ||
        (!allowLoopback && address.isLoopback) ||
        address.address == '0.0.0.0') {
      continue;
    }
    try {
      final socket = await Socket.connect(
        host,
        port,
        sourceAddress: address,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return address;
    } on SocketException {
      // Try another local interface, such as Wi-Fi when a VPN is active.
    }
  }
  throw StateError(
    'Could not reach the device from a local network address. '
    'Check that your phone and device are on the same network.',
  );
}
