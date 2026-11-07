import 'package:flutter/material.dart';

import 'app_snack_bar.dart';
import 'music_storage.dart';
import 'telegram_audio_cache.dart';
import 'telegram_music_library.dart';

class TelegramAudioCacheScreen extends StatefulWidget {
  const TelegramAudioCacheScreen({
    super.key,
    required this.request,
    this.isBusy,
    this.isCurrentAccount,
  });

  final TelegramRequest request;
  final bool Function()? isBusy;
  final bool Function()? isCurrentAccount;

  @override
  State<TelegramAudioCacheScreen> createState() =>
      _TelegramAudioCacheScreenState();
}

class _TelegramAudioCacheScreenState extends State<TelegramAudioCacheScreen> {
  late final cache = TelegramAudioCache(widget.request);
  late Future<List<TelegramChatCacheUsage>> usage = cache.byChat();
  final titles = <int, Future<String>>{};
  bool clearing = false;

  Future<String> title(int id) async {
    try {
      final chat = await widget.request({'@type': 'getChat', 'chat_id': id});
      final name = chat['title'];
      if (name is String && name.trim().isNotEmpty) return name;
    } catch (_) {
      // The chat may no longer be accessible; its cached bytes remain clearable.
    }
    return 'Unavailable chat';
  }

  bool get accountChanged =>
      widget.isCurrentAccount != null && !widget.isCurrentAccount!();

  Future<void> clear(TelegramChatCacheUsage item, String name) async {
    if (accountChanged) {
      notice(
        'Telegram account changed. Reopen this page.',
        AppNoticeKind.warning,
      );
      return;
    }
    if (widget.isBusy?.call() ?? false) {
      notice(
        'Switch to local music and wait for Telegram downloads to finish first.',
        AppNoticeKind.warning,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear chat cache?'),
        content: Text(
          'Remove temporary audio and document files for $name? Saved downloads and playlist indexes will remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear cache'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (accountChanged || (widget.isBusy?.call() ?? false)) {
      notice(
        'Account or playback changed. Reopen this page and try again.',
        AppNoticeKind.warning,
      );
      return;
    }
    setState(() => clearing = true);
    try {
      final bytes = await cache.clearChat(item.chatId);
      if (!mounted) return;
      setState(() => usage = cache.byChat());
      notice(
        'Cleared ${formatStorageSize(bytes)} of cache.',
        AppNoticeKind.success,
      );
    } catch (_) {
      if (mounted) {
        notice('Could not clear this chat’s cache.', AppNoticeKind.error);
      }
    } finally {
      if (mounted) setState(() => clearing = false);
    }
  }

  void notice(String message, AppNoticeKind kind) {
    ScaffoldMessenger.of(context)
        .showSnackBar(AppSnackBar(kind: kind, content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Telegram audio cache')),
    body: FutureBuilder<List<TelegramChatCacheUsage>>(
      future: usage,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load cache usage.'),
                TextButton(
                  onPressed: () => setState(() => usage = cache.byChat()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return const Center(
            child: Text('No cached Telegram audio or documents.'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  'Temporary audio and documents, sorted by storage used. Saved downloads are kept.',
                ),
              );
            }
            final item = items[index - 1];
            if (item.chatId == 0) {
              return Card(
                child: ListTile(
                  title: const Text('Other cached files'),
                  subtitle: const Text('Not attributed to a single chat'),
                  trailing: Text(formatStorageSize(item.bytes)),
                ),
              );
            }
            return FutureBuilder<String>(
              future: titles.putIfAbsent(item.chatId, () => title(item.chatId)),
              builder: (context, titleSnapshot) {
                final name = titleSnapshot.data ?? 'Loading chat…';
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(formatStorageSize(item.bytes)),
                    trailing: TextButton(
                      onPressed: clearing || !titleSnapshot.hasData
                          ? null
                          : () => clear(item, name),
                      child: const Text('Clear'),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    ),
  );
}
