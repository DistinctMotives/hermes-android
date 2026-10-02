import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;

/// An http client whose responses never arrive.
///
/// This simulates the real-world failure the timeout protects against: the
/// server answered (or closed) a keep-alive socket, the client never notices,
/// and the request would otherwise hang forever.
class _HangingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Completer<http.StreamedResponse>().future;
  }
}

void main() {
  group('ApiClient.getSessions', () {
    test('fails fast when the gateway never answers', () async {
      final client = ApiClient(
        baseUrl: 'http://fixture.local',
        apiKey: 'key',
        httpClient: _HangingHttpClient(),
      );

      await expectLater(
        client.getSessions(timeout: const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('parses the gateway session payload', () async {
      final client = ApiClient(
        baseUrl: 'http://fixture.local',
        apiKey: 'key',
        httpClient: _JsonHttpClient(
          body: '''
          {"data":[{"id":"s1","title":"Daily driver","model":"gpt-oss-20b",
                    "source":"gateway","message_count":2,"is_active":true,
                    "preview":"hello","started_at":1750000000}]}
          ''',
        ),
      );

      final sessions = await client.getSessions();
      expect(sessions, hasLength(1));
      expect(sessions.single.title, 'Daily driver');
    });
  });
}

class _JsonHttpClient extends http.BaseClient {
  final String body;
  _JsonHttpClient({required this.body});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(Stream.value(body.codeUnits), 200);
  }
}
