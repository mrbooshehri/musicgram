import 'dart:io';

import 'package:flutter/material.dart';

import 'app_snack_bar.dart';

import 'package:flutter/services.dart';

class AboutDiagnosticsScreen extends StatefulWidget {
  const AboutDiagnosticsScreen({super.key, this.version});
  final Future<String> Function()? version;

  @override
  State<AboutDiagnosticsScreen> createState() => _AboutDiagnosticsScreenState();
}

class _AboutDiagnosticsScreenState extends State<AboutDiagnosticsScreen> {
  late final Future<String> version = (widget.version ?? _getVersion)();

  Future<String> _getVersion() async {
    if (!Platform.isAndroid) return 'Unavailable on this platform';
    try {
      return await const MethodChannel('musicgram/library')
              .invokeMethod<String>('appVersion') ??
          'Unavailable';
    } catch (_) {
      return 'Unavailable';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About')),
    body: FutureBuilder<String>(
      future: version,
      builder: (context, snapshot) {
        final value =
            snapshot.data ?? (snapshot.hasError ? 'Unavailable' : 'Loading…');

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          children: [
            Center(
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/musicgram-logo.png',
                      key: const Key('aboutAppLogo'),
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'MusicGram',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Version $value',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Card(
              child: ListTile(
                title: const Text('Copy app details'),
                subtitle: const Text('Copy the version for a bug report'),
                trailing: const Icon(Icons.copy_outlined),
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: 'MusicGram version: $value'),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      AppSnackBar(
                        kind: AppNoticeKind.success,
                        content: const Text('App details copied.'),
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'MusicGram',
                  applicationVersion: value,
                ),
                child: const Text('Open-source licenses'),
              ),
            ),
          ],
        );
      },
    ),
  );
}
