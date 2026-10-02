import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/connection.dart';
import 'desktop_gateway_client.dart';
import 'gateway_turn_coordinator.dart';
import 'gateway_turn_journal.dart';
import 'gateway_turn_recovery.dart';

typedef GatewayTurnApplicationSessionFactory =
    GatewayTurnApplicationSession Function(SavedConnection connection);
typedef GatewayTurnJournalFactory = GatewayTurnJournal Function();

/// Connection-scoped recovery surface retained by the application owner.
abstract interface class GatewayTurnApplicationSession {
  /// Routes interactive server requests for one mounted chat screen.
  ///
  /// The application session outlives individual routes, so listeners are
  /// keyed by local session id rather than replacing one connection-wide
  /// callback whenever the user opens another chat.
  Object setAsyncEventListener(
    String localSessionId,
    DesktopAsyncEventCallback listener,
  );

  void removeAsyncEventListener(String localSessionId, Object registration);

  /// Responds only when this recovery session owns the request.
  Future<bool> tryRespondToApproval({
    required String sessionId,
    required String choice,
    String? requestId,
  });

  Future<bool> tryRespondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
  });

  Future<bool> tryRespondToSudo({
    required String requestId,
    required String password,
  });

  Future<bool> tryRespondToSecret({
    required String requestId,
    required String value,
  });

  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String localSessionId,
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  });

  Future<void> detachAttachments({
    required String localSessionId,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  });

  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  });

  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  });

  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  });

  Future<void> close();

  set onTurnSettled(GatewayTurnSettledCallback? callback);

  /// Called when `session.open` first binds a draft session to its stored id.
  set onSessionBound(GatewayTurnSessionBoundCallback? callback);
}

/// Owns recovery registries above screen and Navigator lifetimes.
///
/// A screen may detach its callbacks when disposed, but this owner keeps the
/// coordinator, socket, and process-local recovery authority alive until the
/// whole application is disposed. A changed connection configuration receives
/// a distinct scope without retaining plaintext credentials in the key.
class GatewayTurnApplicationController {
  final GatewayTurnApplicationSessionFactory _sessionFactory;
  final Map<String, GatewayTurnApplicationSession> _sessions = {};
  bool _closed = false;

  GatewayTurnApplicationController({
    GatewayTurnApplicationSessionFactory? sessionFactory,
    GatewayTurnJournalFactory? journalFactory,
  }) : _sessionFactory =
           sessionFactory ??
           ((connection) => _CoordinatorGatewayTurnApplicationSession(
             DesktopGatewayClient.fromConnection(connection),
             journal: journalFactory?.call(),
           ));

  GatewayTurnApplicationSession sessionFor(SavedConnection connection) {
    if (_closed) throw StateError('Gateway turn application owner is closed.');
    final key = _connectionScopeKey(connection);
    return _sessions.putIfAbsent(key, () => _sessionFactory(connection));
  }

