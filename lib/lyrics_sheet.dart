import 'dart:async';

import 'package:flutter/material.dart';

import 'lyrics.dart';
import 'playback_controller.dart';
import 'app_snack_bar.dart';
import 'error_toast_notice.dart';
import 'telegram_client.dart';

class LyricsSheet extends StatefulWidget {
  const LyricsSheet({
    super.key,
    required this.player,
    this.service,
    this.cache,
  });
  final PlaybackController player;
  final LyricsService? service;
  final LyricsCache? cache;

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  late final LyricsService _service = widget.service ?? LyricsService();
  late final LyricsCache _cache = widget.cache ?? LyricsCache();
  final _query = TextEditingController();
  String? _trackKey;
  LyricsRecord? _selected;
  List<LyricsRecord> _results = [];
  List<LyricLine> _lines = [];
  List<GlobalKey> _lineKeys = [];
  bool _busy = true;
  bool _manual = false;
  bool _showResults = false;
  String? _error;
  int _generation = 0;
  int _lastActive = -2;

  String? _key(LocalTrack? track) {
    if (track == null) return null;
    final message = track.telegramMessage;
    if (message?['chat_id'] != null && message?['id'] != null) {
      final session = TelegramClient.shared.verifiedSessionId;
      final prefix = session == null || session == 'legacy'
          ? 'telegram'
          : 'telegram:$session';
      return '$prefix:${message!['chat_id']}:${message['id']}';
    }
    return track.downloadKey ?? track.path;
  }

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_playerChanged);
    _playerChanged();
  }

  void _playerChanged() {
    final key = _key(widget.player.currentTrack);
    if (key != _trackKey) {
      _trackKey = key;
      unawaited(_loadTrack(key, widget.player.currentTrack));
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadTrack(String? key, LocalTrack? track) async {
    final generation = ++_generation;
    setState(() {
      _selected = null;
      _lines = [];
      _results = [];
      _error = null;
      _manual = false;
      _showResults = false;
      _busy = key != null;
      _lastActive = -2;
    });
    if (key == null || track == null) return;
    LyricsRecord? cached;
    try {
      cached = await _cache.load(key);
    } catch (_) {
      // Searching still works if the local cache is unavailable.
    }
    if (!mounted || generation != _generation) return;
    if (cached != null) {
      setState(() {
        _selectRecord(cached!);
        _busy = false;
      });
      return;
    }
    await _search(
      title: track.displayTitle,
      artist: track.displayArtist,
      generation: generation,
    );
  }

  Future<void> _search({
    String? query,
    String? title,
    String? artist,
    int? generation,
  }) async {
    final request = generation ?? ++_generation;
    setState(() {
      _showResults = true;
      _busy = true;
      _error = null;
    });
    try {
      final results = await _service.search(
        query: query,
        title: title,
        artist: artist,
      );
      if (!mounted || request != _generation) return;
      setState(() {
        _results = results;
        _busy = false;
      });
    } catch (_) {
      if (!mounted || request != _generation) return;
      setState(() {
        _busy = false;
        _results = [];
        _error =
            'Could not search LRCLIB. Check your connection and try again.';
      });
    }
  }

  void _selectRecord(LyricsRecord record) {
    _selected = record;
    _lines = parseSyncedLyrics(record.syncedLyrics ?? '');
    _lineKeys = List.generate(_lines.length, (_) => GlobalKey());
    _lastActive = -2;
    _showResults = false;
  }

  Future<void> _choose(LyricsRecord record) async {
    final key = _trackKey;
    if (key == null) return;
    ++_generation;
    setState(() {
      _selectRecord(record);
      _manual = false;
    });
    try {
      await _cache.save(key, record);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: const Text('Could not save lyrics for offline use.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.player.removeListener(_playerChanged);
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = activeLyricIndex(_lines, widget.player.position);
    if (!_showResults && active >= 0 && active != _lastActive) {
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || active >= _lineKeys.length) return;
        final target = _lineKeys[active].currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 350),
            alignment: .35,
          );
        }
      });
    }
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Lyrics',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _manual = !_manual;
                }),
                icon: const Icon(Icons.search),
                label: const Text('Search manual'),
              ),
            ],
          ),
        ),
        if (_manual)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Search title, artist or album',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    if (_query.text.trim().isNotEmpty) {
                      _search(query: _query.text);
                    }
                  },
                ),
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) _search(query: value);
              },
            ),
          ),
        if (!_showResults && _selected != null)
          ListTile(
            dense: true,
            title: Text(
              '${_selected!.trackName} · ${_selected!.artistName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: TextButton(
              onPressed: () => _search(
                title: widget.player.currentTrack?.displayTitle,
                artist: widget.player.currentTrack?.displayArtist,
              ),
              child: const Text('Change'),
            ),
          ),
        Expanded(
          child: _busy
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? ErrorToastNotice(message: _error!)
              : _showResults
              ? _results.isEmpty
                    ? const Center(
                        child: Text('No lyrics found. Try a manual search.'),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          return ListTile(
                            leading: const Icon(Icons.lyrics_outlined),
                            title: Text(result.trackName),
                            subtitle: Text(
                              '${result.artistName}${result.albumName.isEmpty ? '' : ' · ${result.albumName}'}',
                            ),
                            trailing: Text(
                              result.instrumental
                                  ? 'Instrumental'
                                  : (result.syncedLyrics?.isNotEmpty ?? false)
                                  ? 'Synced'
                                  : 'Plain',
                            ),
                            onTap: () => _choose(result),
                          );
                        },
                      )
              : _selected == null
              ? const Center(child: Text('Select a song to see lyrics.'))
              : _selected!.instrumental
              ? const Center(child: Text('Instrumental track'))
              : _lines.isNotEmpty
              ? SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < _lines.length; i++)
                        Padding(
                          key: _lineKeys[i],
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            _lines[i].text.isEmpty ? '♪' : _lines[i].text,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: i == active
                                      ? colors.primary
                                      : colors.onSurfaceVariant,
                                  fontWeight: i == active
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                          ),
                        ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _selected!.plainLyrics?.trim().isNotEmpty == true
                        ? _selected!.plainLyrics!
                        : 'No lyrics available for this result.',
                  ),
                ),
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Lyrics provided by LRCLIB'),
        ),
      ],
    );
  }
}
