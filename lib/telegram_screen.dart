import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_snack_bar.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'telegram_client.dart';
import 'telegram_session_store.dart';
import 'telegram_account_card.dart';
import 'telegram_playlists_screen.dart';
import 'telegram_sync_job.dart';
import 'telegram_background_recovery.dart';
import 'telegram_sync_chat_screen.dart';
import 'telegram_connection_log.dart';
export 'telegram_connection_log.dart' show telegramConnectionLog;

class TelegramScreen extends StatefulWidget {
  const TelegramScreen({
    super.key,
    this.openProxyList = false,
    this.onPlay,
    this.onDownload,
    this.openPlaylists = false,
    this.onDownloadPlaylist,
    this.onOpenLocal,
    this.onOpenPlaylists,
    this.onBootstrapStatus,
    this.onBeforeSignOut,
  });
  final bool openProxyList;
  final bool openPlaylists;
  final Future<void> Function(List<Map<String, dynamic>>, int, String)? onPlay;
  final Future<void> Function(Map<String, dynamic>, String)? onDownload;
  final void Function(List<Map<String, dynamic>>, String)? onDownloadPlaylist;
  final VoidCallback? onOpenLocal;
  final VoidCallback? onOpenPlaylists;
  final void Function(String state, String? error)? onBootstrapStatus;
  final Future<void> Function()? onBeforeSignOut;
  @override
  State<TelegramScreen> createState() => _TelegramScreenState();
}

class _TelegramScreenState extends State<TelegramScreen> {
  final client = TelegramClient.shared;
  static const apiId = int.fromEnvironment('TELEGRAM_API_ID');
  static const apiHash = String.fromEnvironment('TELEGRAM_API_HASH');
  final proxyHost = TextEditingController();
  final proxyPort = TextEditingController();
  final proxyUser = TextEditingController();
  final proxyPassword = TextEditingController();
  final proxySecret = TextEditingController();
  String proxyType = 'none';
  final List<Map<String, String>> proxies = [];
  int? selectedProxy;
  final Map<String, int?> proxyLatency = {};
  String? pendingProxyKey;
  VoidCallback? refreshProxyList;
  int _proxySelectionGeneration = 0;