  int get retainedSessionCount => _sessions.length;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    Object? firstError;
    StackTrace? firstStack;
    for (final session in sessions) {
      try {
        await session.close();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }
}

class _CoordinatorGatewayTurnApplicationSession
    implements GatewayTurnApplicationSession {
  final DesktopGatewayClient _client;
  final Map<String, _ApplicationAsyncEventRegistration> _asyncEventListeners =
      {};
  late final GatewayTurnCoordinatorRegistry _registry;
  bool _closed = false;

  _CoordinatorGatewayTurnApplicationSession(
    this._client, {
    GatewayTurnJournal? journal,
  }) {
    _registry = _client.enableTurnRecoveryCoordinator(journal: journal);
  }

  void _syncAsyncEventDispatcher() {
    if (_asyncEventListeners.isEmpty) {
      _client.setAsyncEventListener(null);
      return;
    }
    _client.setAsyncEventListener((localSessionId, event) {
      _asyncEventListeners[localSessionId]?.listener.call(
        localSessionId,
        event,
      );
    }, acceptsSession: _asyncEventListeners.containsKey);
  }

  void _requireOpen() {
    if (_closed) {
      throw StateError('Gateway turn application session is closed.');
    }
  }

  @override
  Object setAsyncEventListener(
    String localSessionId,
    DesktopAsyncEventCallback listener,
  ) {
    _requireOpen();
    final token = Object();
    _asyncEventListeners[localSessionId] = _ApplicationAsyncEventRegistration(
      token,
      listener,
    );
    _syncAsyncEventDispatcher();
    _client.replayServerRequestsForSession(localSessionId);
    return token;
  }

  @override
  void removeAsyncEventListener(String localSessionId, Object registration) {
    _requireOpen();
    final current = _asyncEventListeners[localSessionId];
    if (current == null || !identical(current.token, registration)) return;
    _asyncEventListeners.remove(localSessionId);
    _client.rejectServerRequestsForSession(localSessionId);
    _syncAsyncEventDispatcher();
  }

  @override
  Future<bool> tryRespondToApproval({
    required String sessionId,
    required String choice,
    String? requestId,
  }) async {
    _requireOpen();
    if (requestId == null ||
        !_client.ownsServerRequest(requestId, 'approval')) {
      return false;
    }
    await _client.respondToApproval(
      sessionId: sessionId,
      choice: choice,
      serverRequestId: requestId,
    );
    return true;
  }

  @override
  Future<bool> tryRespondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
  }) async {
    _requireOpen();
    if (!_client.ownsServerRequest(requestId, 'clarify')) return false;
    await _client.respondToClarify(
      requestId: requestId,
      answer: answer,
      questionId: questionId,
    );
    return true;
  }

  @override
  Future<bool> tryRespondToSudo({
    required String requestId,
    required String password,
  }) async {
    _requireOpen();
    if (!_client.ownsServerRequest(requestId, 'sudo')) return false;
    await _client.respondToSudo(requestId: requestId, password: password);
    return true;
  }

  @override
  Future<bool> tryRespondToSecret({
    required String requestId,
    required String value,
  }) async {
    _requireOpen();
    if (!_client.ownsServerRequest(requestId, 'secret')) return false;
    await _client.respondToSecret(requestId: requestId, value: value);
    return true;
  }

  @override
  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String localSessionId,
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  }) {
    _requireOpen();
    return _registry.stageAttachment(
      localSessionId: localSessionId,
      clientAttachmentId: clientAttachmentId,
      name: name,
      dataUrl: dataUrl,
      byteLength: byteLength,
      mediaType: mediaType,
      kind: kind,
    );
  }

  @override
  Future<void> detachAttachments({
    required String localSessionId,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  }) {
    _requireOpen();
    return _registry.detachAttachments(
      localSessionId: localSessionId,
      attachments: attachments,
    );
  }

  @override
  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  }) {
    _requireOpen();
    return _registry.submit(
      localSessionId: localSessionId,
      text: text,
      attachments: attachments,
      onState: onState,
    );
  }

  @override
  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  }) {
    _requireOpen();
    return _registry.recoverPending(localSessionId, onState: onState);
  }

  @override
  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  }) {
    _requireOpen();
    return _registry.interrupt(
      localSessionId: localSessionId,
      clientTurnId: clientTurnId,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _asyncEventListeners.clear();
    _client.setAsyncEventListener(null);
    try {
      await _registry.closeAll();
    } finally {
      _client.close();
    }
  }

  @override
  set onTurnSettled(GatewayTurnSettledCallback? callback) {
    _registry.onTurnSettled = callback;
  }

  @override
  set onSessionBound(GatewayTurnSessionBoundCallback? callback) {
    _registry.onSessionBound = callback;
  }
}

class _ApplicationAsyncEventRegistration {
  final Object token;
  final DesktopAsyncEventCallback listener;

  const _ApplicationAsyncEventRegistration(this.token, this.listener);
}

String _connectionScopeKey(SavedConnection connection) {
  final credentialDigest = sha256
      .convert(
        utf8.encode(
          '${connection.apiKey}\u0000${connection.dashboardPassword ?? ''}',
        ),
      )
      .toString();
  return sha256
      .convert(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'id': connection.id,
            'desktop_gateway_url': connection.desktopGatewayUrl,
            'dashboard_username': connection.dashboardUsername,
            'dashboard_prefix': connection.dashboardPrefix,
            'dashboard_port': connection.dashboardPort,
            'dashboard_proxied': connection.dashboardProxied,
            'credential_digest': credentialDigest,
          }),
        ),
      )
      .toString();
}
