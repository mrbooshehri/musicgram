import 'package:flutter/material.dart';

import 'app_snack_bar.dart';
import 'error_toast_notice.dart';

import 'download_settings.dart';
import 'telegram_cache_storage.dart';
import 'telegram_audio_cache.dart';
import 'telegram_audio_cache_screen.dart';
import 'telegram_client.dart';
import 'music_storage.dart';
import 'music_storage_screen.dart';

class DownloadSettingsScreen extends StatefulWidget {
  const DownloadSettingsScreen({
    super.key,
    this.ensureTelegramSession,
    this.telegramCacheBusy,
  });
  final Future<bool> Function()? ensureTelegramSession;
  final bool Function()? telegramCacheBusy;
  @override
  State<DownloadSettingsScreen> createState() => _DownloadSettingsScreenState();
}

class _DownloadSettingsScreenState extends State<DownloadSettingsScreen> {
  final settings = DownloadSettings.shared;
  late final TextEditingController folder;
  late int concurrency;
  bool saving = false;
  bool clearing = false;
  final cache = TelegramCacheStorage();
  late Future<int> cacheSize;
  late Future<int> audioCacheSize;
  bool clearingAudio = false;

  Future<int> loadAudioCacheSize() async {
    if (widget.ensureTelegramSession != null &&
        !await widget.ensureTelegramSession!()) {
      throw StateError('Telegram session unavailable');
    }
    if (!TelegramClient.shared.isRunning ||
        !TelegramClient.shared.isAccountVerified) {
      throw StateError('Telegram session unavailable');
    }
    return TelegramAudioCache(TelegramClient.shared.request).size();
  }

