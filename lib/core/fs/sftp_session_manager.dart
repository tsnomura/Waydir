import '../../features/locations/location_resolver.dart'
    show SftpCredentials, SftpAuthMethod;
import '../../features/locations/location_uri.dart';
import 'waydir_core_loader.dart';

enum SftpOpenStatus { ok, authRequired, error }

class SftpOpenOutcome {
  final SftpOpenStatus status;
  final int? sessionId;
  final String? message;

  const SftpOpenOutcome({required this.status, this.sessionId, this.message});
}

class SftpSessionRecord {
  final String root;
  final String host;
  final int port;
  final String user;
  final int sessionId;

  const SftpSessionRecord({
    required this.root,
    required this.host,
    required this.port,
    required this.user,
    required this.sessionId,
  });

  Map<String, dynamic> toJson() => {
    'root': root,
    'host': host,
    'port': port,
    'user': user,
    'sessionId': sessionId,
  };

  factory SftpSessionRecord.fromJson(Map<String, dynamic> json) =>
      SftpSessionRecord(
        root: json['root'] as String,
        host: json['host'] as String,
        port: json['port'] as int,
        user: json['user'] as String,
        sessionId: json['sessionId'] as int,
      );
}

/// Singleton zarządzający aktywnymi sesjami SFTP.
///
/// "Root" sesji to logical URI postaci `sftp://user@host:port` — identyfikuje
/// sesję dla UI (sidebar) i służy do routingu ścieżek na `sessionId` Rust core.
class SftpSessionManager {
  SftpSessionManager._();

  static final Map<String, SftpSessionRecord> _byRoot = {};

  /// Ostatnio zarejestrowany handler proszący użytkownika o dane logowania,
  /// używany przy reconnectcie po zerwanym połączeniu (np. z boku Sidebara).
  static Future<SftpCredentials?> Function(String logical)?
  credentialsRequester;

  static List<String> activeRoots() => _byRoot.keys.toList();

  static SftpSessionRecord? recordFor(String anyPath) {
    if (!anyPath.startsWith('sftp://')) return null;
    final uri = LocationUri.parse(anyPath);
    final root = rootOf(uri);

    return _byRoot[root];
  }

  /// Zamienia logical SFTP URI na ścieżkę po stronie serwera (`/foo/bar`).
  static String remotePath(String anyPath) {
    if (!anyPath.startsWith('sftp://')) return anyPath;
    final uri = LocationUri.parse(anyPath);
    final p = uri.path ?? '';

    return p.isEmpty ? '/' : '/$p';
  }

  /// Buduje logical URI rootu dla danego LocationUri sftp.
  static String rootOf(LocationUri uri) {
    final buf = StringBuffer('sftp://');
    final user = uri.username;
    if (user != null && user.isNotEmpty) {
      buf.write(Uri.encodeComponent(user));
      buf.write('@');
    }
    buf.write(uri.host ?? '');
    if (uri.port != null && uri.port != 22) {
      buf.write(':');
      buf.write(uri.port);
    }

    return buf.toString();
  }

  static String buildLogicalPath({
    required String host,
    required int port,
    required String user,
    String remotePath = '/',
  }) {
    final buf = StringBuffer('sftp://');
    if (user.isNotEmpty) {
      buf.write(Uri.encodeComponent(user));
      buf.write('@');
    }
    buf.write(host);
    if (port != 22) {
      buf.write(':');
      buf.write(port);
    }
    final trimmed = remotePath.replaceFirst(RegExp('^/+'), '');
    if (trimmed.isNotEmpty) {
      buf.write('/');
      buf.write(trimmed);
    }

    return buf.toString();
  }

  static String logicalPathForRecord(
    SftpSessionRecord record, {
    String remotePath = '/',
  }) {
    return buildLogicalPath(
      host: record.host,
      port: record.port,
      user: record.user,
      remotePath: remotePath,
    );
  }

  static String logicalPathForSession({
    required String host,
    required int port,
    required String user,
    String remotePath = '/',
  }) {
    return buildLogicalPath(
      host: host,
      port: port,
      user: user,
      remotePath: remotePath,
    );
  }

