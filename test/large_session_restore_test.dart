import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
  });

  testWidgets(
    'remote chat remains usable while bounded history hydration is pending',
    (tester) async {
      final httpClient = _DelayedMessagesHttpClient();
      addTearDown(httpClient.release);
      final apiClient = ApiClient(
        baseUrl: 'http://large-session.fixture',
        apiKey: 'fixture-key',
        httpClient: httpClient,
      );
      var submitted = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            connection: SavedConnection(
              id: 'large-session-fixture',
              label: 'Large session fixture',
              host: 'large-session.fixture',
              port: 8642,
              apiKey: 'fixture-key',
            ),
            session: const Session(
              id: 'stored-large-session',
              title: 'Large chat',
              model: 'fixture-model',
              source: 'api_server',
              messageCount: 4261,
              isActive: true,
              preview: '',
              startedAt: 1,
            ),
            testApiClient: apiClient,
            testRemotePromptSubmit:
                ({
                  required sessionId,
                  required text,
                  required onEvent,
                  required onSent,
                }) async {
                  submitted += 1;
                  onSent();
                },
            testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
          ),
        ),
      );
      await tester.pump();

      final messagesUri = await httpClient.messagesUri.future;
      expect(messagesUri.queryParameters, {'limit': '50', 'order': 'latest'});
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chat-message-composer')))
            .enabled,
        isTrue,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.attach_file),
            )
            .onPressed,
        isNotNull,
      );

      await tester.enterText(
        find.byKey(const Key('chat-message-composer')),
        'Prompt while history is loading',
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();

      expect(submitted, 1);
      expect(find.text('Prompt while history is loading'), findsOneWidget);

      httpClient.release();
      final refreshedMessagesUri = await httpClient.refreshedMessagesUri.future;
      expect(refreshedMessagesUri.queryParameters, {
        'limit': '50',
        'order': 'latest',
      });
      await tester.pumpAndSettle();

      expect(find.text('Stale transcript row'), findsNothing);
      expect(find.text('Existing transcript row'), findsOneWidget);
      expect(find.text('Prompt while history is loading'), findsOneWidget);
      expect(find.text('Fresh reply'), findsOneWidget);
    },
  );

  testWidgets(
    'failed remote send restores the pending authoritative transcript',
    (tester) async {
      final httpClient = _DelayedMessagesHttpClient(
        refreshedMessages: const [
          {'role': 'assistant', 'content': 'Existing transcript row'},
        ],
      );
      final failSubmit = Completer<void>();
      addTearDown(() {
        httpClient.release();
        if (!failSubmit.isCompleted) failSubmit.complete();
      });
      final apiClient = ApiClient(
        baseUrl: 'http://large-session.fixture',
        apiKey: 'test-key',
        httpClient: httpClient,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            connection: SavedConnection(
              id: 'large-session-fixture',
              label: 'Large session fixture',
              host: 'large-session.fixture',
              port: 8642,
              apiKey: 'test-key',
            ),
            session: const Session(
              id: 'stored-large-session',
              title: 'Large chat',
              model: 'fixture-model',
              source: 'api_server',
              messageCount: 4261,
              isActive: true,
              preview: '',
              startedAt: 1,
            ),
            testApiClient: apiClient,
            testRemotePromptSubmit:
                ({
                  required sessionId,
                  required text,
                  required onEvent,
                  required onSent,
                }) async {
                  onSent();
                  await failSubmit.future;
                  throw StateError('submit rejected');
                },
            testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
          ),
        ),
      );
      await tester.pump();
      await httpClient.messagesUri.future;

      await tester.enterText(
        find.byKey(const Key('chat-message-composer')),
        'Keep this draft',
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      httpClient.release();
      await httpClient.firstResponseReturned.future;
      await tester.pump();
      failSubmit.complete();
      await httpClient.refreshedMessagesUri.future;
      await tester.pumpAndSettle();

      expect(find.text('Stale transcript row'), findsNothing);
      expect(find.text('Existing transcript row'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chat-message-composer')))
            .controller
            ?.text,
        'Keep this draft',
      );
    },
  );

  testWidgets(
    'a newer turn prevents an older deferred refresh from replacing it',
    (tester) async {
      final httpClient = _MultiTurnRaceHttpClient();
      addTearDown(httpClient.releaseAll);
      var submitted = 0;
      final apiClient = ApiClient(
        baseUrl: 'http://large-session.fixture',
        apiKey: 'test-key',
        httpClient: httpClient,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            connection: SavedConnection(
              id: 'large-session-fixture',
              label: 'Large session fixture',
              host: 'large-session.fixture',
              port: 8642,
              apiKey: 'test-key',
            ),
            session: const Session(
              id: 'stored-large-session',
              title: 'Large chat',
              model: 'fixture-model',
              source: 'api_server',
              messageCount: 4261,
              isActive: true,
              preview: '',
              startedAt: 1,
            ),
            testApiClient: apiClient,
            testRemotePromptSubmit:
                ({
                  required sessionId,
                  required text,
                  required onEvent,
                  required onSent,
                }) async {
                  submitted += 1;
                  onSent();
                },
            testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
          ),
        ),
      );
      await tester.pump();
      await httpClient.firstMessagesUri.future;

      await tester.enterText(
        find.byKey(const Key('chat-message-composer')),
        'First turn',
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      httpClient.releaseFirst();
      await httpClient.deferredRefreshUri.future;

      await tester.enterText(
        find.byKey(const Key('chat-message-composer')),
        'Second turn',
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      expect(submitted, 2);

      httpClient.releaseDeferredRefresh();
      await httpClient.authoritativeRefreshUri.future;
      await tester.pumpAndSettle();

      expect(find.text('Pre-second-turn snapshot'), findsNothing);
      expect(find.text('Existing transcript row'), findsOneWidget);
      expect(find.text('First turn'), findsOneWidget);
      expect(find.text('Second turn'), findsOneWidget);
      expect(find.text('Second reply'), findsOneWidget);
    },
  );

  testWidgets('stopping a remote turn releases its deferred history refresh', (
    tester,
  ) async {
    final httpClient = _DelayedMessagesHttpClient(
      refreshedMessages: const [
        {'role': 'assistant', 'content': 'Existing transcript row'},
      ],
    );
    final submitGate = Completer<void>();
    addTearDown(() {
      httpClient.release();
      if (!submitGate.isCompleted) submitGate.complete();
    });
    final apiClient = ApiClient(
      baseUrl: 'http://large-session.fixture',
      apiKey: 'test-key',
      httpClient: httpClient,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          connection: SavedConnection(
            id: 'large-session-fixture',
            label: 'Large session fixture',
            host: 'large-session.fixture',
            port: 8642,
            apiKey: 'test-key',
          ),
          session: const Session(
            id: 'stored-large-session',
            title: 'Large chat',
            model: 'fixture-model',
            source: 'api_server',
            messageCount: 4261,
            isActive: true,
            preview: '',
            startedAt: 1,
          ),
          testApiClient: apiClient,
          testRemotePromptSubmit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) async {
                onSent();
                await submitGate.future;
              },
          testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        ),
      ),
    );
    await tester.pump();
    await httpClient.messagesUri.future;

    await tester.enterText(
      find.byKey(const Key('chat-message-composer')),
      'Stop this turn',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    httpClient.release();
    await httpClient.firstResponseReturned.future;
    await tester.pump();

    await tester.tap(find.byTooltip('Stop response'));
    await httpClient.refreshedMessagesUri.future;
    submitGate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Stale transcript row'), findsNothing);
    expect(find.text('Existing transcript row'), findsOneWidget);
  });
}

