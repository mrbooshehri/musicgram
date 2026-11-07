import 'dart:io';
import 'dart:math';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';

import 'telegram_account_profile.dart';

/// Maps a session slot to its private TDLib database directory.
///
/// The legacy slot deliberately keeps its original location. Callers must close
/// the active TDLib client before selecting another slot.
class TelegramSessionStore {
  TelegramSessionStore({this.directory});
  final Future<Directory> Function()? directory;
  static Future<void> _ownerWrites = Future.value();
  static Future<void> _profileWrites = Future.value();

  Future<Directory> _root() =>
      directory?.call() ?? getApplicationSupportDirectory();

  bool _valid(String id) =>
      id == 'legacy' || RegExp(r'^session_[a-zA-Z0-9_-]{1,64}$').hasMatch(id);

  /// Returns an unused slot without changing the active session.
  Future<String> newSessionId() async {
    final random = Random.secure();
    while (true) {
      final id =
          'session_${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
      final root = await _root();
      if (!await (await directoryFor(id)).exists() &&
          !await File('${root.path}/telegram_owner_$id.txt').exists()) {
        return id;
      }
    }
  }

  Future<String> activeId() async {
    try {
      final root = await _root();
      final id = (await File(
        '${root.path}/telegram_active_session.txt',
      ).readAsString()).trim();
      if (!_valid(id)) {
        throw const FormatException('Invalid active Telegram session');
      }
      return id;
    } on PathNotFoundException {
      return 'legacy';
    }
  }

  Future<Directory> activeDirectory() async => directoryFor(await activeId());

  /// Returns verified slot bindings. A binding alone does not prove that the
  /// corresponding TDLib session is still signed in.
  Future<Map<String, int>> verifiedOwners() async {
    final root = await _root();
    if (!await root.exists()) return {};
    final owners = <String, int>{};
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      const prefix = 'telegram_owner_';
      const suffix = '.txt';
      if (!name.startsWith(prefix) || !name.endsWith(suffix)) continue;
      final slot = name.substring(prefix.length, name.length - suffix.length);
      if (!_valid(slot)) continue;
      final owner = int.tryParse((await entity.readAsString()).trim());
      if (owner != null && owner > 0) owners[slot] = owner;
    }
    return Map.unmodifiable(owners);
  }

  Future<Map<String, TelegramAccountProfile>> verifiedProfiles() async {
    final owners = await verifiedOwners();
    final root = await _root();
    final profiles = <String, TelegramAccountProfile>{};
    for (final entry in owners.entries) {
      try {
        final data = jsonDecode(
          await File('${root.path}/telegram_profile_${entry.key}.json')
              .readAsString(),
        );
        if (data is! Map) continue;
        final profile = TelegramAccountProfile.fromJson(
          Map<String, dynamic>.from(data),
        );
        if (profile.id == entry.value) {
          final photo = File(
            '${root.path}/telegram_profile_${entry.key}.photo',
          );
          profiles[entry.key] = profile.withPhotoPath(
            await photo.exists() ? photo.path : null,
          );
        }
      } on FileSystemException catch (_) {
        // Older sessions do not have a saved profile yet.
      } on FormatException catch (_) {
        // Ignore damaged profiles instead of hiding the saved account.
      }
    }
    return Map.unmodifiable(profiles);
  }

  Future<void> saveProfile(String session, Map<String, dynamic> user) {
    if (!_valid(session)) throw ArgumentError.value(session, 'session');
    final profile = TelegramAccountProfile.fromUser(user);
    final result = _profileWrites.then((_) async {
      if (await activeId() != session ||
          (await verifiedOwners())[session] != profile.id) {
        return;
      }
      final root = await _root();
      final file = File('${root.path}/telegram_profile_$session.json');
      if (user.containsKey('profile_photo')) {
        String? oldPhotoId;
        try {
          final old = jsonDecode(await file.readAsString());
          if (old is Map) oldPhotoId = old['photoId'] as String?;
        } on FileSystemException catch (_) {
          // No profile was saved yet.
        } on FormatException catch (_) {
          // Replace damaged profile data.
        }
        if (profile.photoId != oldPhotoId || profile.photoId == null) {
          try {
            await File('${root.path}/telegram_profile_$session.photo').delete();
          } on PathNotFoundException {
            // No cached photo exists yet.
          }
        }
      }
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(profile.toJson()), flush: true);
      if (await activeId() != session) {
        await temp.delete();
        return;
      }
      await temp.rename(file.path);
    });
    _profileWrites = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> cacheProfilePhoto(
    String session,
    Map<String, dynamic> user,
    String path,
  ) {
    if (!_valid(session)) throw ArgumentError.value(session, 'session');
    final profile = TelegramAccountProfile.fromUser(user);
    if (profile.photoId == null) return Future.value();
    final result = _profileWrites.then((_) async {
      if (await activeId() != session ||
          (await verifiedOwners())[session] != profile.id) {
        return;
      }
      final root = await _root();
      final saved = jsonDecode(
        await File('${root.path}/telegram_profile_$session.json')
            .readAsString(),
      );
      if (saved is! Map ||
          saved['id'] != profile.id ||
          saved['photoId'] != profile.photoId) {
        return;
      }
      final target = File('${root.path}/telegram_profile_$session.photo');
      final temp = File('${target.path}.tmp');
      await File(path).copy(temp.path);
      if (await activeId() != session) {
        await temp.delete();
        return;
      }
      await temp.rename(target.path);
    });
    _profileWrites = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<String> verifyOwner(int userId) {
    if (userId <= 0) throw ArgumentError.value(userId, 'userId');
    final result = _ownerWrites.then((_) async {
      final session = await activeId();
      final root = await _root();
      final owner = File('${root.path}/telegram_owner_$session.txt');
      String? saved;
      try {
        saved = (await owner.readAsString()).trim();
      } on PathNotFoundException {
        // A new session has no owner yet.
      }
      if (saved != null && saved != '$userId') {
        throw StateError(
          'This session is assigned to a different Telegram account.',
        );
      }
      if (await activeId() != session) {
        throw StateError('Telegram session changed during verification.');
      }
      if (saved == null) {
        await root.create(recursive: true);
        final temporary = File('${owner.path}.tmp');
        await temporary.writeAsString('$userId', flush: true);
        if (await activeId() != session) {
          await temporary.delete();
          throw StateError('Telegram session changed during verification.');
        }
        await temporary.rename(owner.path);
      }
      return session;
    });
    _ownerWrites = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    return result;
  }

  Future<Directory> directoryFor(String id) async {
    if (!_valid(id)) throw ArgumentError.value(id, 'id');
    final root = await _root();
    return Directory(
      id == 'legacy'
          ? '${root.path}/telegram'
          : '${root.path}/telegram_accounts/$id',
    );
  }

  Future<void> select(String id) {
    if (!_valid(id)) throw ArgumentError.value(id, 'id');
    return _writeSelection(id);
  }

  Future<void> _writeSelection(String id) async {
    final root = await _root();
    await root.create(recursive: true);
    final file = File('${root.path}/telegram_active_session.txt');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(id, flush: true);
    await temporary.rename(file.path);
  }
}
