import 'dart:io';

import 'telegram_music_library.dart';

class TelegramAccountProfile {
  const TelegramAccountProfile({
    required this.id,
    required this.name,
    this.username,
    this.photoId,
    this.photoPath,
  });
  final int id;
  final String name;
  final String? username;
  final String? photoId;
  final String? photoPath;

  factory TelegramAccountProfile.fromUser(Map<String, dynamic> user) {
    final id = user['id'];
    if (id is! int || id <= 0) {
      throw const FormatException('Invalid Telegram account');
    }
    final name = [user['first_name'], user['last_name']]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
    final usernames = user['usernames'];
    final active = usernames is Map ? usernames['active_usernames'] : null;
    final values = active is List
        ? active
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
        : <String>[];
    final legacy = user['username'];
    final photo = user['profile_photo'];
    final small = photo is Map ? photo['small'] : null;
    final photoId = photo is Map
        ? photo['id'] ?? (small is Map ? small['id'] : null)
        : null;
    final username = values.isNotEmpty
        ? values.first
        : legacy is String && legacy.trim().isNotEmpty
        ? legacy.trim()
        : null;
    return TelegramAccountProfile(
      id: id,
      name: name,
      username: username?.replaceFirst(RegExp(r'^@+'), ''),
      photoId: photoId?.toString(),
    );
  }

  factory TelegramAccountProfile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final username = json['username'];
    final photoId = json['photoId'];
    if (id is! int ||
        id <= 0 ||
        name is! String ||
        (username != null && username is! String) ||
        (photoId != null && photoId is! String)) {
      throw const FormatException('Invalid Telegram profile');
    }
    return TelegramAccountProfile(
      id: id,
      name: name,
      username: username as String?,
      photoId: photoId as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (username != null) 'username': username,
    if (photoId != null) 'photoId': photoId,
  };
  TelegramAccountProfile withPhotoPath(String? path) => TelegramAccountProfile(
    id: id,
    name: name,
    username: username,
    photoId: photoId,
    photoPath: path,
  );
  String get displayName => name.isNotEmpty
      ? name
      : username != null && username!.isNotEmpty
      ? '@$username'
      : 'Telegram account';
}

Future<String?> resolveTelegramProfilePhoto(
  Map<String, dynamic> user,
  TelegramRequest request,
) async {
  final photo = user['profile_photo'];
  final file = photo is Map ? photo['small'] : null;
  if (file is! Map) return null;
  Future<String?> pathFrom(dynamic local) async {
    if (local is! Map ||
        local['is_downloading_completed'] != true ||
        local['path'] is! String) {
      return null;
    }
    final path = local['path'] as String;
    return path.isNotEmpty && await File(path).exists() ? path : null;
  }

  final cached = await pathFrom(file['local']);
  if (cached != null) return cached;
  final id = file['id'];
  if (id is! int || id <= 0) return null;
  try {
    final result = await request({
      '@type': 'downloadFile',
      'file_id': id,
      'priority': 1,
      'offset': 0,
      'limit': 0,
      'synchronous': true,
    });
    return await pathFrom(result['local']);
  } catch (_) {
    return null;
  }
}
