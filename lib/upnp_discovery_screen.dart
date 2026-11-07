import 'package:flutter/material.dart';

import 'playback_controller.dart';
import 'upnp_cast_session.dart';
import 'upnp_discovery.dart';
import 'app_snack_bar.dart';
import 'error_toast_notice.dart';

class UpnpDiscoveryScreen extends StatefulWidget {
  const UpnpDiscoveryScreen({
    super.key,
    this.player,
    this.discover = discoverUpnpRenderers,
    this.prepare = UpnpCastSession.prepare,
  });
  final PlaybackController? player;
  final Future<List<UpnpRenderer>> Function() discover;
  final Future<RemotePlaybackSession> Function(
    UpnpRenderer,
    LocalTrack,
    Duration,
  )
  prepare;

  @override
  State<UpnpDiscoveryScreen> createState() => _UpnpDiscoveryScreenState();
}

class _UpnpDiscoveryScreenState extends State<UpnpDiscoveryScreen> {
  late Future<List<UpnpRenderer>?> _results;
  bool _busy = false;

  Future<List<UpnpRenderer>?> _scan() async {
    try {
      return await widget.discover();
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _results = _scan();
  }

  Future<void> _connect(UpnpRenderer device) async {
    final player = widget.player;
    final track = player?.currentTrack;
    if (player == null || track == null) {
      _message('Select a song before casting.');
      return;
    }
    setState(() => _busy = true);
    RemotePlaybackSession? session;
    try {
      session = await widget.prepare(device, track, player.duration);
      if (!mounted || player.currentTrack != track || player.isCasting) {
        await session.close();
        if (mounted) _message('The selected song changed. Please try again.');
        return;
      }
      await player.startCasting(session);
      session = null;
    } catch (error) {
      if (mounted) {
        _message('Could not start casting: $error', kind: AppNoticeKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop({bool playLocally = false}) async {
    setState(() => _busy = true);
    try {
      await widget.player?.stopCasting();
      if (playLocally) await widget.player?.play();
    } catch (_) {
      if (mounted) {
        _message(
          'Could not contact the device. Casting stopped locally.',
          kind: AppNoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message, {AppNoticeKind kind = AppNoticeKind.info}) {
    ScaffoldMessenger.of(context)
        .showSnackBar(AppSnackBar(kind: kind, content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cast to device'),
        actions: [
          if (player?.isCasting != true)
            IconButton(
              tooltip: 'Refresh devices',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _results = _scan();
                    }),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: player ?? Listenable.merge([]),
        builder: (context, _) {
          if (player?.isCasting == true) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.cast_connected),
                    title: Text(
                      'Casting to ${player!.castDeviceName ?? 'device'}',
                    ),
                    subtitle: Text(
                      player.currentTrack?.displayTitle ?? 'Current track',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Playback',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (player.isPlaying) {
                                    await player.pause();
                                  } else {
                                    await player.play();
                                  }
                                },
                          icon: Icon(
                            player.isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                          label: Text(player.isPlaying ? 'Pause' : 'Play'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _stop(),
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop casting'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _stop(playLocally: true),
                          icon: const Icon(Icons.phone_android),
                          label: const Text('Play on this device'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!player.canControlCastVolume)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'This receiver does not provide volume control.',
                    ),
                  ),
              ],
            );
          }
          return Column(
            children: [
              const Card(
                child: ListTile(
                  title: Text('Choose a UPnP/DLNA device'),
                  subtitle: Text(
                    'Select a song and connect both devices to the same network.',
                  ),
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
              Expanded(
                child: FutureBuilder<List<UpnpRenderer>?>(
                  future: _results,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Looking for devices…'),
                          ],
                        ),
                      );
                    }
                    final devices = snapshot.data ?? [];
                    if (devices.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (snapshot.data == null)
                                const ErrorToastNotice(
                                  message: 'Could not scan for devices.',
                                )
                              else
                                const Text('No compatible devices found.'),
                              const SizedBox(height: 8),
                              const Text(
                                'Connect to the same Wi-Fi; some networks block device discovery.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => setState(() {
                                  _results = _scan();
                                }),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.speaker_group_outlined),
                            title: Text(device.name),
                            subtitle: Text(
                              device.canPlay
                                  ? 'Media renderer'
                                  : 'Playback control unavailable',
                            ),
                            enabled: device.canPlay && !_busy,
                            onTap: () => _connect(device),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'UPnP/DLNA devices only; Chromecast uses a different protocol.',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
