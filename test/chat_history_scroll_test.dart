import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/utils/chat_history_scroll.dart';
import 'package:hermes_android/core/widgets/chat_end_affordance.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
  });

  group('REST history', () {
    test('stays chronological and appends the current prompt exactly once', () {
      final history = buildRestChatHistory([
        {'role': 'user', 'content': 'oldest question'},
        {'role': 'assistant', 'content': 'middle answer'},
      ]);

      final requestMessages = GatewayChatClient.buildChatCompletionMessages(
        message: 'current question',
        history: history,
      );

      expect(requestMessages, [
        {'role': 'user', 'content': 'oldest question'},
        {'role': 'assistant', 'content': 'middle answer'},
        {'role': 'user', 'content': 'current question'},
      ]);
      expect(
        requestMessages.where(
          (message) => message['content'] == 'current question',
        ),
        hasLength(1),
      );
    });
  });

  group('scroll coordinator', () {
    test('normal opening exposes only one end alignment', () {
      final coordinator = ChatScrollCoordinator();

      final first = coordinator.consumeInitialEndAlignment();
      final second = coordinator.consumeInitialEndAlignment();

      expect(first, isA<ChatScrollTarget>());
      expect(second, isNull);
      expect(coordinator.initialEndAlignmentConsumed, isTrue);
    });

    for (final transport in const ['REST', 'Remote']) {
      test(
        '$transport completion follows only when streaming started at end',
        () {
          final following = ChatScrollCoordinator();
          following.beginStreaming(isNearEnd: true);
          expect(following.streamingContentChanged(), isNotNull);
          expect(following.endStreaming(), isNotNull);

          final readingHistory = ChatScrollCoordinator();
          readingHistory.beginStreaming(isNearEnd: false);
          expect(readingHistory.streamingContentChanged(), isNull);
          expect(readingHistory.endStreaming(), isNull);
        },
      );
    }

    test('direct user scrolling disables and can resume sticky follow', () {
      final coordinator = ChatScrollCoordinator();
      coordinator.beginStreaming(isNearEnd: true);

      coordinator.updateFromUserScroll(isNearEnd: false);
      expect(coordinator.streamingContentChanged(), isNull);

      coordinator.updateFromUserScroll(isNearEnd: true);
      expect(coordinator.streamingContentChanged(), isNotNull);
    });
  });

  group('end affordance controller', () {
    test('visibility uses distance while unread clears only at actual end', () {
      final controller = ChatEndAffordanceController(
        showThreshold: 200,
        endTolerance: 1,
      );

      controller.updatePosition(pixels: 400, maxScrollExtent: 1000);
      expect(controller.isVisible, isTrue);
      expect(controller.isAtEnd, isFalse);
      expect(controller.registerMaterializedMessage(willFollow: false), isTrue);
      expect(controller.newMessageCount, 1);

      controller.updatePosition(pixels: 850, maxScrollExtent: 1000);
      expect(controller.isVisible, isFalse);
      expect(controller.newMessageCount, 1);

      controller.updatePosition(pixels: 998, maxScrollExtent: 1000);
      expect(controller.isAtEnd, isFalse);
      expect(controller.newMessageCount, 1);

      controller.updatePosition(pixels: 999.5, maxScrollExtent: 1000);
      expect(controller.isAtEnd, isTrue);
      expect(controller.newMessageCount, 0);
    });

    test('followed messages never create transient unread state', () {
      final controller = ChatEndAffordanceController();
      controller.updatePosition(pixels: 500, maxScrollExtent: 1000);

      expect(controller.registerMaterializedMessage(willFollow: true), isFalse);
      expect(controller.newMessageCount, 0);
    });
  });

  group('ChatScreen integration', () {
    testWidgets(
      'composer stays overflow-free at font scale 200% on compact screens',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        for (final width in [320.0, 360.0]) {
          tester.view.physicalSize = Size(width, 640);
          await _pumpChat(
            tester,
            client: _ControlledChatHttpClient(const []),
            connectionId: 'compact-$width',
            sessionId: 'compact-$width',
            textScale: 2,
          );

          for (final label in const [
            'Add attachment',
            'Message',
            'Start voice input',
            'Spoken replies',
            'Send message',
          ]) {
            expect(find.bySemanticsLabel(label), findsOneWidget);
          }
          for (final tooltip in const [
            'Attach image or file',
            'Speak to Hermes',
            'Send',
          ]) {
            expect(tester.getSize(find.byTooltip(tooltip)), const Size(48, 48));
          }
          final messageField = tester.widget<TextField>(
            find.descendant(
              of: find.bySemanticsLabel('Message'),
              matching: find.byType(TextField),
            ),
          );
          expect(messageField.minLines, 1);
          expect(messageField.maxLines, 5);
          expect(messageField.decoration?.hintText, 'Message Hermes…');
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'opens a materialized long history at end after stable layout',
      (tester) async {
        final historyGate = Completer<void>();
        final client = _ControlledChatHttpClient(
          _longHistory(),
          historyGate: historyGate,
        );

        await _pumpChat(
          tester,
          client: client,
          connectionId: 'delayed-opening',
          sessionId: 'delayed-opening',
          settle: false,
        );
        await tester.pump();
        expect(find.byType(ListView), findsNothing);

        historyGate.complete();
        await tester.pumpAndSettle();

        final controller = _chatListController(tester);
        expect(controller.position.maxScrollExtent, greaterThan(0));
        expect(controller.position.pixels, controller.position.maxScrollExtent);
        expect(find.bySemanticsLabel('Go to end'), findsNothing);
      },
    );

    testWidgets('reopening ignores an old position and returns to end', (
      tester,
    ) async {
      final messages = _longHistory();
      await _pumpChat(
        tester,
        client: _ControlledChatHttpClient(messages),
        connectionId: 'no-restore',
        sessionId: 'no-restore',
      );
      final firstController = _chatListController(tester);
      firstController.jumpTo(320);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await _pumpChat(
        tester,
        client: _ControlledChatHttpClient(messages),
        connectionId: 'no-restore',
        sessionId: 'no-restore',
      );
      final reopenedController = _chatListController(tester);

      expect(
        reopenedController.position.pixels,
        reopenedController.position.maxScrollExtent,
      );
      expect(reopenedController.position.pixels, isNot(closeTo(320, 0.01)));
    });

    testWidgets('sends chronological REST history through the real screen', (
      tester,
    ) async {
      final initialMessages = [
        {'role': 'user', 'content': 'oldest question'},
        {'role': 'assistant', 'content': 'middle answer'},
      ];
      final client = _ControlledChatHttpClient(initialMessages);

      await _pumpChat(
        tester,
        client: client,
        connectionId: 'integration-history',
        sessionId: 'history-session',
      );
      await tester.enterText(find.byType(TextField), 'current question');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await client.postStarted.future;

      final request =
          jsonDecode(client.lastRequestBody!) as Map<String, dynamic>;
      expect(request['messages'], [
        {'role': 'user', 'content': 'oldest question'},
        {'role': 'assistant', 'content': 'middle answer'},
        {'role': 'user', 'content': 'current question'},
      ]);

      client.finish([
        ...initialMessages,
        {'role': 'user', 'content': 'current question'},
        {'role': 'assistant', 'content': 'final answer'},
      ]);
      await tester.pumpAndSettle();
    });

    testWidgets(
      'REST follows at end but preserves history through refresh and completion',
      (tester) async {
        final initialMessages = _longHistory();
        final client = _ControlledChatHttpClient(initialMessages);

        await _pumpChat(
          tester,
          client: client,
          connectionId: 'rest-scroll',
          sessionId: 'rest-scroll',
        );
        final controller = _chatListController(tester);
        expect(controller.position.pixels, controller.position.maxScrollExtent);

        controller.jumpTo(80);
        await tester.pump();
        await tester.tap(find.byTooltip('Chat actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Refresh'));
        await tester.pumpAndSettle();
        expect(controller.position.pixels, closeTo(80, 0.01));

        await tester.enterText(find.byType(TextField), 'stay in history');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await client.postStarted.future;

        client.emitToken('first materialized delta');
        await tester.pump();
        await tester.pump();
        final historyPosition = controller.position.pixels;
        expect(_indicatorText(tester), '1 new');
        expect(_goToEndSemantics(tester).value, '1 new message');

        client.emitToken(' and a second delta of the same message');
        await tester.pump();
        await tester.pump();
        expect(controller.position.pixels, closeTo(historyPosition, 0.01));
        expect(_indicatorText(tester), '1 new');

        client.finish([
          ...initialMessages,
          {'role': 'user', 'content': 'stay in history'},
          {
            'role': 'assistant',
            'content':
                'first materialized delta and a second delta of the same message',
          },
        ]);
        await tester.pumpAndSettle();
        expect(controller.position.pixels, closeTo(historyPosition, 0.01));
        expect(_indicatorText(tester), '1 new');

        await tester.tap(find.bySemanticsLabel('Go to end'));
        await tester.pumpAndSettle();
        expect(controller.position.pixels, controller.position.maxScrollExtent);
        expect(find.bySemanticsLabel('Go to end'), findsNothing);
      },
    );

    testWidgets(
      'REST streaming at end follows content growth before completion',
      (tester) async {
        final initialMessages = _longHistory();
        final client = _ControlledChatHttpClient(initialMessages);
        await _pumpChat(
          tester,
          client: client,
          connectionId: 'rest-follow',
          sessionId: 'rest-follow',
        );
        final controller = _chatListController(tester);

        await tester.enterText(find.byType(TextField), 'follow this');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await client.postStarted.future;
        client.emitToken(List.filled(60, 'growing response').join('\n'));
        await tester.pump();
        await tester.pump();

        expect(controller.position.pixels, controller.position.maxScrollExtent);
        expect(find.bySemanticsLabel('Go to end'), findsNothing);

        client.finish([
          ...initialMessages,
          {'role': 'user', 'content': 'follow this'},
          {'role': 'assistant', 'content': 'done'},
        ]);
        await tester.pumpAndSettle();
        expect(controller.position.pixels, controller.position.maxScrollExtent);
      },
    );

    testWidgets(
      'Remote completion preserves history and counts each new message once',
      (tester) async {
        final remote = _ControlledRemotePrompt();
        await _pumpChat(
          tester,
          client: _ControlledChatHttpClient(_longHistory()),
          connectionId: 'remote-history',
          sessionId: 'remote-history',
          remoteSubmit: remote.submit,
        );
        final controller = _chatListController(tester);
        controller.jumpTo(80);
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'remote response');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await remote.started.future;

        remote.emit('message.delta', {'text': 'first'});
        await tester.pump();
        await tester.pump();
        final historyPosition = controller.position.pixels;
        expect(_indicatorText(tester), '1 new');

        remote.emit('message.delta', {'text': ' second delta'});
        await tester.pump();
        await tester.pump();
        expect(_indicatorText(tester), '1 new');
        expect(controller.position.pixels, closeTo(historyPosition, 0.01));

        remote.emit('message.interim', {
          'text': ' interim',
          'already_streamed': false,
        });
        remote.emit('message.delta', {'text': 'second message'});
        await tester.pump();
        await tester.pump();
        expect(_indicatorText(tester), '2 new');
        expect(_goToEndSemantics(tester).value, '2 new messages');

        remote.emit('message.complete', {'rendered': 'second message final'});
        remote.finish();
        await tester.pumpAndSettle();
        expect(controller.position.pixels, closeTo(historyPosition, 0.01));
        expect(_indicatorText(tester), '2 new');

        await _dragToEnd(tester, controller);
        expect(controller.position.pixels, controller.position.maxScrollExtent);
        expect(find.bySemanticsLabel('Go to end'), findsNothing);
      },
    );

    testWidgets(
      'end action stays above compact composer, IME, and attachment panel',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 720);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        await _pumpChat(
          tester,
          client: _ControlledChatHttpClient(_longHistory()),
          connectionId: 'compact-end-action',
          sessionId: 'compact-end-action',
          viewInsets: const EdgeInsets.only(bottom: 220),
          initialDrafts: [_fixtureDraft('one'), _fixtureDraft('two')],
        );
        final controller = _chatListController(tester);
        controller.jumpTo(0);
        await tester.pumpAndSettle();

        final button = find.byKey(ChatEndAffordance.buttonKey);
        final inputBar = find.byKey(const Key('chat-input-bar'));
        expect(button, findsOneWidget);
        expect(find.bySemanticsLabel('Attachment drafts'), findsOneWidget);
        expect(
          tester.getRect(button).bottom,
          lessThanOrEqualTo(tester.getRect(inputBar).top),
        );
        expect(tester.getRect(button).bottom, lessThanOrEqualTo(500));
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'server file picker inserts an @file reference in the composer',
      (tester) async {
        await _pumpChat(
          tester,
          client: _ControlledChatHttpClient(const []),
          connectionId: 'server-file',
          sessionId: 'server-file',
          serverFilePicker: () async => '/srv/project/README.md',
        );

        await tester.tap(find.bySemanticsLabel('Add attachment'));
        await tester.pumpAndSettle();
        expect(find.text('Browse server files'), findsOneWidget);

        await tester.tap(find.text('Browse server files'));
        await tester.pumpAndSettle();

        final composer = tester.widget<TextField>(find.byType(TextField));
        expect(composer.controller!.text, '@file /srv/project/README.md ');
      },
    );
  });
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required _ControlledChatHttpClient client,
  required String connectionId,
  required String sessionId,
  double textScale = 1,
  EdgeInsets viewInsets = EdgeInsets.zero,
  TestRemotePromptSubmit? remoteSubmit,
  Future<String?> Function()? serverFilePicker,
  List<AttachmentDraft> initialDrafts = const [],
  bool settle = true,
}) async {
  final apiClient = ApiClient(
    baseUrl: 'http://fixture.example',
    apiKey: 'synthetic-test-key',
    httpClient: client,
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: viewInsets,
        ),
        child: child!,
      ),
      home: ChatScreen(
        connection: SavedConnection(
          id: connectionId,
          label: 'Fixture',
          host: 'fixture.example',
          port: 8642,
          apiKey: 'synthetic-test-key',
        ),
        session: Session(
          id: sessionId,
          title: 'Fixture chat',
          model: 'fixture-model',
          source: 'test',
          messageCount: client.serverMessages.length,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        testApiClient: apiClient,
        testRemotePromptSubmit: remoteSubmit,
        testServerFilePicker: serverFilePicker,
        testInitialAttachmentDrafts: initialDrafts,
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

ScrollController _chatListController(WidgetTester tester) {
  return tester.widget<ListView>(find.byType(ListView).first).controller!;
}

String? _indicatorText(WidgetTester tester) {
  return tester.widget<Text>(find.byKey(ChatEndAffordance.countKey)).data;
}

SemanticsNode _goToEndSemantics(WidgetTester tester) {
  return tester.getSemantics(find.bySemanticsLabel('Go to end'));
}

Future<void> _dragToEnd(
  WidgetTester tester,
  ScrollController controller,
) async {
  for (
    var attempt = 0;
    attempt < 12 &&
        controller.position.pixels < controller.position.maxScrollExtent - 1;
    attempt++
  ) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
  }
}

AttachmentDraft _fixtureDraft(String id) {
  return AttachmentDraft(
    id: id,
    cachedPath: 'C:/synthetic/$id.txt',
    name: '$id.txt',
    byteLength: 4,
    mediaType: 'text/plain',
    kind: AttachmentDraftKind.genericFile,
  );
}

List<Map<String, dynamic>> _longHistory() {
  return [
    for (var index = 0; index < 24; index++)
      {
        'role': index.isEven ? 'user' : 'assistant',
        'content':
            'message $index\n${List.filled(5, 'history line').join('\n')}',
      },
  ];
}

class _ControlledRemotePrompt {
  Completer<void> started = Completer<void>();
  Completer<void>? _completion;
  StreamCallback? _onEvent;

  Future<void> submit({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
    required void Function() onSent,
  }) async {
    onSent();
    _onEvent = onEvent;
    _completion = Completer<void>();
    if (!started.isCompleted) started.complete();
    await _completion!.future;
  }

  void emit(String type, Map<String, dynamic> data) {
    _onEvent!(StreamEvent(type: type, data: data));
  }

  void finish() {
    _completion!.complete();
  }
}

class _ControlledChatHttpClient extends http.BaseClient {
  List<Map<String, dynamic>> serverMessages;
  final Completer<void> postStarted = Completer<void>();
  final Completer<void>? historyGate;
  StreamController<List<int>>? _completionStream;
  String? lastRequestBody;

  _ControlledChatHttpClient(
    List<Map<String, dynamic>> messages, {
    this.historyGate,
  }) : serverMessages = List<Map<String, dynamic>>.from(messages);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      await historyGate?.future;
      return _jsonResponse({'data': serverMessages});
    }
    if (request.method == 'POST' &&
        request.url.path.endsWith('/v1/chat/completions')) {
      lastRequestBody = (request as http.Request).body;
      _completionStream = StreamController<List<int>>();
      if (!postStarted.isCompleted) postStarted.complete();
      return http.StreamedResponse(
        _completionStream!.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }
    return _jsonResponse({'error': 'unexpected request'}, statusCode: 404);
  }

  void emitToken(String token) {
    _completionStream!.add(
      utf8.encode(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': token},
            },
          ],
        })}\n\n',
      ),
    );
  }

  void finish(List<Map<String, dynamic>> finalMessages) {
    serverMessages = List<Map<String, dynamic>>.from(finalMessages);
    _completionStream!
      ..add(utf8.encode('data: [DONE]\n\n'))
      ..close();
  }

  http.StreamedResponse _jsonResponse(Object body, {int statusCode = 200}) {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}
