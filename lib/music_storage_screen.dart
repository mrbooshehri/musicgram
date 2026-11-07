import 'package:flutter/material.dart';

import 'music_storage.dart';

class MusicStorageScreen extends StatelessWidget {
  const MusicStorageScreen({
    super.key,
    required this.title,
    required this.folders,
  });
  final String title;
  final List<FolderUsage> folders;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: folders.isEmpty
        ? const Center(child: Text('No music found on primary storage.'))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: folders.length,
            itemBuilder: (context, index) {
              final item = folders[index];
              return Card(
                child: ListTile(
                  title: Text(item.folder),
                  subtitle: Text(
                    '${item.count} ${item.count == 1 ? 'track' : 'tracks'}',
                  ),
                  trailing: Text(formatStorageSize(item.bytes)),
                ),
              );
            },
          ),
  );
}
