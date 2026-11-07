import 'dart:io';

import 'package:flutter/services.dart';
import 'package:upnp_client/upnp_client.dart';

class UpnpRenderer {
  const UpnpRenderer({
    required this.id,
    required this.name,
    required this.canPlay,
    this.renderer,
  });
  final String id;
  final String name;
  final bool canPlay;
  final MediaRenderer? renderer;
}

Future<List<UpnpRenderer>> discoverUpnpRenderers() async {
  const channel = MethodChannel('musicgram/library');
  var locked = false;
  final discoverer = DeviceDiscoverer();
  final errors = discoverer.errors.listen(
    null,
    onError: (Object _, StackTrace _) {},
  );
  try {
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('acquireUpnpMulticast');
      locked = true;
    }
    await discoverer.start(addressTypes: [InternetAddressType.IPv4]);
    final devices = await discoverer.getDevices(
      searchTarget: UpnpDeviceType.mediaRenderer.urn(),
      timeout: const Duration(seconds: 5),
    );
    final results = <String, UpnpRenderer>{};
    void addDevice(Device device, String? parentUrl) {
      final url = device.url ?? parentUrl;
      if (device is MediaRenderer) {
        final id = device.description?.udn ?? url;
        if (id != null && id.isNotEmpty) {
          final name = device.description?.friendlyName?.trim();
          results[id] = UpnpRenderer(
            id: id,
            name: name == null || name.isEmpty ? 'UPnP device' : name,
            canPlay: device.avTransport != null,
            renderer: device,
          );
        }
      }
      for (final child in device.devices) {
        addDevice(child, url);
      }
    }

    for (final device in devices) {
      addDevice(device, null);
    }
    return results.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  } finally {
    await errors.cancel();
    discoverer.dispose();
    if (locked) await channel.invokeMethod<void>('releaseUpnpMulticast');
  }
}