  static String defaultRemotePath(int sessionId, String user) {
    final home = WaydirCoreLoader.sftpRealPath(sessionId, '.');
    if (home != null && home.startsWith('/')) {
      final stat = WaydirCoreLoader.sftpStat(sessionId, home);
      if (stat != null && stat.exists && stat.isDir) {
        return home;
      }
    }
    final candidates = [
      if (user.isNotEmpty) '/home/$user',
      if (user.isNotEmpty) '/Users/$user',
    ];
    for (final path in candidates) {
      final stat = WaydirCoreLoader.sftpStat(sessionId, path);
      if (stat != null && stat.exists && stat.isDir) {
        return path;
      }
    }

    return '/';
  }

  static Future<SftpOpenOutcome> openSession({
    required String host,
    required int port,
    required String username,
    SftpCredentials? credentials,
  }) async {
    final user = credentials?.username.isNotEmpty == true
        ? credentials!.username
        : username;
    final root = buildLogicalPath(host: host, port: port, user: user);
    final existing = _byRoot[root];
    if (existing != null) {
      return SftpOpenOutcome(
        status: SftpOpenStatus.ok,
        sessionId: existing.sessionId,
      );
    }

    int authKind;
    String? password;
    String? keyPath;
    String? passphrase;
    if (credentials == null) {
      authKind = 0; // auto
    } else {
      switch (credentials.method) {
        case SftpAuthMethod.auto:
          authKind = 0;
          break;
        case SftpAuthMethod.password:
          authKind = 1;
          password = credentials.password;
          break;
        case SftpAuthMethod.privateKey:
          authKind = 2;
          keyPath = credentials.privateKeyPath;
          passphrase = credentials.passphrase;
          break;
      }
    }

    final result = WaydirCoreLoader.sftpOpen(
      host: host,
      port: port,
      user: user,
      authKind: authKind,
      password: password,
      keyPath: keyPath,
      passphrase: passphrase,
    );

    if (result.isOk) {
      _byRoot[root] = SftpSessionRecord(
        root: root,
        host: host,
        port: port,
        user: user,
        sessionId: result.sessionId,
      );

      return SftpOpenOutcome(
        status: SftpOpenStatus.ok,
        sessionId: result.sessionId,
      );
    }
    if (result.isAuthRequired) {
      return const SftpOpenOutcome(status: SftpOpenStatus.authRequired);
    }

    return SftpOpenOutcome(
      status: SftpOpenStatus.error,
      message: result.errorMessage,
    );
  }

  /// Sprawdza, czy sesja wciąż odpowiada (lekki round-trip: canonicalize).
  static bool isAlive(int sessionId) {
    return WaydirCoreLoader.sftpRealPath(sessionId, '.') != null;
  }

  /// Próbuje otworzyć sesję dla `host`/`port`/`username`: najpierw bez danych
  /// logowania (klucze auto), a gdy serwer zażąda auth — przez
  /// [credentialsRequester]. Zwraca nowy rekord albo `null`, gdy się nie
  /// powiodło albo użytkownik anulował prompt. Rekord jest odczytywany po
  /// faktycznie użytym użytkowniku (może różnić się od `username`, gdy prompt
  /// zwrócił inną nazwę), żeby uniknąć niedopasowania klucza roota.
  static Future<SftpSessionRecord?> _openWithPrompt({
    required String host,
    required int port,
    required String username,
    required String logicalForPrompt,
  }) async {
    var outcome = await openSession(host: host, port: port, username: username);
    if (outcome.status == SftpOpenStatus.ok) {
      return _byRoot[buildLogicalPath(host: host, port: port, user: username)];
    }
    if (outcome.status != SftpOpenStatus.authRequired) {
      return null;
    }
    final requester = credentialsRequester;
    if (requester == null) return null;
    final credentials = await requester(logicalForPrompt);
    if (credentials == null || credentials.username.trim().isEmpty) {
      return null;
    }
    outcome = await openSession(
      host: host,
      port: port,
      username: username,
      credentials: credentials,
    );
    if (outcome.status != SftpOpenStatus.ok) return null;
    final resolvedUser = credentials.username.isNotEmpty
        ? credentials.username
        : username;

    return _byRoot[buildLogicalPath(
      host: host,
      port: port,
      user: resolvedUser,
    )];
  }

