import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/session_search_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

SessionSearchClient clientReturning(
  http.Response Function(http.Request request) handler, {
  Future<Map<String, String>> Function()? headers,
}) {
  return SessionSearchClient(
    baseUrl: 'http://dashboard.example:9119',
    headers: headers ?? () async => const {'Cookie': 'session=abc'},
    httpClient: MockClient((request) async => handler(request)),
  );
}

http.Response jsonOk(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

void main() {
  test(
    'returns no results for a blank query without calling the server',
    () async {
      var called = false;
      final client = clientReturning((_) {
        called = true;
        return jsonOk({'results': []});
      });

      expect(await client.search('   '), isEmpty);
      expect(called, isFalse, reason: 'a blank query must not hit the network');
    },
  );

  test('sends the query and clamped limit to the dashboard endpoint', () async {
    late Uri captured;
    final client = clientReturning((request) {
      captured = request.url;
      return jsonOk({'results': []});
    });

    await client.search('tuk tuk', limit: 5000);

    expect(captured.path, '/api/sessions/search');
    expect(captured.queryParameters['q'], 'tuk tuk');
    expect(
      captured.queryParameters['limit'],
      '${SessionSearchClient.maxLimit}',
      reason: 'an oversized limit must be clamped, not forwarded',
    );
  });

  test('forwards the supplied auth headers', () async {
    late Map<String, String> captured;
    final client = clientReturning((request) {
      captured = request.headers;
      return jsonOk({'results': []});
    }, headers: () async => const {'Cookie': 'hermes_session_at=xyz'});

    await client.search('anything');

    expect(captured['Cookie'], 'hermes_session_at=xyz');
  });

  test('maps a result row into a session plus its matching excerpt', () async {
    final client = clientReturning(
      (_) => jsonOk({
        'results': [
          {
            'session_id': '20260823_1200_abc',
            'title': 'Electric tuk-tuk build',
            'snippet': 'the [tuk-tuk] prototype in Ethiopia',
            'role': 'user',
            'source': 'discord',
            'model': 'claude-opus-5',
            'session_started': 1787509770.0,
          },
        ],
      }),
    );

    final hits = await client.search('tuk');

    expect(hits, hasLength(1));
    expect(hits.single.session.id, '20260823_1200_abc');
    expect(hits.single.session.title, 'Electric tuk-tuk build');
    expect(hits.single.snippet, 'the [tuk-tuk] prototype in Ethiopia');
    expect(hits.single.role, 'user');
  });

  test('falls back to the id field when the row omits session_id', () async {
    final client = clientReturning(
      (_) => jsonOk({
        'results': [
          {'id': 'session-from-id-field', 'title': 'Legacy row'},
        ],
      }),
    );

    final hits = await client.search('legacy');

    expect(hits.single.session.id, 'session-from-id-field');
  });

  test('tolerates a sparse row instead of crashing the list', () async {
    final client = clientReturning(
      (_) => jsonOk({
        'results': [
          {'session_id': 'bare'},
        ],
      }),
    );

    final hits = await client.search('bare');

    expect(hits.single.session.id, 'bare');
    expect(hits.single.snippet, isEmpty);
    expect(hits.single.role, isNull);
  });

  test('explains an auth failure instead of reporting zero matches', () async {
    final client = clientReturning((_) => http.Response('Unauthorized', 401));

    await expectLater(
      client.search('anything'),
      throwsA(
        isA<SessionSearchException>().having(
          (e) => e.message,
          'message',
          contains('credentials'),
        ),
      ),
    );
  });

  test('explains that an older dashboard lacks the endpoint', () async {
    final client = clientReturning((_) => http.Response('Not Found', 404));

    await expectLater(
      client.search('anything'),
      throwsA(
        isA<SessionSearchException>().having(
          (e) => e.message,
          'message',
          contains('does not expose session search'),
        ),
      ),
    );
  });

  test('surfaces an unreachable dashboard as a search failure', () async {
    final client = SessionSearchClient(
      baseUrl: 'http://dashboard.example:9119',
      headers: () async => const {},
      httpClient: MockClient((_) async => throw const SocketExceptionStub()),
    );

    await expectLater(
      client.search('anything'),
      throwsA(isA<SessionSearchException>()),
    );
  });

  test(
    'rejects a malformed body rather than showing an empty result',
    () async {
      final client = clientReturning((_) => http.Response('not json', 200));

      await expectLater(
        client.search('anything'),
        throwsA(
          isA<SessionSearchException>().having(
            (e) => e.message,
            'message',
            contains('malformed'),
          ),
        ),
      );
    },
  );

  test('returns empty when the payload carries no results list', () async {
    final client = clientReturning((_) => jsonOk({'ok': true}));

    expect(await client.search('anything'), isEmpty);
  });
}

/// Stand-in for a transport failure; MockClient cannot raise a real
/// SocketException without a live socket.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => 'connection refused';
}