class _DelayedMessagesHttpClient extends http.BaseClient {
  _DelayedMessagesHttpClient({
    this.refreshedMessages = const [
      {'role': 'assistant', 'content': 'Existing transcript row'},
      {'role': 'user', 'content': 'Prompt while history is loading'},
      {'role': 'assistant', 'content': 'Fresh reply'},
    ],
  });

  final List<Map<String, dynamic>> refreshedMessages;
  final Completer<Uri> messagesUri = Completer<Uri>();
  final Completer<Uri> refreshedMessagesUri = Completer<Uri>();
  final Completer<void> firstResponseReturned = Completer<void>();
  final Completer<void> _released = Completer<void>();
  int _messageRequestCount = 0;

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      _messageRequestCount += 1;
      if (_messageRequestCount == 1) {
        if (!messagesUri.isCompleted) messagesUri.complete(request.url);
        await _released.future;
        if (!firstResponseReturned.isCompleted) {
          firstResponseReturned.complete();
        }
        return _jsonResponse([
          {'role': 'assistant', 'content': 'Stale transcript row'},
        ]);
      }
      if (!refreshedMessagesUri.isCompleted) {
        refreshedMessagesUri.complete(request.url);
      }
      return _jsonResponse(refreshedMessages);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'error': 'unexpected request'}))),
      404,
      headers: {'content-type': 'application/json'},
    );
  }

  http.StreamedResponse _jsonResponse(List<Map<String, dynamic>> messages) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'data': messages}))),
        200,
        headers: {'content-type': 'application/json'},
      );
}

class _MultiTurnRaceHttpClient extends http.BaseClient {
  final Completer<Uri> firstMessagesUri = Completer<Uri>();
  final Completer<Uri> deferredRefreshUri = Completer<Uri>();
  final Completer<Uri> authoritativeRefreshUri = Completer<Uri>();
  final Completer<void> _releaseFirst = Completer<void>();
  final Completer<void> _releaseDeferredRefresh = Completer<void>();
  int _messageRequestCount = 0;

  void releaseFirst() {
    if (!_releaseFirst.isCompleted) _releaseFirst.complete();
  }

  void releaseDeferredRefresh() {
    if (!_releaseDeferredRefresh.isCompleted) {
      _releaseDeferredRefresh.complete();
    }
  }

  void releaseAll() {
    releaseFirst();
    releaseDeferredRefresh();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      _messageRequestCount += 1;
      switch (_messageRequestCount) {
        case 1:
          firstMessagesUri.complete(request.url);
          await _releaseFirst.future;
          return _response([
            {'role': 'assistant', 'content': 'Initial stale snapshot'},
          ]);
        case 2:
          deferredRefreshUri.complete(request.url);
          await _releaseDeferredRefresh.future;
          return _response([
            {'role': 'assistant', 'content': 'Pre-second-turn snapshot'},
            {'role': 'user', 'content': 'First turn'},
          ]);
        default:
          if (!authoritativeRefreshUri.isCompleted) {
            authoritativeRefreshUri.complete(request.url);
          }
          return _response([
            {'role': 'assistant', 'content': 'Existing transcript row'},
            {'role': 'user', 'content': 'First turn'},
            {'role': 'assistant', 'content': 'First reply'},
            {'role': 'user', 'content': 'Second turn'},
            {'role': 'assistant', 'content': 'Second reply'},
          ]);
      }
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'error': 'unexpected request'}))),
      404,
      headers: {'content-type': 'application/json'},
    );
  }

  http.StreamedResponse _response(List<Map<String, dynamic>> messages) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'data': messages}))),
        200,
        headers: {'content-type': 'application/json'},
      );
}