  Future<void> clearAudioCache() async {
    if (widget.telegramCacheBusy?.call() ?? false) {
      ScaffoldMessenger.of(context).showSnackBar(
        AppSnackBar(
          kind: AppNoticeKind.warning,
          content: const Text(
            'Switch to local music and wait for Telegram downloads to finish first.',
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Telegram audio cache?'),
        content: const Text(
          'Temporary audio and document files for this Telegram account will be removed. Saved downloads and playlist indexes will remain. Songs may need to be downloaded again when streamed.',
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
    if (widget.telegramCacheBusy?.call() ?? false) {
      ScaffoldMessenger.of(context).showSnackBar(
        AppSnackBar(
          kind: AppNoticeKind.warning,
          content: const Text(
            'Switch to local music and wait for Telegram downloads to finish first.',
          ),
        ),
      );
      return;
    }
    setState(() => clearingAudio = true);
    try {
      final bytes = await TelegramAudioCache(TelegramClient.shared.request)
          .clear();
      if (!mounted) return;
      setState(() => audioCacheSize = loadAudioCacheSize());
      ScaffoldMessenger.of(context).showSnackBar(
        AppSnackBar(
          kind: AppNoticeKind.success,
          content: Text(
            'Cleared ${formatStorageSize(bytes)} of Telegram cache.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: const Text('Could not clear Telegram audio cache.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => clearingAudio = false);
    }
  }

  late Future<MusicStorageSummary> storage;

  String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear playlist cache?'),
        content: const Text(
          'Telegram playlist indexes will be removed and need to be synced again. Downloaded music and your playlists will remain.',
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
    setState(() => clearing = true);
    try {
      await cache.clear();
      if (mounted) setState(() => cacheSize = cache.size());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: Text('Could not clear playlist cache.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => clearing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    folder = TextEditingController(text: settings.folder);
    concurrency = settings.concurrency;
    cacheSize = cache.size();
    audioCacheSize = loadAudioCacheSize();
    storage = MusicStorageSummary.load();
  }

  @override
  void dispose() {
    folder.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!DownloadSettings.validFolder(folder.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        AppSnackBar(
          kind: AppNoticeKind.warning,
          content: Text('Enter a valid folder name without slashes.'),
        ),
      );
      return;
    }
    setState(() => saving = true);
    try {
      await settings.save(folder.text, concurrency);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: Text('Could not save download settings.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Downloads & cache')),

    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        Text('Storage', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FutureBuilder<MusicStorageSummary>(
              future: storage,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (!snapshot.hasData) {
                  return Column(
                    children: [
                      const ErrorToastNotice(
                        message: 'Storage analysis unavailable. Allow music access and try again.',
                      ),
                      TextButton(
                        onPressed: () => setState(
                          () => storage = MusicStorageSummary.load(),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  );
                }
                final data = snapshot.data!;
                Widget bar(
                  String label,
                  int bytes,
                  List<FolderUsage> folders,
                  Color color,
                ) {
                  final ratio = data.capacity <= 0
                      ? 0.0
                      : (bytes / data.capacity).clamp(0.0, 1.0);
                  final theme = Theme.of(context);
                  final scheme = theme.colorScheme;
                  final percentage = data.capacity <= 0
                      ? 'Storage capacity unavailable'
                      : bytes > 0 && ratio < .001
                      ? '<0.1% of device storage'
                      : '${(ratio * 100).toStringAsFixed(1)}% of device storage';
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            MusicStorageScreen(title: label, folders: folders),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              Text(
                                formatStorageSize(bytes),
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 14,
                              color: color,
                              backgroundColor: scheme.onSurface.withValues(
                                alpha: .22,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            percentage,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    Text(
                      '${formatStorageSize(data.usedBytes)} used of ${formatStorageSize(data.capacity)}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Primary shared storage · tap a bar for folders',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        bar(
                          'Local music',
                          data.localBytes,
                          data.local,
                          Theme.of(context).colorScheme.primary,
                        ),
                        bar(
                          'Telegram downloads',
                          data.telegramBytes,
                          data.telegram,
                          Theme.of(context).colorScheme.tertiary,
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => storage = MusicStorageSummary.load()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Downloads', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: folder,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Folder in Music',
                    helperText: 'Playlists are saved as subfolders.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: concurrency,
                  decoration: const InputDecoration(
                    labelText: 'Concurrent downloads',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var i = 1; i <= 3; i++)
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: saving
                      ? null
                      : (value) => setState(() => concurrency = value ?? 1),
                ),
                const SizedBox(height: 12),
                const Text('Downloads run while the app is open.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Cache', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: FutureBuilder<int>(
            future: cacheSize,
            builder: (context, snapshot) => ListTile(
              title: const Text('Telegram playlist cache'),
              subtitle: snapshot.hasError
                  ? const ErrorToastNotice(
                      message: 'Could not calculate Telegram cache size.',
                    )
                  : Text(
                      snapshot.hasData
                          ? formatStorageSize(snapshot.data!)
                          : 'Calculating…',
                    ),
              trailing: TextButton(
                onPressed: clearing || !snapshot.hasData || snapshot.data == 0
                    ? null
                    : clearCache,
                child: const Text('Clear'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: FutureBuilder<int>(
            future: audioCacheSize,
            builder: (context, snapshot) => ListTile(
              title: const Text('Telegram audio cache'),
              onTap: !snapshot.hasData || clearingAudio
                  ? null
                  : () async {
                      final session = TelegramClient.shared.verifiedSessionId;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TelegramAudioCacheScreen(
                            request: TelegramClient.shared.request,
                            isBusy: widget.telegramCacheBusy,
                            isCurrentAccount: () =>
                                TelegramClient.shared.isAccountVerified &&
                                TelegramClient.shared.verifiedSessionId ==
                                    session,
                          ),
                        ),
                      );
                      if (mounted) {
                        setState(() => audioCacheSize = loadAudioCacheSize());
                      }
                    },
              subtitle: Text(
                snapshot.hasError
                    ? 'Unavailable — connect to Telegram and retry'
                    : snapshot.hasData
                    ? '${formatStorageSize(snapshot.data!)} · Audio and documents'
                    : 'Calculating…',
              ),
              trailing: snapshot.hasError
                  ? IconButton(
                      tooltip: 'Retry',
                      onPressed: () =>
                          setState(() => audioCacheSize = loadAudioCacheSize()),
                      icon: const Icon(Icons.refresh),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed:
                              clearingAudio ||
                                  !snapshot.hasData ||
                                  snapshot.data == 0
                              ? null
                              : clearAudioCache,
                          child: Text(clearingAudio ? 'Clearing…' : 'Clear'),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Downloaded songs are stored separately.'),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: saving ? null : save,
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
