import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/ai_search_query_rewriter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'calls the lightweight endpoint with selected provider and model',
    () async {
      late http.Request captured;
      final client = AiSearchQueryRewriter(
        baseUrl: 'http://gateway.example:8642/',
        apiKey: 'secret-key',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'query': 'C-MAY Ethiopia',
              'provider': 'nvidia',
              'model': 'openai/gpt-oss-20b',
              'usage': {
                'input_tokens': 114,
                'output_tokens': 39,
                'total_tokens': 153,
              },
            }),
            200,
          );
        }),
      );

      final rewritten = await client.rewrite(
        query: 'where did we discuss the electric tuk-tuk project?',
        provider: 'nvidia',
        model: 'openai/gpt-oss-20b',
      );

      expect(rewritten, 'C-MAY Ethiopia');
      expect(captured.url.path, '/v1/search/rewrite');
      expect(captured.headers['Authorization'], 'Bearer secret-key');
      expect(captured.headers, isNot(contains('X-Hermes-Session-Id')));
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body, {
        'query': 'where did we discuss the electric tuk-tuk project?',
        'provider': 'nvidia',
        'model': 'openai/gpt-oss-20b',
      });
    },
  );

  test('blank input never calls Hermes', () async {
    var called = false;
    final client = AiSearchQueryRewriter(
      baseUrl: 'http://gateway.example:8642',
      apiKey: 'key',
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    expect(
      await client.rewrite(query: ' ', provider: 'nvidia', model: 'model'),
      isEmpty,
    );
    expect(called, isFalse);
  });

  test('requires a selected provider and model', () async {
    final client = AiSearchQueryRewriter(
      baseUrl: 'http://gateway.example:8642',
      apiKey: 'key',
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );

    await expectLater(
      client.rewrite(query: 'find this', provider: '', model: ''),
      throwsA(
        isA<AiSearchRewriteException>().having(
          (e) => e.message,
          'message',
          contains('Choose an AI search model'),
        ),
      ),
    );
  });

  test(
    'falls back to the original query when AI rewrite is unavailable',
    () async {
      for (final status in [404, 429, 503]) {
        final client = AiSearchQueryRewriter(
          baseUrl: 'http://gateway.example:8642',
          apiKey: 'test-key',
          httpClient: MockClient(
            (_) async => http.Response('Unavailable', status),
          ),
        );

        expect(
          await client.rewrite(
            query: 'find this',
            provider: 'nvidia',
            model: 'model',
          ),
          'find this',
          reason: 'HTTP $status should degrade to ordinary full-text search',
        );
      }
    },
  );

  test('surfaces auth and server error messages', () async {
    final authClient = AiSearchQueryRewriter(
      baseUrl: 'http://gateway.example:8642',
      apiKey: 'bad',
      httpClient: MockClient((_) async => http.Response('Unauthorized', 401)),
    );
    await expectLater(
      authClient.rewrite(query: 'x', provider: 'p', model: 'm'),
      throwsA(
        isA<AiSearchRewriteException>().having(
          (e) => e.message,
          'message',
          contains('API key'),
        ),
      ),
    );

    final serverClient = AiSearchQueryRewriter(
      baseUrl: 'http://gateway.example:8642',
      apiKey: 'key',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'The selected provider is unavailable.'},
          }),
          400,
        ),
      ),
    );
    await expectLater(
      serverClient.rewrite(query: 'x', provider: 'p', model: 'm'),
      throwsA(
        isA<AiSearchRewriteException>().having(
          (e) => e.message,
          'message',
          'The selected provider is unavailable.',
        ),
      ),
    );
  });

  test('rejects a malformed success response', () async {
    final client = AiSearchQueryRewriter(
      baseUrl: 'http://gateway.example:8642',
      apiKey: 'key',
      httpClient: MockClient((_) async => http.Response('not json', 200)),
    );

    await expectLater(
      client.rewrite(query: 'x', provider: 'p', model: 'm'),
      throwsA(
        isA<AiSearchRewriteException>().having(
          (e) => e.message,
          'message',
          contains('malformed'),
        ),
      ),
    );
  });

  test('normalizes a gateway path prefix exactly once', () async {
    late Uri captured;
    final client = AiSearchQueryRewriter(
      baseUrl: 'https://gateway.example/',
      pathPrefix: '/profile/carlos/',
      apiKey: 'key',
      httpClient: MockClient((request) async {
        captured = request.url;
        return http.Response(jsonEncode({'query': 'Hermes'}), 200);
      }),
    );

    await client.rewrite(query: 'agent', provider: 'p', model: 'm');

    expect(captured.path, '/profile/carlos/v1/search/rewrite');
  });
}
