import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_snack_bar.dart';
import 'notification_settings.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool saving = false;

  Future<void> _save(Future<void> Function() action) async {
    setState(() => saving = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: const Text('Could not save notification settings.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _openSystemSettings() async {
    try {
      await const MethodChannel('musicgram/library')
          .invokeMethod<void>('openNotificationSettings');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: const Text(
              'Could not open Android notification settings.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        Text('Media controls', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: NotificationSettings.showArtwork,
                builder: (context, enabled, _) => SwitchListTile(
                  title: const Text('Show track artwork'),
                  subtitle: const Text(
                    'Also applies to lock screen and Android Auto.',
                  ),
                  value: enabled,
                  onChanged: saving
                      ? null
                      : (value) =>
                            _save(() => NotificationSettings.save(value)),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: NotificationSettings.showCompactSkip,
                builder: (context, enabled, _) => SwitchListTile(
                  title: const Text('Previous and next buttons'),
                  subtitle: const Text(
                    'In compact controls when supported by Android.',
                  ),
                  value: enabled,
                  onChanged: saving
                      ? null
                      : (value) => _save(
                          () => NotificationSettings.saveCompactSkip(value),
                        ),
                ),
              ),
            ],
          ),
        ),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 24),
          Text('Android', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              title: const Text('Notification settings'),
              subtitle: const Text(
                'Manage permissions and lock-screen visibility',
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: _openSystemSettings,
            ),
          ),
        ],
      ],
    ),
  );
}
