import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'loading_skeleton.dart';
import 'telegram_playlists_screen.dart';

typedef TelegramSheetStatus = ({String state, String? error});

class TelegramLibrarySheet extends StatelessWidget {
  const TelegramLibrarySheet({
    super.key,
    required this.status,
    required this.onPlay,
    required this.onDownload,
    required this.onDownloadPlaylist,
    required this.onOpenLocal,
    required this.onOpenTelegramSettings,
    this.category = 'Playlists',
    this.hideHeader = false,
    this.onBack,
  });

  final ValueListenable<TelegramSheetStatus> status;
  final Future<void> Function(List<Map<String, dynamic>>, int, String) onPlay;
  final Future<void> Function(Map<String, dynamic>, String) onDownload;
  final void Function(List<Map<String, dynamic>>, String) onDownloadPlaylist;
  final VoidCallback onOpenLocal;
  final VoidCallback onOpenTelegramSettings;
  final String category;
  final bool hideHeader;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TelegramSheetStatus>(
        valueListenable: status,
        builder: (context, current, _) {
          if (current.state == 'ready') {
            return TelegramPlaylistsScreen(
              key: ValueKey(category),
              onPlay: onPlay,
              onDownload: onDownload,
              onDownloadPlaylist: onDownloadPlaylist,
              onOpenLocal: onOpenLocal,
              sheetMode: true,
              category: category,
              hideHeader: hideHeader,
              onCategoryBack: onBack,
            );
          }
          final waiting =
              current.error == null &&
              (current.state == 'initializing' ||
                  current.state == 'connecting');
          return Column(
            children: [
              if (!hideHeader)
                ListTile(
                  title: const Text('Telegram'),
                  trailing: TextButton.icon(
                    onPressed: onOpenLocal,
                    icon: const Icon(Icons.library_music_outlined),
                    label: const Text('Local'),
                  ),
                ),
              Expanded(
                child: waiting
                    ? const LibraryLoadingSkeleton()
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                current.error ??
                                    'Sign in to Telegram to see your music.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: onOpenTelegramSettings,
                                child: const Text('Telegram settings'),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      );
}
