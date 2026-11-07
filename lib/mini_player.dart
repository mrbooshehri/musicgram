import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'playback_controller.dart';
import 'playlist_cover.dart';
import 'embedded_artwork.dart';


class MiniPlayerNavigatorObserver extends NavigatorObserver {
  final secondaryPage = ValueNotifier<bool>(false);
  final List<PageRoute<dynamic>> _pages = [];

  void _update() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) secondaryPage.value = _pages.length > 1;
    });
  }

  bool _disposed = false;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      _pages.add(route);
      _update();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      _pages.remove(route);
      _update();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      _pages.remove(route);
      _update();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute is PageRoute ? _pages.indexOf(oldRoute) : -1;
    if (index >= 0) {
      if (newRoute is PageRoute) {
        _pages[index] = newRoute;
      } else {
        _pages.removeAt(index);
      }
    } else if (newRoute is PageRoute) {
      _pages.add(newRoute);
    }
    _update();
  }

  void dispose() {
    _disposed = true;
    secondaryPage.dispose();
  }
}

class _MiniArtwork extends StatefulWidget {
  const _MiniArtwork({
    super.key,
    required this.track,
    required this.telegram,
    this.loader,
  });
  final LocalTrack track;
  final Map<String, dynamic>? telegram;
  final Future<Uint8List?> Function(String path)? loader;

  @override
  State<_MiniArtwork> createState() => _MiniArtworkState();
}

class _MiniArtworkState extends State<_MiniArtwork> {
  late Future<Uint8List?> artwork;
  @override
  void initState() {
    super.initState();
    artwork = (widget.loader ?? EmbeddedArtwork.load)(widget.track.path);
  }

  @override
  Widget build(BuildContext context) {
    Widget fallback() => PlaylistCover(
      size: 48,
      playlist: {
        'type': widget.telegram == null ? 'local' : 'telegram',
        'tracks': [
          widget.telegram ?? {'path': widget.track.path},
        ],
      },
    );
    return FutureBuilder<Uint8List?>(
      future: artwork,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) return fallback();
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback(),
          ),
        );
      },
    );
  }
}

class MiniPlayerShell extends StatefulWidget {
  const MiniPlayerShell({
    super.key,
    required this.child,
    required this.player,
    required this.secondaryPage,
    required this.onOpenPlayer,
    this.artworkLoader,
  });
  final Widget child;
  final ValueListenable<PlaybackController?> player;
  final ValueListenable<bool> secondaryPage;
  final VoidCallback onOpenPlayer;
  final Future<Uint8List?> Function(String path)? artworkLoader;
  @override
  State<MiniPlayerShell> createState() => _MiniPlayerShellState();
}

class _MiniPlayerShellState extends State<MiniPlayerShell> {
  bool dismissed = false;
  String? dismissedTrack;
  bool wasSecondary = false;
  bool playedOnSecondaryPage = false;
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<PlaybackController?>(
    valueListenable: widget.player,
    builder: (context, player, _) => ValueListenableBuilder<bool>(
      valueListenable: widget.secondaryPage,
      builder: (context, secondary, _) {
        if (secondary && !wasSecondary) dismissed = false;
        if (!secondary) playedOnSecondaryPage = false;
        wasSecondary = secondary;
        if (player == null) return widget.child;
        return ListenableBuilder(
          listenable: player,
          builder: (context, _) {
            final track = player.currentTrack;
            if (secondary && player.isPlaying) playedOnSecondaryPage = true;
            if (dismissed && dismissedTrack != track?.path) dismissed = false;
            final visible =
                secondary &&
                track != null &&
                playedOnSecondaryPage &&
                !dismissed &&
                MediaQuery.viewInsetsOf(context).bottom == 0;
            if (!visible) return widget.child;
            final telegram = track.telegramMessage;
            return Column(
              children: [
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeBottom: true,
                    child: widget.child,
                  ),
                ),
                TooltipVisibility(
                  visible: false,
                  child: Material(
                    key: const Key('miniPlayer'),
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    elevation: 4,
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        height: 64,
                        child: Row(
                          children: [
                            const SizedBox(width: 8),
                            _MiniArtwork(
                              key: ValueKey(track.path),
                              track: track,
                              telegram: telegram,
                              loader: widget.artworkLoader,
                            ),
                            Expanded(
                              child: InkWell(
                                onTap: widget.onOpenPlayer,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        track.displayTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      Text(
                                        track.displayArtist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Semantics(
                              label: player.showPauseControl ? 'Pause' : 'Play',
                              child: IconButton(
                                key: const Key('miniPlayPause'),
                                tooltip: player.showPauseControl
                                    ? 'Pause'
                                    : 'Play',
                                onPressed: player.togglePlayback,
                                icon: Icon(
                                  player.showPauseControl
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                              ),
                            ),
                            Semantics(
                              label: 'Next track',
                              child: IconButton(
                                key: const Key('miniNext'),
                                tooltip: 'Next',
                                onPressed: player.queue.length > 1
                                    ? player.next
                                    : null,
                                icon: const Icon(Icons.skip_next),
                              ),
                            ),
                            Semantics(
                              label: 'Close mini player',
                              child: IconButton(
                                key: const Key('miniClose'),
                                tooltip: 'Close mini player',
                                onPressed: () => setState(() {
                                  dismissed = true;
                                  dismissedTrack = track.path;
                                }),
                                icon: const Icon(Icons.close),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}
