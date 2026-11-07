import 'package:flutter/material.dart';

import 'telegram_client.dart';
import 'telegram_music_library.dart';
import 'telegram_sync_selection.dart';
import 'app_snack_bar.dart';
import 'error_toast_notice.dart';

class TelegramSyncChatScreen extends StatefulWidget {
  const TelegramSyncChatScreen({super.key, this.request, this.selection});
  final TelegramRequest? request;
  final TelegramSyncSelection? selection;
  @override
  State<TelegramSyncChatScreen> createState() => _TelegramSyncChatScreenState();
}

class _SyncChat {
  const _SyncChat(this.id, this.title, this.category);
  final int id;
  final String title;
  final int category;
}

class _TelegramSyncChatScreenState extends State<TelegramSyncChatScreen> {
  late final TelegramRequest request =
      widget.request ?? TelegramClient.shared.request;
  late Future<List<_SyncChat>> chats = _load();
  final selected = <int>{};
  bool saving = false;
  late final TelegramSyncSelection selection =
      widget.selection ?? TelegramSyncSelection(request: request);

  Future<List<_SyncChat>> _load() async {
    final previouslySelected = await selection.load();
    selected
      ..clear()
      ..addAll(previouslySelected);
    final ids = <int>{};
    for (final list in [
      <String, Object?>{'@type': 'chatListMain'},
      <String, Object?>{'@type': 'chatListArchive'},
    ]) {
      while (true) {
        try {
          await request({
            '@type': 'loadChats',
            'chat_list': list,
            'limit': 100,
          });
        } on StateError catch (e) {
          if (e.message.toString().toLowerCase().contains('not found')) break;
          rethrow;
        }
      }
      final response = await request({
        '@type': 'getChats',
        'chat_list': list,
        'limit': 100000,
      });
      final raw = response['chat_ids'];
      if (raw is! List) throw const FormatException('Invalid chat list');
      ids.addAll(raw.whereType<int>());
    }
    final result = <_SyncChat>[];
    for (final id in ids) {
      final chat = await request({'@type': 'getChat', 'chat_id': id});
      final type = chat['type'];
      if (type is! Map) continue;
      var category = 3;
      if (type['@type'] == 'chatTypePrivate') {
        category = 0;
        final userId = type['user_id'];
        if (userId is int) {
          final user = await request({'@type': 'getUser', 'user_id': userId});
          final userType = user['type'];
          if (userType is Map && userType['@type'] == 'userTypeBot') {
            category = 2;
          }
        }
      } else if (type['@type'] == 'chatTypeSupergroup' &&
          type['is_channel'] == true) {
        category = 1;
      } else if (type['@type'] != 'chatTypeSupergroup' &&
          type['@type'] != 'chatTypeBasicGroup') {
        continue;
      }
      final title = chat['title'];
      result.add(
        _SyncChat(
          id,
          title is String && title.isNotEmpty ? title : 'Untitled chat',
          category,
        ),
      );
    }
    result.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return result;
  }

  Future<void> _saveSelection() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await selection.save(selected);
      if (mounted) Navigator.pop(context, Set<int>.of(selected));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: const Text('Could not save selected chats.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Choose chats to sync'),
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(icon: Icon(Icons.person_outline), text: 'Private'),
            Tab(icon: Icon(Icons.campaign_outlined), text: 'Channels'),
            Tab(icon: Icon(Icons.smart_toy_outlined), text: 'Bots'),
            Tab(icon: Icon(Icons.group_outlined), text: 'Groups'),
          ],
        ),
      ),
      body: FutureBuilder<List<_SyncChat>>(
        future: chats,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ErrorToastNotice(
                    message: 'Could not load Telegram chats.',
                  ),
                  TextButton(
                    onPressed: () => setState(() => chats = _load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: Text('${selected.length} selected')),
                    TextButton(
                      onPressed: () => setState(() {
                        selected.addAll(all.map((c) => c.id));
                      }),
                      child: const Text('Select all'),
                    ),
                    TextButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => setState(selected.clear),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: List.generate(4, (category) {
                    final items = all
                        .where((chat) => chat.category == category)
                        .toList();
                    if (items.isEmpty) {
                      return const Center(child: Text('No chats'));
                    }
                    return ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final chat = items[index];
                        return CheckboxListTile(
                          value: selected.contains(chat.id),
                          title: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              selected.add(chat.id);
                            } else {
                              selected.remove(chat.id);
                            }
                          }),
                        );
                      },
                    );
                  }),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: saving ? null : _saveSelection,
                      child: Text(
                        selected.isEmpty
                            ? 'Save selection'
                            : 'Sync selected chats',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