  /// In-flight connection attempts keyed by root (`sftp://[user@]host[:port]`),
  /// so concurrent callers for the same target (e.g. several tabs open on the
  /// same dropped session) share one reconnect/reauth instead of each
  /// prompting for credentials independently.
  static final Map<String, Future<SftpSessionRecord?>> _pendingConnects = {};

  static Future<SftpSessionRecord?> _coalesce(
    String key,
    Future<SftpSessionRecord?> Function() start,
  ) {
    final pending = _pendingConnects[key];
    if (pending != null) return pending;
    final future = start();
    _pendingConnects[key] = future;
    future.whenComplete(() {
      if (identical(_pendingConnects[key], future)) {
        _pendingConnects.remove(key);
      }
    });

    return future;
  }

  /// Zamyka martwą sesję i próbuje ją odtworzyć (z reautentykacją w razie
  /// potrzeby). Zwraca nowy rekord albo `null`, gdy reconnect się nie
  /// powiódł albo użytkownik anulował prompt. Współbieżne wywołania dla tego
  /// samego roota dzielą jedną próbę (patrz [_coalesce]).
  static Future<SftpSessionRecord?> reconnect(SftpSessionRecord record) {
    return _coalesce(record.root, () async {
      closeRoot(record.root);

      return _openWithPrompt(
        host: record.host,
        port: record.port,
        username: record.user,
        logicalForPrompt: logicalPathForRecord(record),
      );
    });
  }

  /// Zapewnia działającą sesję dla dowolnej ścieżki `sftp://...`: reużywa
  /// żywą sesję, reconnectuje martwą, a gdy nie ma żadnego rekordu (np. po
  /// wcześniejszym nieudanym reconnectcie, który usunął go z puli) — otwiera
  /// nową sesję na podstawie host/port/user zakodowanych w samej ścieżce.
  /// Zwraca działający rekord albo `null`, gdy nie udało się połączyć.
  static Future<SftpSessionRecord?> ensureSession(String anyPath) async {
    if (!anyPath.startsWith('sftp://')) return null;
    final existing = recordFor(anyPath);
    if (existing != null) {
      if (isAlive(existing.sessionId)) return existing;

      return reconnect(existing);
    }
    final uri = LocationUri.parse(anyPath);
    final host = uri.host ?? '';
    if (host.isEmpty) return null;
    final port = uri.port ?? 22;
    final username = uri.username ?? '';
    final key = buildLogicalPath(host: host, port: port, user: username);

    return _coalesce(
      key,
      () => _openWithPrompt(
        host: host,
        port: port,
        username: username,
        logicalForPrompt: key,
      ),
    );
  }

  static void closeRoot(String root) {
    final rec = _byRoot.remove(root);
    if (rec != null) {
      WaydirCoreLoader.sftpClose(rec.sessionId);
    }
  }

  /// Migawka aktywnych sesji do przekazania do isolate'a roboczego.
  /// Worker nie otwiera nowych połączeń — używa wpisów z migawki do
  /// resolvowania `sessionId` po ścieżkach URI.
  static List<SftpSessionRecord> exportRecords() => _byRoot.values.toList();

  /// Wstrzykuje wpisy sesji w bieżącym isolate (do użycia w isolate'cie
  /// roboczym, gdzie statyczna mapa jest pusta). Nie otwiera nowych sesji.
  static void seedRecords(Iterable<SftpSessionRecord> records) {
    for (final rec in records) {
      _byRoot[rec.root] = rec;
    }
  }

  static void debugReset() {
    for (final rec in _byRoot.values) {
      WaydirCoreLoader.sftpClose(rec.sessionId);
    }
    _byRoot.clear();
  }
}
