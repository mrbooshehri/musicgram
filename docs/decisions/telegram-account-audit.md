# Telegram account management: session-data audit

This audit describes the existing implementation before sign-out or multiple-account changes. No existing session or user data was modified.

## Current ownership

- **TDLib client:** `lib/telegram_client.dart` exposes one process-wide `TelegramClient.shared`, one client ID, one authorization state, one request map, and one receive loop. The Android bridge's `receive` operation receives TDLib updates globally. No client close/recreate or sign-out lifecycle is currently implemented.
- **TDLib database:** `lib/telegram_screen.dart` initializes TDLib with one application-support directory, `telegram`. Existing installations must continue to recognize that directory during migration. Its presence alone does not prove a valid signed-in session.
- **Telegram discovery cache:** `lib/telegram_library_cache.dart` resolves `getMe` and stores `telegram_music_<user id>.json` per Telegram user. `TelegramCacheStorage.clear` currently removes all matching users' files, not just an active account.
- **User playlists:** `lib/playlist_store.dart` stores local and Telegram playlists together in `playlists.json`. Telegram entries can contain message data; they do not carry an owner account ID. Chat and message IDs alone must not be treated as proof that another account is authorized to read the content.
- **Downloaded tracks:** `lib/downloaded_tracks.dart` stores one secure-storage map under `telegram_downloaded_tracks`, keyed by a remote unique file ID or chat/message IDs. Downloaded audio is saved in Android's shared Music storage. Signing out must not silently delete those user-visible files. Ownership and collision handling for older records need an explicit migration.
- **Proxy settings:** `lib/telegram_screen.dart` stores the proxy list and selection under the shared secure-storage key `telegram_proxies`. TDLib also stores its enabled proxy in its own database. Decide and document whether proxies are global or per account before switching.
- **Playback and downloads:** `PlaybackController` has one in-memory queue. Telegram tracks may hold TDLib file IDs, message maps, and local loopback stream URLs. `TelegramStreamServer` uses the shared client request callback and can prebuffer. Playlist downloads can remain queued asynchronously. These must be stopped, drained, or invalidated before changing the active client.
- **Other state:** `playback_state.json` stores one current path and position, including possible loopback paths; restoring a Telegram loopback URL across sessions is unsafe. Lyrics selections use a shared file with Telegram chat/message-derived keys. Account-switch handling must avoid cross-account collisions or unauthorized reuse.
- **Diagnostics:** connection and player logs are session-only. Continue to exclude credentials, phone numbers, message contents, paths and proxy secrets.

## Implications for the next steps

1. Implement sign-out as a lifecycle operation that stops account-bound streaming and pending work, sends TDLib `logOut`, observes authorization closure, and permits a fresh client. A request response alone is not proof that closure is complete.
2. Preserve shared downloaded files and local playlists. Make cleanup of caches or account-owned records explicit; do not assume all locally stored data is safe to delete.
3. Before multiple accounts, isolate the TDLib database per account and route global native receive events by client ID. Scope Telegram playlists, download records, lyrics keys, cached media and ongoing operations to the account, while keeping local playlists and device settings intact.
4. Migrate the existing single-session database and shared records conservatively. Verify migration and rollback on copies before touching a real session. Records whose ownership cannot be established should not be silently assigned to another account.
5. Test sign-out, closure, restart, switching, cancellation and account isolation using fake TDLib events, then verify on a real Android device with test accounts. Avoid logging private account data.
