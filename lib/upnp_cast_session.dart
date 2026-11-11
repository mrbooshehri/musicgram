import 'dart:io';

import 'package:upnp_client/didl.dart';
import 'package:upnp_client/upnp_client.dart';

import 'cast_media_server.dart';
import 'cast_network_address.dart';
import 'playback_controller.dart';
import 'upnp_discovery.dart';

/// Some renderers require the current transport to stop before changing URI.
Future<void> setCastTransportUri({
  required Future<void> Function() setUri,
  required Future<void> Function() stop,
}) async {
  try {
    await setUri();
  } on UPnPException catch (error) {
    if (error.errorCode != 701) rethrow;
    await stop();
    await setUri();
  }
}

class UpnpCastSession implements RemotePlaybackSession {
  UpnpCastSession._(
    this.deviceName,
    this._transport,
    this._rendering,
    this._address,
  );

  @override
  final String deviceName;
  final AvTransportService _transport;
  final RenderingControlService? _rendering;
  final InternetAddress _address;
  CastMediaServer? _server;
  bool _closed = false;
  @override
  bool get supportsVolume => _rendering != null;

  static Future<UpnpCastSession> prepare(
    UpnpRenderer device,
    LocalTrack track,
    Duration duration,
  ) async {
    final renderer = device.renderer;
    final transport = renderer?.avTransport;
    final address = Uri.tryParse(renderer?.urlBase ?? renderer?.url ?? '');
    if (transport == null || address == null || address.host.isEmpty) {
      throw StateError('This device does not support playback control.');
    }
    final localAddress = await selectCastAddress(
      address.host,
      address.hasPort ? address.port : 80,
    );
    final session = UpnpCastSession._(
      device.name,
      transport,
      renderer?.renderingControl,
      localAddress,
    );
    await session._setTrack(track, duration);
    return session;
  }

  Future<void> _setTrack(LocalTrack track, Duration duration) async {
    if (_closed) throw StateError('Casting has stopped.');
    final content = track.telegramMessage?['content'];
    final media = content is Map
        ? (content['audio'] ?? content['document'])
        : null;
    final mimeType = media is Map && media['mime_type'] is String
        ? media['mime_type'] as String
        : null;
    final source = Uri.tryParse(track.path);
    final server = track.path.startsWith('/')
        ? await CastMediaServer.start(
            File(track.path),
            _address,
            mimeType: mimeType,
          )
        : track.telegramFileId != null && source != null
        ? await CastMediaServer.startStream(
            source,
            track.name,
            _address,
            mimeType: mimeType,
          )
        : throw StateError('This track is not available for casting.');
    try {
      final uri = server.uri.toString();
      final reportedDuration = media is Map ? media['duration'] : null;
      final trackDuration = duration > Duration.zero
          ? duration
          : reportedDuration is int && reportedDuration > 0
          ? Duration(seconds: reportedDuration)
          : Duration.zero;
      var metadata = MusicTrack(
        id: 'current',
        uri: uri,
        title: track.displayTitle,
        artist: track.artist,
        album: track.album ?? '',
        duration: trackDuration,
        artUri: null,
        protocolInfo:
            'http-get:*:${server.contentType.mimeType}:DLNA.ORG_OP=01;DLNA.ORG_CI=0',
      ).toXml();
      if (trackDuration == Duration.zero) {
        metadata = metadata.replaceFirst(' duration="00:00:00"', '');
      }
      await setCastTransportUri(
        setUri: () => _transport
            .setAVTransportURI(uri, metadata: metadata)
            .timeout(const Duration(seconds: 10)),
        stop: () => _transport.stop().timeout(const Duration(seconds: 5)),
      );
      if (_closed) throw StateError('Casting has stopped.');
      final previous = _server;
      _server = server;
      await previous?.close();
    } catch (_) {
      await server.close();
      rethrow;
    }
  }

  @override
  Future<void> loadTrack(LocalTrack track) => _setTrack(track, Duration.zero);

  static Duration? _parseTime(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d+):(\d{2}):(\d{2})(?:\.(\d{1,3}))?$')
        .firstMatch(value);
    if (match == null) return null;
    final minutes = int.parse(match[2]!);
    final seconds = int.parse(match[3]!);
    if (minutes >= 60 || seconds >= 60) return null;
    return Duration(
      hours: int.parse(match[1]!),
      minutes: minutes,
      seconds: seconds,
      milliseconds: int.parse((match[4] ?? '').padRight(3, '0')),
    );
  }

  @override
  Future<({Duration? position, Duration? duration})> readTiming() async {
    final info = await _transport.getPositionInfo().timeout(
      const Duration(seconds: 3),
    );
    return (
      position: _parseTime(info.relTime),
      duration: _parseTime(info.trackDuration),
    );
  }

  @override
  Future<String?> readPlaybackState() async =>
      (await _transport.getTransportInfo().timeout(const Duration(seconds: 3)))
          .currentTransportState
          ?.value;

  @override
  Future<double?> readVolume() async {
    final control = _rendering;
    if (control == null) return null;
    final value = await control.getVolume().timeout(const Duration(seconds: 3));
    return value < 0 ? null : (value / 100).clamp(0.0, 1.0);
  }

  @override
  Future<void> setVolume(double value) async {
    final control = _rendering;
    if (control == null) {
      throw UnsupportedError('Receiver volume is unavailable.');
    }
    await control
        .setVolume(volume: (value.clamp(0.0, 1.0) * 100).round())
        .timeout(const Duration(seconds: 3));
  }

  @override
  Future<void> play() => _transport.play().timeout(const Duration(seconds: 10));

  @override
  Future<void> pause() =>
      _transport.pause().timeout(const Duration(seconds: 10));

  @override
  Future<void> seek(Duration position) {
    final seconds = position.inSeconds;
    final target =
        '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return _transport
        .seek(SeekMode.relTime, target)
        .timeout(const Duration(seconds: 10));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _transport.stop().timeout(const Duration(seconds: 5));
    } finally {
      await _server?.close();
    }
  }
}
