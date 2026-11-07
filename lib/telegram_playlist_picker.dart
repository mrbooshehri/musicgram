import 'package:flutter/material.dart';

import 'library_search.dart';
import 'loading_skeleton.dart';
import 'telegram_client.dart';
import 'telegram_library_cache.dart';
import 'telegram_music_library.dart';
import 'error_toast_notice.dart';

class TelegramPlaylistPicker extends StatefulWidget {
  const TelegramPlaylistPicker({
    super.key,
    required this.name,
    required this.initial,
    this.groups,
    this.request,
    this.ensureSession,
  });
  final String name;
  final List<Map<String, dynamic>> initial;
  final Stream<MusicGroups>? groups;
  final TelegramRequest? request;
  final Future<bool> Function()? ensureSession;

  @override
  State<TelegramPlaylistPicker> createState() => _TelegramPlaylistPickerState();
}

class _TelegramPlaylistPickerState extends State<TelegramPlaylistPicker> {
  final client = TelegramClient.shared;
  final searchController = TextEditingController();
  late final Stream<MusicGroups> results;
  late final Map<String, Map<String, dynamic>> selected;
  final Map<int, Future<String>> titles = {};
  int? chatId;
  String? chatName;
  String search = '';
  bool saving = false;
  bool? sessionReady;

  static String? key(Map item) => item['chat_id'] is int && item['id'] is int
      ? '${item['chat_id']}:${item['id']}'
      : null;

  @override
  void initState() {
    super.initState();
    selected = {
      for (final item in widget.initial)
        if (key(item) != null) key(item)!: item,
    };
    final request = widget.request ?? client.request;
    results =
        widget.groups ??
        TelegramLibraryCache(
          request: request,
          library: TelegramMusicLibrary(request: request),
        ).load(cacheOnly: true);
    if (widget.ensureSession == null) {
      sessionReady =
          widget.groups != null ||
          (client.isRunning && client.isAccountVerified);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        bool ready;
        try {
          ready = await widget.ensureSession!();
        } catch (_) {
          ready = false;
        }
        if (mounted) setState(() => sessionReady = ready);
      });
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<String> chatTitle(int id) => titles.putIfAbsent(id, () async {
    try {
      final chat = await (widget.request ?? client.request)({
        '@type': 'getChat',
        'chat_id': id,
      });
      return chat['title'] is String &&
              (chat['title'] as String).trim().isNotEmpty
          ? chat['title'] as String
          : 'Telegram chat';
    } catch (_) {
      return 'Telegram chat';
    }
  });

  void backToChats() => setState(() {
    chatId = null;
    chatName = null;
    search = '';
    searchController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
  });

  void save() {
    if (chatId == null) {
      Navigator.pop(context, selected.values.toList());
    } else {
      setState(() => saving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, selected.values.toList());
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: chatId == null || saving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && chatId != null && !saving) backToChats();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: chatId == null
            ? null
            : IconButton(
                tooltip: 'Back to chats',
                icon: const Icon(Icons.arrow_back),
                onPressed: backToChats,
              ),
        title: Text(chatName ?? widget.name),
        actions: [TextButton(onPressed: save, child: const Text('Save'))],
      ),
      body: sessionReady == false
          ? Center(
              child: Text(
                widget.ensureSession == null
                    ? 'Sign in to Telegram in Settings first.'
                    : 'Could not connect to Telegram. Check your connection or sign in in Settings.',
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: sessionReady == null
                      ? const LibraryLoadingSkeleton()
                      : StreamBuilder<MusicGroups>(
                          stream: results,
                          builder: (context, snapshot) {
                            final groups = snapshot.data ?? {};
                            if (groups.isEmpty &&
                                snapshot.connectionState !=
                                    ConnectionState.done) {
                              return const LibraryLoadingSkeleton();
                            }
                            if (groups.isEmpty && snapshot.hasError) {
                              return const ErrorToastNotice(
                                message: 'Could not load Telegram music.',
                              );
                            }
                            if (groups.isEmpty) {
                              return const Center(
                                child: Text(
                                  'No cached music. Sync Telegram playlists in Settings first.',
                                ),
                              );
                            }
                            if (chatId != null) {
                              return _tracks(groups[chatId] ?? []);
                            }
                            final entries = groups.entries.toList();
                            return ListView.builder(
                              itemCount: entries.length,
                              itemBuilder: (context, index) {
                                final entry = entries[index];
                                return FutureBuilder<String>(
                                  future: chatTitle(entry.key),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState !=
                                        ConnectionState.done) {
                                      return ListTile(
                                        leading: const Icon(Icons.queue_music),
                                        title: Align(
                                          alignment: Alignment.centerLeft,
                                          child: LoadingSkeleton(
                                            key: ValueKey(
                                              'chat-title-loading-${entry.key}',
                                            ),
                                            width: 160,
                                            height: 14,
                                          ),
                                        ),
                                        subtitle: Text(
                                          '${entry.value.length} songs',
                                        ),
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                        ),
                                      );
                                    }
                                    final name =
                                        snapshot.data ?? 'Loading chat…';
                                    if (search.isNotEmpty &&
                                        (snapshot.data == null ||
                                            !librarySearchMatches(
                                              name,
                                              search,
                                            ))) {
                                      return const SizedBox.shrink();
                                    }
                                    return ListTile(
                                      leading: const Icon(Icons.queue_music),
                                      title: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        '${entry.value.length} songs',
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: snapshot.data == null
                                          ? null
                                          : () => setState(() {
                                              chatId = entry.key;
                                              chatName = name;
                                              search = '';
                                              searchController.clear();
                                              FocusManager.instance.primaryFocus
                                                  ?.unfocus();
                                            }),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                ),
                LibrarySearch(
                  controller: searchController,
                  hint: chatId == null
                      ? 'Search chats'
                      : 'Search songs or artists',
                  onChanged: (value) => setState(() => search = value),
                ),
              ],
            ),
    ),
  );

  Widget _tracks(List<Map<String, dynamic>> tracks) {
    final filtered = tracks.where((item) {
      final content = item['content'];
      final media = content is Map
          ? content['audio'] ?? content['document']
          : null;
      final data = media is Map ? media : const {};
      return librarySearchMatches(
        '${data['title'] ?? ''} ${data['file_name'] ?? ''} ${data['performer'] ?? ''}',
        search,
      );
    }).toList();
    if (filtered.isEmpty) return const Center(child: Text('No songs found.'));
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final item = filtered[index];
        final itemKey = key(item);
        final content = item['content'];
        final media = content is Map
            ? content['audio'] ?? content['document']
            : null;
        final data = media is Map ? media : const {};
        final title = data['title'];
        final filename = data['file_name'];
        final artist = data['performer'];
        return CheckboxListTile(
          value: itemKey != null && selected.containsKey(itemKey),
          title: Text(
            title is String && title.trim().isNotEmpty
                ? title
                : filename is String && filename.isNotEmpty
                ? filename
                : 'Untitled track',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: artist is String && artist.isNotEmpty
              ? Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis)
              : null,
          onChanged: itemKey == null
              ? null
              : (value) => setState(() {
                  if (value == true) {
                    selected[itemKey] = item;
                  } else {
                    selected.remove(itemKey);
                  }
                }),
        );
      },
    );
  }
}
