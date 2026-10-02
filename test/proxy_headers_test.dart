import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/ai_search_query_rewriter.dart';
import 'package:hermes_android/core/services/config_backup.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _cf = {
  'CF-Access-Client-Id': 'id.access',
  'CF-Access-Client-Secret': 'secret-value',
};
const _pangolin = {'P-Access-Token-Id': 'tok-id', 'P-Access-Token': 'tok'};

class _MemoryCredentialStore implements CredentialStore {
  final Map<String, String> values = {};
  final Map<String, String> _cache = {};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
    _cache.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    final value = values[key];
    if (value == null) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    return value;
  }

  @override
  String? readCached(String key) => _cache[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

String? _header(http.BaseRequest request, String name) {
  for (final e in request.headers.entries) {
    if (e.key.toLowerCase() == name.toLowerCase()) return e.value;
  }
  return null;
}

void _expectHeaders(http.BaseRequest request, Map<String, String> expected) {
  for (final e in expected.entries) {
    expect(_header(request, e.key), e.value, reason: e.key);
  }
}

void main() {
  group('SavedConnection extraHeaders', () {
    SavedConnection make({Map<String, String> headers = const {}}) =>
        SavedConnection(
          id: '1',
          label: 'Home',
          host: 'hermes.example.com',
          port: 443,
          apiKey: 'key',
          useHttps: true,
          extraHeaders: headers,
        );

    test('never leak into the plain-text metadata map', () {
      final map = make(headers: _cf).toMap();
      expect(jsonEncode(map), isNot(contains('secret-value')));
      expect(map.containsKey('extra_headers'), isFalse);
    });

    test('are preserved by copyWith and replaceable', () {
      final conn = make(headers: _cf);
      expect(conn.copyWith(label: 'x').extraHeaders, _cf);
      expect(conn.copyWith(extraHeaders: const {}).extraHeaders, isEmpty);
    });

    test('are immutable', () {
      expect(
        () => make(headers: _cf).extraHeaders['X'] = 'y',
        throwsUnsupportedError,
      );
    });

    test('cleanHeaders trims and drops blank entries', () {
      expect(
        SavedConnection.cleanHeaders({
          ' A ': ' 1 ',
          'B': '',
          '': 'x',
          '  ': '  ',
        }),
        {'A': '1'},
      );
    });

    test('headersFromJson ignores non-string data', () {
      expect(SavedConnection.headersFromJson(null), isEmpty);
      expect(SavedConnection.headersFromJson('nope'), isEmpty);
      expect(SavedConnection.headersFromJson({'A': 1, 'B': 'b'}), {'B': 'b'});
    });
  });

  group('ConnectionManager persistence', () {
    late _MemoryCredentialStore store;
    late ConnectionManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = _MemoryCredentialStore();
      manager = await ConnectionManager.create(
        await SharedPreferences.getInstance(),
        credentialStore: store,
      );
    });

    test('headers live in the secure store, not SharedPreferences', () async {
      await manager.saveConnection(
        'Home',
        'https://hermes.example.com',
        null,
        'key',
        extraHeaders: _cf,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        (prefs.getStringList('saved_connections') ?? []).join(),
        isNot(contains('secret-value')),
      );
      expect(store.values.values.single, contains('secret-value'));
      expect(manager.getConnections().single.extraHeaders, _cf);
    });

    test('survive a cold start via loadConnectionsWithSecrets', () async {
      await manager.saveConnection(
        'Home',
        'hermes.example.com',
        null,
        'key',
        extraHeaders: _pangolin,
      );
      final fresh = ConnectionManager(
        await SharedPreferences.getInstance(),
        credentialStore: store,
      );
      expect(
        (await fresh.loadConnectionsWithSecrets()).single.extraHeaders,
        _pangolin,
      );
    });

    test('headers alone (no api key) are still stored', () async {
      await manager.saveConnection(
        'Home',
        'hermes.example.com',
        null,
        '',
        extraHeaders: _cf,
      );
      expect(store.values, hasLength(1));
    });

    test('updateConnection replaces, clears, or keeps headers', () async {
      await manager.saveConnection(
        'Home',
        'hermes.example.com',
        null,
        'key',
        extraHeaders: _cf,
      );
      final id = manager.getConnections().single.id;

      await manager.updateConnection(
        id,
        'Home',
        'hermes.example.com',
        null,
        'key',
        extraHeaders: _pangolin,
      );
      expect(manager.getConnections().single.extraHeaders, _pangolin);

      // Omitted: untouched.
      await manager.updateConnection(
        id,
        'Home 2',
        'hermes.example.com',
        null,
        'key',
      );
      expect(manager.getConnections().single.extraHeaders, _pangolin);

      await manager.updateConnection(
        id,
        'Home 2',
        'hermes.example.com',
        null,
        'key',
        extraHeaders: const {},
      );
      expect(manager.getConnections().single.extraHeaders, isEmpty);
      expect(store.values.values.single, isNot(contains('P-Access')));
    });

    test('other updates do not drop the headers', () async {
      await manager.saveConnection(
        'Home',
        'hermes.example.com',
        null,
        'key',
        extraHeaders: _cf,
      );
      final id = manager.getConnections().single.id;
      await manager.updateApiKey(id, 'new-key');
      await manager.updateDashboardAuth(id, username: 'u', password: 'p');
      expect(manager.getConnections().single.extraHeaders, _cf);
    });

    test('credentials stored before this feature still load', () async {
      await manager.saveConnection('Home', 'hermes.example.com', null, 'key');
      store.values[store.values.keys.single] = jsonEncode({'api_key': 'key'});
      final conn = (await manager.loadConnectionsWithSecrets()).single;
      expect(conn.apiKey, 'key');
      expect(conn.extraHeaders, isEmpty);
    });

    test('malformed stored headers fail closed', () async {
      await manager.saveConnection('Home', 'hermes.example.com', null, 'key');
      store.values[store.values.keys.single] = jsonEncode({
        'api_key': 'key',
        'extra_headers': {'A': 5},
      });
      await expectLater(
        manager.loadConnectionsWithSecrets(),
        throwsA(isA<CredentialStorageException>()),
      );
    });
  });

  group('ApiClient', () {
    test('sends proxy headers on every REST call', () async {
      final seen = <http.BaseRequest>[];
      final client = ApiClient(
        baseUrl: 'https://hermes.example.com',
        apiKey: 'key',
        extraHeaders: _cf,
        httpClient: MockClient((request) async {
          seen.add(request);
          return http.Response('{"status":"ok","data":[]}', 200);
        }),
      );
      await client.checkHealth();
      await client.getSessions();
      expect(seen, isNotEmpty);
      for (final r in seen) {
        _expectHeaders(r, _cf);
        expect(_header(r, 'authorization'), 'Bearer key');
      }
    });

    test('gateway auth wins if a proxy header collides', () async {
      late http.BaseRequest seen;
      final client = ApiClient(
        baseUrl: 'https://hermes.example.com',
        apiKey: 'key',
        extraHeaders: const {'Authorization': 'Basic abc'},
        httpClient: MockClient((request) async {
          seen = request;
          return http.Response('{"status":"ok"}', 200);
        }),
      );
      await client.checkHealth();
      expect(_header(seen, 'authorization'), 'Bearer key');
    });
  });

  group('DashboardClient', () {
    test('proxied mode still sends proxy headers', () async {
      late http.BaseRequest seen;
      final client = DashboardClient(
        host: 'hermes.example.com',
        port: 443,
        useHttps: true,
        proxied: true,
        extraHeaders: _pangolin,
        httpClient: MockClient((request) async {
          seen = request;
          return http.Response('{}', 200);
        }),
      );
      await client.getModelInfo();
      _expectHeaders(seen, _pangolin);
    });

    test('session-token fetch and API call both carry them', () async {
      final seen = <http.BaseRequest>[];
      final client = DashboardClient(
        host: 'hermes.example.com',
        port: 443,
        useHttps: true,
        extraHeaders: _cf,
        httpClient: MockClient((request) async {
          seen.add(request);
          if (request.url.path == '/') {
            return http.Response(
              '<script>window.__HERMES_SESSION_TOKEN__="tok";</script>',
              200,
            );
          }
          return http.Response('{}', 200);
        }),
      );
      await client.getModelInfo();
      expect(seen, hasLength(2));
      for (final r in seen) {
        _expectHeaders(r, _cf);
      }
      expect(_header(seen.last, 'x-hermes-session-token'), 'tok');
    });

    test('password login and follow-up calls carry them', () async {
      final seen = <http.BaseRequest>[];
      final client = DashboardClient(
        host: 'hermes.example.com',
        port: 443,
        useHttps: true,
        username: 'u',
        password: 'p',
        extraHeaders: _cf,
        httpClient: MockClient((request) async {
          seen.add(request);
          if (request.url.path == '/auth/password-login') {
            return http.Response(
              '{}',
              200,
              headers: {'set-cookie': 'hermes_session_at=abc; Path=/'},
            );
          }
          return http.Response('{}', 200);
        }),
      );
      await client.getModelInfo();
      expect(seen.first.url.path, '/auth/password-login');
      for (final r in seen) {
        _expectHeaders(r, _cf);
      }
      expect(_header(seen.last, 'cookie'), 'hermes_session_at=abc');
    });

    test('exposes the proxy headers for the WebSocket upgrade', () {
      final client = DashboardClient(
        host: 'hermes.example.com',
        extraHeaders: _cf,
      );
      expect(client.webSocketHeaders, _cf);
      expect(DashboardClient(host: 'h').webSocketHeaders, isEmpty);
    });
  });

  test('AiSearchQueryRewriter sends proxy headers', () async {
    late http.BaseRequest seen;
    final rewriter = AiSearchQueryRewriter(
      baseUrl: 'https://hermes.example.com',
      apiKey: 'key',
      extraHeaders: _cf,
      httpClient: MockClient((request) async {
        seen = request;
        return http.Response('{"query":"q"}', 200);
      }),
    );
    try {
      await rewriter.rewrite(query: 'q', provider: 'p', model: 'm');
    } catch (_) {
      // The response shape is irrelevant; only the request headers matter.
    }
    _expectHeaders(seen, _cf);
    expect(_header(seen, 'authorization'), 'Bearer key');
  });

  group('WsClient', () {
    test('sends proxy headers on the WebSocket upgrade', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final upgrade = <String, String?>{};
      server.listen((request) async {
        for (final name in _cf.keys) {
          upgrade[name] = request.headers.value(name);
        }
        final socket = await WebSocketTransformer.upgrade(request);
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'method': 'event',
            'params': {'type': 'gateway.ready', 'payload': {}},
          }),
        );
      });

      final client = WsClient(
        'http://127.0.0.1:${server.port}',
        ticket: 't',
        extraHeaders: _cf,
      );
      addTearDown(client.close);
      try {
        await client.connect();
      } catch (_) {
        // Readiness handshake details are not under test.
      }
      expect(upgrade, _cf);
    });
  });

  group('ConfigBackup', () {
    SavedConnection withHeaders() => SavedConnection(
      id: 'c1',
      label: 'Home',
      host: 'hermes.example.com',
      port: 443,
      apiKey: 'key',
      extraHeaders: _cf,
    );

    test('round-trips proxy headers', () {
      final backup = ConfigBackup(
        createdAt: DateTime.utc(2026, 10, 2),
        appVersion: '1',
        connections: [withHeaders()],
        preferences: const {},
      );
      final restored = ConfigBackup.fromJson(
        jsonDecode(jsonEncode(backup.toJson())) as Map<String, dynamic>,
      );
      expect(restored.connections.single.extraHeaders, _cf);
    });

    test('backups made before proxy headers existed still restore', () {
      final json = ConfigBackup(
        createdAt: DateTime.utc(2026, 10, 2),
        appVersion: '1',
        connections: [withHeaders()],
        preferences: const {},
      ).toJson();
      for (final c in json['connections'] as List) {
        (c as Map).remove('extra_headers');
      }
      expect(
        ConfigBackup.fromJson(json).connections.single.extraHeaders,
        isEmpty,
      );
    });
  });
}
