import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';

import 'telegram_account_profile.dart';
import 'telegram_client.dart';
import 'telegram_music_library.dart';

class TelegramAccountCard extends StatelessWidget {
  const TelegramAccountCard({
    super.key,
    required this.account,
    required this.connected,
    this.request,
    this.onPhotoResolved,
  });
  final Future<Map<String, dynamic>> account;
  final bool connected;
  final TelegramRequest? request;
  final Future<void> Function(Map<String, dynamic>, String)? onPhotoResolved;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: FutureBuilder<Map<String, dynamic>>(
        future: account,
        builder: (context, snapshot) {
          final user = snapshot.data;
          TelegramAccountProfile? profile;
          if (user != null) {
            try {
              profile = TelegramAccountProfile.fromUser(user);
            } on FormatException {
              // Older or incomplete account data still has a readable name.
            }
          }
          final name =
              profile?.displayName ??
              [user?['first_name'], user?['last_name']]
                  .whereType<String>()
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .join(' ');
          final username = profile?.username;
          return Row(
            children: [
              TelegramProfileAvatar(
                user: user,
                request: request ?? TelegramClient.shared.request,
                onPhotoResolved: onPhotoResolved,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Telegram account' : name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (username != null && username.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      connected
                          ? 'Signed in · Connected'
                          : 'Signed in · Connecting',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (snapshot.hasError)
                      Text(
                        'Account details unavailable',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class TelegramProfileAvatar extends StatefulWidget {
  const TelegramProfileAvatar({
    super.key,
    required this.user,
    required this.request,
    this.onPhotoResolved,
  });
  final Map<String, dynamic>? user;
  final TelegramRequest request;
  final Future<void> Function(Map<String, dynamic>, String)? onPhotoResolved;

  @override
  State<TelegramProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<TelegramProfileAvatar> {
  late Future<String?> _photo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final user = widget.user;
    final onResolved = widget.onPhotoResolved;
    _photo = user == null
        ? Future.value(null)
        : resolveTelegramProfilePhoto(user, widget.request).then((path) {
            if (path != null && onResolved != null) {
              unawaited(onResolved(user, path).catchError((_) {}));
            }
            return path;
          });
  }

  @override
  void didUpdateWidget(covariant TelegramProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.user, widget.user) ||
        oldWidget.request != widget.request) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _photo,
    builder: (context, snapshot) => CircleAvatar(
      radius: 24,
      child: snapshot.data == null
          ? const Icon(Icons.person_outline)
          : ClipOval(
              child: Image.file(
                File(snapshot.data!),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.person_outline),
              ),
            ),
    ),
  );
}

class TelegramCachedProfileAvatar extends StatelessWidget {
  const TelegramCachedProfileAvatar({super.key, this.path});
  final String? path;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 24,
    child: path == null
        ? const Icon(Icons.person_outline)
        : ClipOval(
            child: Image.file(
              File(path!),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(Icons.person_outline),
            ),
          ),
  );
}
