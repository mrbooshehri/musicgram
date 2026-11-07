import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'telegram_artwork.dart';
import 'telegram_client.dart';
import 'loading_skeleton.dart';

class PlaylistCover extends StatelessWidget {
  const PlaylistCover({super.key, required this.playlist, this.size = 48});
  final Map<String, dynamic> playlist;
  final double size;
  static final Map<String, Future<Uint8List?>> _artwork = {};
  static Future<Uint8List?> _load(String path) {
    final existing = _artwork.remove(path);
    if (existing != null) {
      _artwork[path] = existing;
      return existing;
    }
    final future = const MethodChannel('musicgram/library')
        .invokeMethod<Uint8List>('artwork', {'path': path})
        .catchError((_) => null);
    _artwork[path] = future;
    if (_artwork.length > 30) _artwork.remove(_artwork.keys.first);
    return future;
  }

  @override
  Widget build(BuildContext context) {
    final custom = playlist['cover'];
    if (custom is String && custom.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(custom),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(),
        ),
      );
    }
    final tracks = playlist['tracks'];
    if (tracks is! List || tracks.isEmpty || tracks.first is! Map) {
      return _fallback();
    }
    final raw = tracks.first as Map;
    final first = raw is Map<String, dynamic>
        ? raw
        : Map<String, dynamic>.from(raw);
    if (playlist['type'] == 'telegram') {
      return SizedBox(
        width: size,
        height: size,
        child: TelegramArtwork(
          message: first,
          request: TelegramClient.shared.request,
        ),
      );
    }
    final path = first['path'];
    if (path is! String || !Platform.isAndroid) return _fallback();
    return FutureBuilder<Uint8List?>(
      future: _load(path),
      builder: (context, snapshot) =>
          snapshot.connectionState != ConnectionState.done
          ? LoadingSkeleton(width: size, height: size)
          : snapshot.data == null
          ? _fallback()
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                snapshot.data!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(),
              ),
            ),
    );
  }

  Widget _fallback() =>
      SizedBox(width: size, height: size, child: const Icon(Icons.queue_music));
}
