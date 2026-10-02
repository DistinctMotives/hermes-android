import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_turn_contract.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/recording_turn_notification_sink.dart';

const _clientTurnId = '123e4567-e89b-42d3-a456-426614174000';

/// Wires the notification path ChatScreen actually uses when a turn settles.
///
/// The TurnNotificationService unit tests prove the service posts what it is
/// asked to post. These tests prove ChatScreen asks — the seam between "a turn
/// finished while the app was backgrounded" and "Android shows something" had
/// no coverage, so a regression there would ship silently.
void main() {
  late RecordingTurnNotificationSink sink;
  late TurnNotificationService notifications;
  late _CallbackCapturingTurnSession turnSession;

  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    sink = RecordingTurnNotificationSink();
    notifications = TurnNotificationService(sink: sink);
    turnSession = _CallbackCapturingTurnSession();
  });

  Future<void> pumpChat(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          connection: SavedConnection(
            id: 'notif-fixture',
            label: 'Notification fixture',
            host: 'notif.fixture',
            port: 8642,
            apiKey: '',
          ),
          session: const Session(
            id: 'notif-session',
            title: 'Roadmap',
            model: 'fixture-model',
            source: 'test',
            messageCount: 0,
            isActive: true,
            preview: '',
            startedAt: 1,
          ),
          testApiClient: ApiClient(
            baseUrl: 'http://notif.fixture',
            apiKey: '',
            httpClient: _EmptyChatHttpClient(),
          ),
          testTurnApplicationSession: turnSession,
          testTurnNotifications: notifications,
          testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Android walks the full lifecycle chain; skipping a step trips Flutter's
  /// transition assertions, so tests must move the same way a device does.
  void background(WidgetTester tester) {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void foreground(WidgetTester tester) {
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  testWidgets('a turn settling in the background posts a notification', (
    tester,
  ) async {
    await pumpChat(tester);

    // Android moved the app off screen.
    background(tester);
    await tester.pump();

    turnSession.settle(_completedState());
    await tester.pump();

    expect(sink.shown, hasLength(1));
    // The session title tells the user which chat answered.
    expect(sink.shown.single.body, contains('Roadmap'));
  });

  testWidgets('a turn settling in the foreground posts nothing', (
    tester,
  ) async {
    await pumpChat(tester);

    // App is on screen: the user already watches the answer arrive.
    turnSession.settle(_completedState());
    await tester.pump();

    expect(sink.shown, isEmpty);
  });

  testWidgets('returning to the app clears the pending notifications', (
    tester,
  ) async {
    await pumpChat(tester);

    background(tester);
    await tester.pump();
    turnSession.settle(_completedState());
    await tester.pump();

    foreground(tester);
    await tester.pump();

    expect(sink.cancelAllCount, greaterThanOrEqualTo(1));
  });
}

GatewayTurnRecoveryState _completedState() =>
    GatewayTurnRecoveryState.initial(
      clientTurnId: _clientTurnId,
    ).markSubmissionStarted().applyAck(
      const GatewayTurnAck(
        clientTurnId: _clientTurnId,
        turnId: 'server-turn',
        status: GatewayRecoveryTurnStatus.completed,
        lastSeq: 4,
        created: false,
      ),
    );

/// Turn session that keeps the settle callback ChatScreen registers, so a test
/// can fire it the way the real gateway would.
class _CallbackCapturingTurnSession implements GatewayTurnApplicationSession {
  GatewayTurnSettledCallback? _onTurnSettled;

  @override
  Object setAsyncEventListener(
    String localSessionId,
    DesktopAsyncEventCallback listener,
  ) => Object();

  @override
  void removeAsyncEventListener(String localSessionId, Object registration) {}

  @override
  Future<bool> tryRespondToApproval({
    required String sessionId,
    required String choice,
    String? requestId,
  }) async => false;

  @override
  Future<bool> tryRespondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
  }) async => false;

  @override
  Future<bool> tryRespondToSudo({
    required String requestId,
    required String password,
  }) async => false;

  @override
  Future<bool> tryRespondToSecret({
    required String requestId,
    required String value,
  }) async => false;

  void settle(GatewayTurnRecoveryState state) => _onTurnSettled?.call(state);

  @override
  set onTurnSettled(GatewayTurnSettledCallback? callback) {
    _onTurnSettled = callback;
  }

  @override
  set onSessionBound(GatewayTurnSessionBoundCallback? callback) {}

  @override
  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  }) async => const <GatewayTurnRecoveryState>[];

  @override
  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async {}

  @override
  Future<void> detachAttachments({
    required String localSessionId,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  }) => throw UnimplementedError();

  @override
  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  }) => throw UnimplementedError();

  @override
  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String localSessionId,
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  }) => throw UnimplementedError();
}

class _EmptyChatHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'data': <Object>[]}))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'error': 'unexpected request'}))),
      404,
      headers: {'content-type': 'application/json'},
    );
  }
}