  Future<void> checkProxy(
    Map<String, String> proxy,
    VoidCallback update,
  ) async {
    final host = proxy['host']!;
    final port = int.tryParse(proxy['port'] ?? '');
    final key = '$host:$port';
    if (port == null) return;
    final timer = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      socket.destroy();
      proxyLatency[key] = timer.elapsedMilliseconds;
    } catch (_) {
      proxyLatency[key] = null;
    }
    if (mounted) update();
  }

  Country? selectedCountry;
  final input = TextEditingController();
  String state = 'credentials';
  String? _error;
  String? get error => _error;
  set error(String? value) {
    if (value != null && value != _error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            AppSnackBar(kind: AppNoticeKind.error, content: Text(value)),
          );
      });
    }
    _error = value;
  }

  StateSetter? _loginUpdate;
  bool running = false;
  bool receiveLoopActive = false;
  bool proxyConfigured = false;
  bool parametersSent = false;
  bool _openedPlaylists = false;
  bool _initializing = true;
  String? _reportedStatus;
  String? _reportedError;
  Future<Map<String, dynamic>>? _accountInfo;
  int? _currentAccountId;
  bool _signingOut = false;
  bool _changingAccount = false;
  String? _recoverySession;

  Future<void> _retryVerification() async {
    setState(() {
      state = 'connecting';
      error = null;
    });
    try {
      await client.verifyAccount();
      if (!mounted) return;
      setState(() {
        state = 'ready';
        error = null;
      });
      _openRequestedPlaylists();
    } catch (_) {
      if (mounted) {
        setState(() {
          state = 'accountMismatch';
          error =
              'Could not verify this Telegram account for the current session.';
        });
      }
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Telegram?'),
        content: const Text(
          'Your downloaded music and playlists will remain on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _signingOut = true;
      error = null;
    });
    try {
      final prepare = widget.onBeforeSignOut;
      if (prepare == null) {
        throw StateError('Return to Telegram settings to sign out.');
      }
      await TelegramSyncJob.shared.cancel();
      await prepare();
      await client.logOut();
      running = false;
      connectionTimeout?.cancel();
      parametersSent = false;
      proxyConfigured = false;
      _accountInfo = null;
      _currentAccountId = null;
      input.clear();
      if (mounted) {
        setState(() {
          state = 'credentials';
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Could not sign out: $e');
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _manageAccounts() async {
    final sessions = TelegramSessionStore();
    try {
      final owners = await sessions.verifiedOwners();
      final profiles = await sessions.verifiedProfiles();
      final current = await sessions.activeId();
      if (!mounted) return;
      final chosen = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Telegram accounts')),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in owners.entries)
                      ListTile(
                        leading: entry.key == current && _accountInfo != null
                            ? FutureBuilder<Map<String, dynamic>>(
                                future: _accountInfo,
                                builder: (context, snapshot) => snapshot.hasData
                                    ? TelegramProfileAvatar(
                                        user: snapshot.data,
                                        request: client.request,
                                        onPhotoResolved: _cacheAccountPhoto,
                                      )
                                    : TelegramCachedProfileAvatar(
                                        path: profiles[entry.key]?.photoPath,
                                      ),
                              )
                            : TelegramCachedProfileAvatar(
                                path: profiles[entry.key]?.photoPath,
                              ),
                        title: Text(
                          profiles[entry.key]?.displayName ??
                              'Telegram account',
                        ),
                        subtitle: Text(
                          profiles[entry.key]?.username != null &&
                                  profiles[entry.key]!.username!.isNotEmpty
                              ? '@${profiles[entry.key]!.username}'
                              : 'No username available',
                        ),
                        trailing: entry.key == current
                            ? const Icon(Icons.check)
                            : null,
                        onTap: entry.key == current
                            ? null
                            : () => Navigator.pop(context, entry.key),
                      ),
                    ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_add_alt_1),
                      ),
                      title: const Text('Add account'),
                      onTap: () => Navigator.pop(context, 'add'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      if (chosen == null || !mounted) return;
      final isNew = chosen == 'add';
      final target = isNew ? await sessions.newSessionId() : chosen;
      if (!mounted) return;
      await _changeAccount(target, isNew: isNew);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load Telegram accounts.');
    }
  }

  Future<void> _changeAccount(String target, {required bool isNew}) async {
    final prepare = widget.onBeforeSignOut;
    if (prepare == null) {
      setState(() => error = 'Open Telegram settings to switch accounts.');
      return;
    }
    setState(() {
      _changingAccount = true;
      error = null;
    });
    try {
      await client.switchSession(
        target,
        prepare: () async {
          await TelegramSyncJob.shared.cancel(preserveCheckpoint: true);
          TelegramSyncJob.shared.clearRecoveryView();
          await prepare();
        },
      );
      connectionTimeout?.cancel();
      parametersSent = false;
      proxyConfigured = false;
      _accountInfo = null;
      _currentAccountId = null;
      input.clear();
      if (!mounted) return;
      setState(() {
        state = 'connecting';
        error = null;
      });
      await start(restoreSession: !isNew);
      if (isNew && mounted) await _openLogin();
    } catch (_) {
      if (mounted) {
        setState(() {
          state = client.isAccountVerified ? 'ready' : 'credentials';
          error = 'Could not switch Telegram accounts. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _changingAccount = false);
    }
  }

  Future<Map<String, dynamic>> _loadAccount() async {
    final session = client.verifiedSessionId;
    final user = await client.request({'@type': 'getMe'});
    if (session == null || client.verifiedSessionId != session) {
      throw StateError('Telegram account changed.');
    }
    _currentAccountId = user['id'] is int ? user['id'] as int : null;
    try {
      await TelegramSessionStore().saveProfile(session, user);
    } catch (_) {
      // Account information is still usable if profile caching fails.
    }
    return user;
  }

  Future<void> _cacheAccountPhoto(
    Map<String, dynamic> user,
    String path,
  ) async {
    final session = client.verifiedSessionId;
    if (session == null) return;
    final store = TelegramSessionStore();
    await store.cacheProfilePhoto(session, user, path);
    final cached = (await store.verifiedProfiles())[session]?.photoPath;
    if (cached != null) await FileImage(File(cached)).evict();
  }

  void _openRequestedPlaylists() {
    if (!widget.openPlaylists || _openedPlaylists || state != 'ready') return;
    _openedPlaylists = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (widget.onOpenPlaylists != null) {
          widget.onOpenPlaylists!();
          return;
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => TelegramPlaylistsScreen(
              onPlay: widget.onPlay,
              onDownload: widget.onDownload,
              onDownloadPlaylist: widget.onDownloadPlaylist,
              onOpenLocal: widget.onOpenLocal,
            ),
          ),
        );
      }
    });
  }

  Timer? connectionTimeout;

  static const _storage = FlutterSecureStorage();
  Future<void> _saveProxies() async {
    try {
      await _storage.write(
        key: 'telegram_proxies',
        value: jsonEncode({
          'proxies': proxies,
          'selected': selectedProxy,
          'enabled': proxyType != 'none',
        }),
      );
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save proxy settings securely.');
      }
    }
  }

  Future<void> _loadProxies() async {
    try {
      final raw = await _storage.read(key: 'telegram_proxies');
      if (raw == null || !mounted) return;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      final items = (saved['proxies'] as List)
          .map((item) => Map<String, String>.from(item as Map))
          .toList();
      final selected = saved['selected'];
      setState(() {
        proxies
          ..clear()
          ..addAll(items);
        selectedProxy =
            selected is int && selected >= 0 && selected < items.length
            ? selected
            : null;
      });
      if (saved['enabled'] == true && selectedProxy != null) {
        applyProxy(selectedProxy!);
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Could not restore proxy settings.');
    }
  }

  @override
  void initState() {
    super.initState();
    client.addListener(_refreshConnectionStatus);
    TelegramSyncJob.shared.addListener(_syncStatusChanged);
    if (client.isAccountVerified) _refreshConnectionStatus();
    unawaited(_prepare());
  }

  void _syncStatusChanged() {
    final failure = TelegramSyncJob.shared.error;
    if (failure != null && mounted) setState(() => error = failure);
  }

  Future<void> _chooseChatsToSync() async {
    final selected = await Navigator.of(context).push<Set<int>>(
      MaterialPageRoute(builder: (_) => const TelegramSyncChatScreen()),
    );
    if (!mounted || selected == null || selected.isEmpty) return;
    TelegramSyncJob.shared.start(chatIds: selected);
  }

  Future<void> _prepare() async {
    try {
      await _initializeProxies();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not restore the Telegram session.');
      }
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  void _reportBootstrapStatus() {
    if (widget.onBootstrapStatus == null) return;
    final status = _initializing ? 'initializing' : state;
    final currentError = _initializing ? null : error;
    if (_reportedStatus == status && _reportedError == currentError) return;
    _reportedStatus = status;
    _reportedError = currentError;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onBootstrapStatus?.call(status, currentError);
    });
  }

  void _refreshConnectionStatus() {
    refreshProxyList?.call();
    final session = client.verifiedSessionId;
    if (client.isAccountVerified &&
        session != null &&
        _recoverySession != session) {
      _recoverySession = session;
      unawaited(
        TelegramSyncJob.shared.findInterrupted().catchError((Object _) {
          if (mounted) {
            setState(() => error = 'Could not read the interrupted sync.');
          }
        }),
      );
    }
    if (!client.isAccountVerified) _recoverySession = null;
    if (mounted) setState(() {});
  }

  void _openLibrary({bool refresh = false}) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TelegramPlaylistsScreen(
          onPlay: widget.onPlay,
          onDownload: widget.onDownload,
          onDownloadPlaylist: widget.onDownloadPlaylist,
          initialRefresh: refresh,
        ),
      ),
    );
  }

  Future<void> _initializeProxies() async {
    await TelegramBackgroundRecovery.running;
    await _loadProxies();
    if (!mounted) return;
    if (client.isRunning) {
      running = true;
      final auth = client.authorizationState;
      setState(() {
        state = switch (auth) {
          'authorizationStateReady' => 'connecting',
          'authorizationStateWaitPhoneNumber' => 'phone',
          'authorizationStateWaitCode' => 'code',
          'authorizationStateWaitPassword' => 'password',
          _ => 'connecting',
        };
      });
      if (!receiveLoopActive) unawaited(receive());
      if (auth == 'authorizationStateReady') {
        try {
          await client.verifyAccount();
          if (mounted) {
            setState(() {
              state = 'ready';
              error = null;
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              state = 'accountMismatch';
              error = 'Could not verify this Telegram account for the current session.';
            });
          }
        }
      }
      _openRequestedPlaylists();
      // The page may have closed while TDLib was changing state.
      await client.send({'@type': 'getAuthorizationState'});
      await client.send({'@type': 'getProxies', '@extra': 'proxy_status'});
    } else if (Platform.isAndroid && apiId > 0 && apiHash.isNotEmpty) {
      try {
        final directory = await TelegramSessionStore().activeDirectory();
        final hasSession = await directory.exists();
        if (mounted && hasSession) {
          await start(restoreSession: true);
        }
      } catch (_) {
        if (mounted) {
          setState(() => error = 'Could not restore the Telegram session.');
        }
      }
    }
    if (mounted && widget.openProxyList) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await openProxySettings();
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  void logEvent(String event) {
    recordTelegramConnection(event);
  }

  Future<void> importClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    importProxy(data?.text ?? '');
  }

  void importProxy(String text) {
    final uri = Uri.tryParse(text.trim());
    final kind = uri?.scheme == 'tg'
        ? uri?.host
        : uri?.host.toLowerCase() == 't.me'
        ? uri?.pathSegments.firstOrNull
        : null;
    final params = uri?.queryParameters ?? {};
    final port = int.tryParse(params['port'] ?? '');
    if ((kind != 'proxy' && kind != 'socks') ||
        (params['server'] ?? '').isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        (kind == 'proxy' && (params['secret'] ?? '').isEmpty)) {
      setState(() => error = 'This is not a valid Telegram proxy link.');
      return;
    }
    setState(() {
      proxyType = kind == 'proxy' ? 'mtproto' : 'socks5';
      proxyHost.text = params['server']!;
      proxyPort.text = '$port';
      proxySecret.text = params['secret'] ?? '';
      proxyUser.text = params['user'] ?? '';
      proxyPassword.text = params['pass'] ?? '';
      error = null;
    });
  }

  Future<void> scanProxy() async {
    var detected = false;
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Scan proxy QR code')),
          body: MobileScanner(
            onDetect: (capture) {
              if (detected) return;
              for (final barcode in capture.barcodes) {
                final raw = barcode.rawValue;
                if (raw != null && raw.isNotEmpty) {
                  detected = true;
                  Navigator.of(context).pop(raw);
                  break;
                }
              }
            },
          ),
        ),
      ),
    );
    if (mounted && value != null) importProxy(value);
  }

  bool isDuplicateProxy(Map<String, String> candidate, {int? except}) {
    for (var i = 0; i < proxies.length; i++) {
      if (i == except) continue;
      final existing = proxies[i];
      if (existing['type'] == candidate['type'] &&
          existing['host']?.trim().toLowerCase() ==
              candidate['host']?.trim().toLowerCase() &&
          int.tryParse(existing['port'] ?? '') ==
              int.tryParse(candidate['port'] ?? '') &&
          existing['user'] == candidate['user'] &&
          existing['password'] == candidate['password'] &&
          existing['secret'] == candidate['secret']) {
        return true;
      }
    }
    return false;
  }

  void applyProxy(int index) {
    final proxy = proxies[index];
    setState(() {
      selectedProxy = index;
      proxyType = proxy['type']!;
      proxyHost.text = proxy['host']!;
      proxyPort.text = proxy['port']!;
      proxyUser.text = proxy['user']!;
      proxyPassword.text = proxy['password']!;
      proxySecret.text = proxy['secret']!;
    });
    unawaited(_saveProxies());
  }

  Future<void> activateProxy(int index) async {
    final generation = ++_proxySelectionGeneration;
    applyProxy(index);
    if (!client.isRunning) return;
    final proxy = Map<String, String>.of(proxies[index]);
    final type = switch (proxy['type']) {
      'socks5' => {
        '@type': 'proxyTypeSocks5',
        'username': proxy['user'] ?? '',
        'password': proxy['password'] ?? '',
      },
      'http' => {
        '@type': 'proxyTypeHttp',
        'username': proxy['user'] ?? '',
        'password': proxy['password'] ?? '',
        'http_only': false,
      },
      _ => {'@type': 'proxyTypeMtproto', 'secret': proxy['secret'] ?? ''},
    };
    client.proxySwitchStarted();
    try {
      await client.request({
        '@type': 'addProxy',
        'proxy': {
          '@type': 'proxy',
          'server': proxy['host'],
          'port': int.parse(proxy['port']!),
          'type': type,
        },
        'enable': true,
      });
      if (generation != _proxySelectionGeneration) return;
      client.proxyEnabled('${proxy['host']}:${int.parse(proxy['port']!)}');
      unawaited(client.refreshConnectionState().catchError((_) {}));
      await client.send({'@type': 'getProxies', '@extra': 'proxy_status'});
    } catch (error) {
      if (generation != _proxySelectionGeneration) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar(
            kind: AppNoticeKind.error,
            content: Text('Could not activate proxy: $error'),
          ),
        );
      }
    }
  }

  Future<void> editProxy(int index) async {
    final item = proxies[index];
    var type = item['type']!;
    final host = TextEditingController(text: item['host']);
    final port = TextEditingController(text: item['port']);
    final user = TextEditingController(text: item['user']);
    final password = TextEditingController(text: item['password']);
    final secret = TextEditingController(text: item['secret']);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, update) => Scaffold(
            appBar: AppBar(title: const Text('Proxy details')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'socks5', child: Text('SOCKS5')),
                    DropdownMenuItem(value: 'http', child: Text('HTTP')),
                    DropdownMenuItem(value: 'mtproto', child: Text('MTProto')),
                  ],
                  onChanged: (value) => update(() => type = value ?? type),
                ),
                TextField(
                  controller: host,
                  decoration: const InputDecoration(labelText: 'Server'),
                ),
                TextField(
                  controller: port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port'),
                ),
                if (type == 'mtproto')
                  TextField(
                    controller: secret,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Secret'),
                  )
                else ...[
                  TextField(
                    controller: user,
                    decoration: const InputDecoration(
                      labelText: 'Username (optional)',
                    ),
                  ),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password (optional)',
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    final parsed = int.tryParse(port.text);
                    if (host.text.trim().isEmpty ||
                        parsed == null ||
                        parsed < 1 ||
                        parsed > 65535 ||
                        (type == 'mtproto' && secret.text.trim().isEmpty)) {
                      ScaffoldMessenger.of(pageContext).showSnackBar(
                        AppSnackBar(
                          kind: AppNoticeKind.warning,
                          content: Text(
                            'Enter a valid server, port and required secret.',
                          ),
                        ),
                      );
                      return;
                    }
                    final candidate = {
                      'type': type,
                      'host': host.text.trim(),
                      'port': port.text,
                      'user': user.text,
                      'password': password.text,
                      'secret': secret.text,
                    };
                    if (isDuplicateProxy(candidate, except: index)) {
                      ScaffoldMessenger.of(pageContext).showSnackBar(
                        AppSnackBar(
                          kind: AppNoticeKind.warning,
                          content: Text('This proxy is already in your list.'),
                        ),
                      );
                      return;
                    }
                    final active =
                        selectedProxy == index && proxyType != 'none';
                    setState(() {
                      proxies[index] = {
                        'type': type,
                        'host': host.text.trim(),
                        'port': port.text,
                        'user': user.text,
                        'password': password.text,
                        'secret': secret.text,
                      };
                    });
                    if (active) {
                      applyProxy(index);
                    } else {
                      unawaited(_saveProxies());
                    }
                    Navigator.pop(pageContext);
                  },
                  child: const Text('Save changes'),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      proxies.removeAt(index);
                      if (selectedProxy == index) {
                        selectedProxy = null;
                        proxyType = 'none';
                      } else if (selectedProxy != null &&
                          selectedProxy! > index) {
                        selectedProxy = selectedProxy! - 1;
                      }
                    });
                    unawaited(_saveProxies());
                    Navigator.pop(pageContext);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove proxy'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    host.dispose();
    port.dispose();
    user.dispose();
    password.dispose();
    secret.dispose();
  }

  Future<void> openProxySettings() async {
    var checking = false;
    var initialCheckScheduled = false;
    VoidCallback? refresh;
    Future<void> checkAll() async {
      if (checking || refresh == null) return;
      checking = true;
      try {
        await Future.wait(
          List<Map<String, String>>.of(proxies)
              .map((proxy) => checkProxy(proxy, () => refresh?.call())),
        );
      } finally {
        checking = false;
      }
    }

    final timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(checkAll()),
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => StatefulBuilder(
          builder: (context, update) {
            refresh = () {
              if (context.mounted) update(() {});
            };
            refreshProxyList = refresh;
            if (!initialCheckScheduled) {
              initialCheckScheduled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) unawaited(checkAll());
              });
            }
            return Scaffold(
              appBar: AppBar(title: const Text('Proxy settings')),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(
                    title: const Text('Use proxy'),
                    value: proxyType != 'none',
                    onChanged: (enabled) {
                      if (!enabled) {
                        _proxySelectionGeneration++;
                        setState(() => proxyType = 'none');
                        unawaited(_saveProxies());
                        if (client.isRunning) {
                          client.proxySwitchStarted();
                          unawaited(client.send({'@type': 'disableProxy'}));
                        }
                        update(() {});
                      } else if (selectedProxy != null) {
                        unawaited(activateProxy(selectedProxy!));
                        update(() {});
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          AppSnackBar(
                            kind: AppNoticeKind.warning,
                            content: Text('Select a proxy to enable it.'),
                          ),
                        );
                      }
                    },
                  ),
                  if (proxies.isEmpty)
                    const ListTile(title: Text('No proxies added')),
                  for (var i = 0; i < proxies.length; i++)
                    Card(
                      clipBehavior: Clip.antiAlias,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              color: switch (proxies[i]['type']) {
                                'mtproto' => Colors.deepPurpleAccent,
                                'socks5' => Colors.teal,
                                _ => Colors.orange,
                              },
                            ),
                            Expanded(
                              child: ListTile(
                                title: Text(
                                  '${proxies[i]['host']}:${proxies[i]['port']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        i == selectedProxy &&
                                            proxyType != 'none'
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                    fontWeight:
                                        i == selectedProxy &&
                                            proxyType != 'none'
                                        ? FontWeight.bold
                                        : null,
                                  ),
                                ),
                                subtitle: Builder(
                                  builder: (context) {
                                    final key =
                                        '${proxies[i]['host']}:${int.tryParse(proxies[i]['port'] ?? '')}';
                                    final checked = proxyLatency.containsKey(
                                      key,
                                    );
                                    final latency = proxyLatency[key];
                                    final connected =
                                        key == client.activeProxyKey &&
                                        client.proxyConnected;
                                    final label = connected
                                        ? latency == null
                                              ? 'Connected'
                                              : 'Connected, Ping: $latency ms'
                                        : !checked
                                        ? 'Not checked'
                                        : latency == null
                                        ? 'Unavailable'
                                        : 'Available, Ping: $latency ms';
                                    final color = connected
                                        ? Colors.blue
                                        : !checked
                                        ? null
                                        : latency == null
                                        ? Colors.red
                                        : Colors.green;
                                    return Text(
                                      label,
                                      style: TextStyle(color: color),
                                    );
                                  },
                                ),
                                onTap: () {
                                  unawaited(activateProxy(i));
                                  update(() {});
                                },
                                trailing: IconButton(
                                  icon: const Icon(Icons.info_outline),
                                  tooltip: 'Proxy details',
                                  onPressed: () async {
                                    await editProxy(i);
                                    if (context.mounted) update(() {});
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.network_check),
                    title: const Text('Check proxy connections'),
                    subtitle: const Text(
                      'Tests whether each server accepts a TCP connection.',
                    ),
                    onTap: () {
                      for (final proxy in List<Map<String, String>>.of(
                        proxies,
                      )) {
                        unawaited(
                          checkProxy(proxy, () {
                            if (context.mounted) update(() {});
                          }),
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Add proxy'),
                    onTap: () async {
                      final originalType = proxyType;
                      final originalHost = proxyHost.text;
                      final originalPort = proxyPort.text;
                      final originalUser = proxyUser.text;
                      final originalPassword = proxyPassword.text;
                      final originalSecret = proxySecret.text;
                      final originalCount = proxies.length;
                      proxyType = 'socks5';
                      proxyHost.clear();
                      proxyPort.clear();
                      proxyUser.clear();
                      proxyPassword.clear();
                      proxySecret.clear();
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => StatefulBuilder(
                            builder: (context, edit) => Scaffold(
                              appBar: AppBar(title: const Text('Add proxy')),
                              body: ListView(
                                padding: const EdgeInsets.all(16),
                                children: [
                                  DropdownButtonFormField<String>(
                                    initialValue: proxyType,
                                    decoration: const InputDecoration(
                                      labelText: 'Type',
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'socks5',
                                        child: Text('SOCKS5'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'http',
                                        child: Text('HTTP'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'mtproto',
                                        child: Text('MTProto'),
                                      ),
                                    ],
                                    onChanged: (v) =>
                                        edit(() => proxyType = v ?? 'socks5'),
                                  ),
                                  TextField(
                                    controller: proxyHost,
                                    decoration: const InputDecoration(
                                      labelText: 'Server',
                                    ),
                                  ),
                                  TextField(
                                    controller: proxyPort,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Port',
                                    ),
                                  ),
                                  if (proxyType == 'mtproto')
                                    TextField(
                                      controller: proxySecret,
                                      obscureText: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Secret',
                                      ),
                                    )
                                  else ...[
                                    TextField(
                                      controller: proxyUser,
                                      decoration: const InputDecoration(
                                        labelText: 'Username (optional)',
                                      ),
                                    ),
                                    TextField(
                                      controller: proxyPassword,
                                      obscureText: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Password (optional)',
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 20),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.content_paste),
                                    label: const Text('Import from clipboard'),
                                    onPressed: () async {
                                      await importClipboard();
                                      if (context.mounted) edit(() {});
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.qr_code_scanner),
                                    label: const Text('Scan QR code'),
                                    onPressed: () async {
                                      await scanProxy();
                                      if (context.mounted) edit(() {});
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                    onPressed: () {
                                      final port = int.tryParse(proxyPort.text);
                                      if (proxyHost.text.trim().isEmpty ||
                                          port == null ||
                                          port < 1 ||
                                          port > 65535 ||
                                          (proxyType == 'mtproto' &&
                                              proxySecret.text
                                                  .trim()
                                                  .isEmpty)) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              AppSnackBar(
                                                kind: AppNoticeKind.warning,
                                                content: Text(
                                                  'Enter a valid server, port and required secret.',
                                                ),
                                              ),
                                            );
                                        return;
                                      }
                                      final candidate = {
                                        'type': proxyType,
                                        'host': proxyHost.text.trim(),
                                        'port': proxyPort.text,
                                        'user': proxyUser.text,
                                        'password': proxyPassword.text,
                                        'secret': proxySecret.text,
                                      };
                                      if (isDuplicateProxy(candidate)) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              AppSnackBar(
                                                kind: AppNoticeKind.warning,
                                                content: Text(
                                                  'This proxy is already in your list.',
                                                ),
                                              ),
                                            );
                                        return;
                                      }
                                      proxies.add({
                                        'type': proxyType,
                                        'host': proxyHost.text.trim(),
                                        'port': proxyPort.text,
                                        'user': proxyUser.text,
                                        'password': proxyPassword.text,
                                        'secret': proxySecret.text,
                                      });
                                      applyProxy(proxies.length - 1);
                                      Navigator.pop(context);
                                    },
                                    child: const Text('Save proxy'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                      if (mounted) {
                        if (proxies.length == originalCount) {
                          setState(() {
                            proxyType = originalType;
                            proxyHost.text = originalHost;
                            proxyPort.text = originalPort;
                            proxyUser.text = originalUser;
                            proxyPassword.text = originalPassword;
                            proxySecret.text = originalSecret;
                          });
                        }
                        update(() {});
                      }
                    },
                  ),
                  if (proxies.isNotEmpty)
                    TextButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Delete all proxies?'),
                            content: const Text(
                              'This removes all saved proxies and disables the active proxy.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Delete all'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !context.mounted) return;
                        try {
                          if (client.isRunning) {
                            await client.send({'@type': 'disableProxy'});
                          }
                          if (!context.mounted || !mounted) return;
                          setState(() {
                            proxies.clear();
                            selectedProxy = null;
                            proxyType = 'none';
                            client.activeProxyKey = null;
                            pendingProxyKey = null;
                            proxyLatency.clear();
                          });
                          await _saveProxies();
                          if (context.mounted) update(() {});
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              AppSnackBar(
                                kind: AppNoticeKind.error,
                                content: Text(
                                  'Could not disable the active proxy.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete All Proxies'),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
    refresh = null;
    refreshProxyList = null;
    timer.cancel();
  }

  Future<void> start({bool restoreSession = false}) async {
    logEvent(
      'Starting connection (${proxyType == 'none' ? 'direct' : proxyType})',
    );
    if (!Platform.isAndroid) {
      setState(
        () => error = 'Telegram is currently available on Android only.',
      );
      return;
    }
    if (apiId <= 0 || apiHash.isEmpty) {
      setState(() => error = 'Telegram is not configured in this build.');
      return;
    }
    try {
      if (proxyType != 'none' &&
          (proxyHost.text.trim().isEmpty ||
              (int.tryParse(proxyPort.text) ?? 0) < 1 ||
              (int.tryParse(proxyPort.text) ?? 0) > 65535 ||
              (proxyType == 'mtproto' && proxySecret.text.trim().isEmpty))) {
        setState(
          () => error = 'Enter a valid proxy host, port and required secret.',
        );
        return;
      }
      await client.create();
      if (!mounted) return;
      running = true;
      setState(() {
        state = 'connecting';
        error = null;
      });
      if (!receiveLoopActive) unawaited(receive());
      if (restoreSession) {
        // TDLib stores the enabled proxy in its database with the session.
        proxyConfigured = true;
      } else if (proxyType != 'none') {
        pendingProxyKey =
            '${proxyHost.text.trim()}:${int.parse(proxyPort.text)}';
        final type = switch (proxyType) {
          'socks5' => {
            '@type': 'proxyTypeSocks5',
            'username': proxyUser.text,
            'password': proxyPassword.text,
          },
          'http' => {
            '@type': 'proxyTypeHttp',
            'username': proxyUser.text,
            'password': proxyPassword.text,
            'http_only': false,
          },
          _ => {'@type': 'proxyTypeMtproto', 'secret': proxySecret.text.trim()},
        };
        await client.send({
          '@type': 'addProxy',
          '@extra': 'proxy_setup',
          'proxy': {
            '@type': 'proxy',
            'server': proxyHost.text.trim(),
            'port': int.parse(proxyPort.text),
            'type': type,
          },
          'enable': true,
        });
      } else {
        pendingProxyKey = null;
        await client.send({'@type': 'disableProxy', '@extra': 'proxy_setup'});
      }
      await client.send({'@type': 'getAuthorizationState'});
      await client.send({'@type': 'getProxies', '@extra': 'proxy_status'});
      if (!mounted) return;
      connectionTimeout?.cancel();
      connectionTimeout = Timer(const Duration(seconds: 30), () {
        if (mounted && state == 'connecting') {
          logEvent('Connection timed out after 30 seconds');
          setState(
            () => error = 'Telegram is taking too long to connect. Check your proxy and try again.',
          );
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = 'Could not start Telegram: $e');
    }
  }

  Future<void> receive() async {
    if (receiveLoopActive) return;
    receiveLoopActive = true;
    try {
      while (running) {
        try {
          final update = await client.receive();
          if (!mounted || !running) return;
          if (update == null) continue;
          final updatedUser = update['user'];
          if (update['@type'] == 'updateUser' &&
              updatedUser is Map &&
              updatedUser['id'] == _currentAccountId &&
              client.verifiedSessionId != null) {
            final user = Map<String, dynamic>.from(updatedUser);
            final session = client.verifiedSessionId!;
            setState(() => _accountInfo = Future.value(user));
            unawaited(
              TelegramSessionStore()
                  .saveProfile(session, user)
                  .catchError((_) {}),
            );
          }
          if (update['@extra'] == 'proxy_setup') {
            logEvent('Proxy setup: ${update['@type']}');
            if (update['@type'] == 'error') {
              setState(() {
                state = 'credentials';
                error =
                    update['message']?.toString() ??
                    'Proxy configuration failed.';
              });
              continue;
            }
            proxyConfigured = true;
            if (pendingProxyKey != null) client.proxyEnabled(pendingProxyKey!);
            unawaited(client.refreshConnectionState().catchError((_) {}));
            refreshProxyList?.call();
            await client.send({
              '@type': 'getProxies',
              '@extra': 'proxy_status',
            });
            await client.send({'@type': 'getAuthorizationState'});
            continue;
          }
          if (update['@type'] == 'error') {
            setState(
              () => error =
                  update['message']?.toString() ?? 'Telegram request failed.',
            );
            continue;
          }
          final auth = update['@type'] == 'updateAuthorizationState'
              ? update['authorization_state']
              : update;
          final type = auth is Map ? auth['@type'] : null;
          if (type == 'authorizationStateWaitTdlibParameters' &&
              !parametersSent) {
            parametersSent = true;
            logEvent('Initializing TDLib');
            final dir = await TelegramSessionStore().activeDirectory();
            await client.send({
              '@type': 'setTdlibParameters',
              'database_directory': dir.path,
              'use_message_database': true,
              'use_secret_chats': false,
              'api_id': apiId,
              'api_hash': apiHash,
              'system_language_code': 'en',
              'device_model': 'Android',
              'application_version': '0.1.0',
            });
          } else if (type == 'authorizationStateWaitPhoneNumber') {
            setState(() {
              state = 'phone';
              error = null;
            });
          } else if (type == 'authorizationStateWaitCode') {
            setState(() {
              state = 'code';
              input.clear();
              error = null;
            });
          } else if (type == 'authorizationStateWaitPassword') {
            setState(() {
              state = 'password';
              input.clear();
              error = null;
            });
          } else if (type == 'authorizationStateReady') {
            try {
              await client.verifyAccount();
              if (!mounted) return;
              setState(() {
                state = 'ready';
                input.clear();
                error = null;
              });
              _openRequestedPlaylists();
            } catch (_) {
              if (mounted) {
                setState(() {
                  state = 'accountMismatch';
                  error = 'Could not verify this Telegram account for the current session.';
                });
              }
            }
          }
        } catch (e) {
          if (mounted) setState(() => error = 'Telegram connection failed: $e');
          return;
        }
      }
    } finally {
      receiveLoopActive = false;
    }
  }

  Future<void> submit() async {
    final value = input.text.trim();
    if (value.isEmpty) return;
    if (state == 'phone' && selectedCountry == null) {
      setState(() => error = 'Choose your country first.');
      return;
    }
    final request = switch (state) {
      'phone' => {
        '@type': 'setAuthenticationPhoneNumber',
        'phone_number':
            '+${selectedCountry!.phoneCode}${value.replaceAll(RegExp(r'[^0-9]'), '')}',
      },
      'code' => {'@type': 'checkAuthenticationCode', 'code': value},
      'password' => {'@type': 'checkAuthenticationPassword', 'password': value},
      _ => <String, String>{},
    };
    if (request.isNotEmpty) await client.send(request);
  }

  Future<void> _openLogin() async {
    final navigation = Navigator.of(context);
    final route = MaterialPageRoute<void>(
      builder: (loginContext) => StatefulBuilder(
        builder: (loginContext, update) {
          _loginUpdate = update;
          final step = state;
          final title = switch (step) {
            'phone' => 'Your phone number',
            'code' => 'Enter your code',
            'password' => 'Two-step verification',
            'ready' => 'You’re connected',
            _ => 'Connecting to Telegram',
          };
          return Scaffold(
            appBar: AppBar(),
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: Column(
                        key: ValueKey(step),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: Theme.of(loginContext)
                                .colorScheme
                                .primaryContainer,
                            child: Icon(
                              step == 'phone'
                                  ? Icons.phone_iphone
                                  : step == 'code'
                                  ? Icons.mark_chat_unread_outlined
                                  : step == 'password'
                                  ? Icons.lock_outline
                                  : step == 'ready'
                                  ? Icons.check
                                  : Icons.send_rounded,
                              size: 34,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: Theme.of(loginContext)
                                .textTheme
                                .headlineSmall,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            step == 'phone'
                                ? 'Choose your country and enter your number.'
                                : step == 'code'
                                ? 'Enter the code sent by Telegram.'
                                : step == 'password'
                                ? 'Enter your Telegram two-step verification password.'
                                : step == 'ready'
                                ? 'Your Telegram account is ready.'
                                : 'This may take a moment.',
                            textAlign: TextAlign.center,
                            style: Theme.of(loginContext).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 24),
                          if (step == 'phone')
                            ListTile(
                              title: Text(
                                selectedCountry == null
                                    ? 'Choose country'
                                    : '${selectedCountry!.flagEmoji}  ${selectedCountry!.name}',
                              ),
                              trailing: const Icon(Icons.arrow_drop_down),
                              onTap: () => showCountryPicker(
                                context: loginContext,
                                showPhoneCode: true,
                                onSelect: (country) {
                                  setState(() {
                                    selectedCountry = country;
                                    error = null;
                                  });
                                },
                              ),
                            ),
                          if (step == 'phone' ||
                              step == 'code' ||
                              step == 'password') ...[
                            TextField(
                              controller: input,
                              obscureText: step == 'password',
                              keyboardType: step == 'phone'
                                  ? TextInputType.phone
                                  : step == 'code'
                                  ? TextInputType.number
                                  : TextInputType.text,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                prefixText:
                                    step == 'phone' && selectedCountry != null
                                    ? '+${selectedCountry!.phoneCode}  '
                                    : null,
                                labelText: step == 'phone'
                                    ? 'Phone number'
                                    : step == 'code'
                                    ? 'Login code'
                                    : 'Password',
                              ),
                              onSubmitted: (_) => submit(),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: submit,
                                child: const Text('Continue'),
                              ),
                            ),
                          ] else if (step == 'ready')
                            FilledButton(
                              onPressed: () => Navigator.pop(loginContext),
                              child: const Text('Done'),
                            )
                          else
                            const CircularProgressIndicator(),
                          if (error != null) ...[
                            if (step == 'connecting' || step == 'credentials')
                              TextButton(
                                onPressed: start,
                                child: const Text('Try again'),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    final future = navigation.push(route);
    if (state == 'credentials') unawaited(start());
    await future;
    _loginUpdate = null;
  }

  @override
  void dispose() {
    client.removeListener(_refreshConnectionStatus);
    TelegramSyncJob.shared.removeListener(_syncStatusChanged);
    running = false;
    connectionTimeout?.cancel();
    proxyHost.dispose();
    proxyPort.dispose();
    proxyUser.dispose();
    proxyPassword.dispose();
    proxySecret.dispose();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _reportBootstrapStatus();
    if (_loginUpdate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loginUpdate?.call(() {});
      });
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Telegram')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (state == 'ready') ...[
              TelegramAccountCard(
                account: _accountInfo ??= _loadAccount(),
                connected: client.connected,
                onPhotoResolved: _cacheAccountPhoto,
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.library_music_outlined),
                      title: const Text('Telegram playlists'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openLibrary,
                    ),
                    AnimatedBuilder(
                      animation: TelegramSyncJob.shared,
                      builder: (context, _) {
                        final job = TelegramSyncJob.shared;
                        return ListTile(
                          leading: const Icon(Icons.sync),
                          title: Text(
                            job.running
                                ? 'Syncing Telegram music'
                                : 'Sync Telegram music',
                          ),
                          subtitle: job.running
                              ? Text(
                                  '${job.tracks} tracks · ${job.playlists} playlists',
                                )
                              : null,
                          trailing: job.running
                              ? TextButton(
                                  onPressed: job.cancel,
                                  child: const Text('Cancel'),
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: job.running ? null : _chooseChatsToSync,
                        );
                      },
                    ),
                    AnimatedBuilder(
                      animation: TelegramSyncJob.shared,
                      builder: (context, _) {
                        final job = TelegramSyncJob.shared;
                        final pending = job.recoverableChats;
                        if (job.running || pending == null || pending.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return ListTile(
                          leading: const Icon(Icons.restore),
                          title: const Text('Resume interrupted sync'),
                          subtitle: Text('${pending.length} chats remaining'),
                          onTap: () => job.start(chatIds: pending),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.manage_accounts_outlined),
                      title: const Text('Telegram accounts'),
                      subtitle: const Text('Add or switch accounts'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _changingAccount || _signingOut
                          ? null
                          : _manageAccounts,
                    ),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: Text(_signingOut ? 'Signing out…' : 'Sign out'),
                      onTap: _signingOut ? null : _signOut,
                    ),
                  ],
                ),
              ),
            ] else if (state == 'accountMismatch') ...[
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      title: Text('Account verification failed'),
                      subtitle: Text(
                        'Check your connection and retry, or sign out.',
                      ),
                    ),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _signingOut ? null : _retryVerification,
                          child: const Text('Retry'),
                        ),
                        TextButton(
                          onPressed: _signingOut ? null : _signOut,
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              Card(
                child: ListTile(
                  title: const Text('Telegram account'),
                  subtitle: const Text('Sign in to access your music'),
                  trailing: FilledButton(
                    onPressed: _openLogin,
                    child: const Text('Sign in'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (state != 'ready') ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('Telegram accounts'),
                  subtitle: const Text('Switch to a saved account'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _changingAccount || _signingOut
                      ? null
                      : _manageAccounts,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: const Text('Proxy settings'),
                    subtitle: Text(
                      proxyType == 'none'
                          ? 'Manage proxies'
                          : '${proxyHost.text}:${proxyPort.text}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: openProxySettings,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showTelegramLog(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            const ListTile(
              title: Text('Telegram connection log'),
              subtitle: Text(
                'Connection events only; credentials are not shown.',
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<List<String>>(
                valueListenable: telegramConnectionLog,
                builder: (context, entries, _) => entries.isEmpty
                    ? const Center(child: Text('No connection events yet.'))
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) =>
                            ListTile(dense: true, title: Text(entries[index])),
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
