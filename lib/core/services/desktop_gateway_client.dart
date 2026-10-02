import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'capability_registry.dart';
import 'connection_manager.dart';
import 'gateway_turn_coordinator.dart';
import 'gateway_turn_journal.dart';
import 'projects_gateway_client.dart';
import 'ws_client.dart';

typedef DesktopAsyncEventCallback =
    void Function(String mobileSessionId, StreamEvent event);
typedef DesktopAsyncEventSessionPredicate = bool Function(String sessionId);
typedef DesktopConnectionCallback =
    void Function(DesktopConnectionState connectionState);

enum DesktopConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Authenticated JSON-RPC transport for a Hermes Desktop remote gateway.
///
/// The mobile OpenAI-compatible endpoint remains available for legacy
/// profiles. When a connection supplies [SavedConnection.desktopGatewayUrl],
/// chat writes and interactive events use this one Desktop session transport.
class DesktopGatewayClient {
  static int _nextServerRequestNamespace = 1;

  final int _serverRequestNamespace = _nextServerRequestNamespace++;
  final String _connectionId;
  final String _baseUrl;
  final DashboardClient _dashboard;

  /// Hermes profile the gateway socket should run chats under, or null to
  /// let the server use its own. See [SavedConnection.gatewayProfile].
  final String? _gatewayProfile;
  WsClient? _ws;
  Future<WsClient>? _socketInFlight;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  final Map<String, Future<_DesktopGatewayBinding>> _bindingInFlight = {};
  bool _closed = false;
  final Map<String, String> _gatewaySessionIds = {};
  final Map<String, String> _storedSessionIds = {};
  final Map<String, String> _workingDirectories = {};
  final Map<String, GatewayServerRequest> _serverRequests = {};
  final Map<String, WsClient> _serverRequestClients = {};
  final Map<String, String> _serverRequestMobileSessionIds = {};
  final Map<String, StreamEvent> _serverRequestEvents = {};
  final Map<WsClient, int> _serverRequestClientOrdinals = Map.identity();
  int _nextServerRequestClientOrdinal = 1;
  final Map<String, Set<String>> _serverClarifyRemaining = {};
  final Map<String, String> _serverApprovalByMobileSession = {};
  DesktopAsyncEventCallback? _asyncEventListener;
  DesktopAsyncEventSessionPredicate? _asyncEventAcceptsSession;
  DesktopConnectionCallback? _connectionListener;
  GatewayTurnCoordinatorRegistry? _turnCoordinatorRegistry;
  ProjectsGatewayClient? _projects;
  final CapabilityRegistry _capabilities = CapabilityRegistry();

  static const _asyncEventTypes = {
    'background.complete',
    'review.summary',
    'notification.show',
    'notification.clear',
    'subagent.spawn_requested',
    'subagent.start',
    'subagent.thinking',
    'subagent.tool',
    'subagent.progress',
    'subagent.complete',
    // A detached legacy turn can settle after its prompt.submit listener was
    // rejected by socket close. Route its terminal frame to ChatScreen's
    // recovery controller; live turns ignore this duplicate async delivery.
    'message.complete',
    'turn.end',
    'turn.error',
    'error',
    'request.cancel',
  };

  DesktopGatewayClient._({
    required this._connectionId,
    required this._baseUrl,
    required this._dashboard,
    this._gatewayProfile,
  });

  /// The canonical gateway origin for [connection].
  ///
  /// Extracted so the recovery-journal scope can be derived without opening a
  /// transport: an omitted default port and an explicit one must resolve to
  /// the same string, or the same gateway would be recorded under two scopes.
  static String normalizedGatewayBaseUrl(SavedConnection connection) {
    final override = connection.desktopGatewayUrl?.trim() ?? '';
    final overrideUri = override.isEmpty
        ? null
        : Uri.tryParse(
            override.contains('://') ? override : 'https://$override',
          );
    final isDistinctOverride =
        overrideUri != null &&
        overrideUri.host.isNotEmpty &&
        overrideUri.host.toLowerCase() != connection.host.toLowerCase();
    final raw = isDistinctOverride
        ? override
        : SavedConnection.joinBaseUrl(
            '${connection.useHttps ? 'https' : 'http'}://'
            '${connection.host}:${connection.dashboardPort}',
            connection.dashboardPrefix ?? '',
          );
    final normalized = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError('Desktop Gateway URL must be an http(s) URL');
    }
    final baseUri = uri.replace(query: '', fragment: '');
    final pathPrefix = baseUri.path == '/' ? '' : baseUri.path;
    final port = baseUri.hasPort
        ? baseUri.port
        : baseUri.scheme == 'https'
        ? 443
        : 80;
    return SavedConnection.joinBaseUrl(
      '${baseUri.scheme}://${baseUri.host}:$port',
      pathPrefix,
    );
  }

  static String _endpointDigest(String baseUrl) =>
      sha256.convert(utf8.encode(baseUrl)).toString();

  /// The recovery-journal endpoint scope for [connection], or `null` when the
  /// connection names no usable Desktop Gateway.
  ///
  /// Returning `null` rather than throwing keeps callers that only want to
  /// *read* journal state — such as the Home digest — free of try/catch around
  /// a plain configuration fact.
  static String? endpointDigestFor(SavedConnection connection) {
    final hasExplicitOverride =
        connection.desktopGatewayUrl?.trim().isNotEmpty == true;
    final hasDashboardAuth =
        connection.dashboardProxied ||
        (connection.dashboardUsername?.trim().isNotEmpty == true &&
            connection.dashboardPassword?.trim().isNotEmpty == true);
    if (!hasExplicitOverride && !hasDashboardAuth) return null;
    try {
      return _endpointDigest(normalizedGatewayBaseUrl(connection));
    } on ArgumentError {
      return null;
    }
  }

  factory DesktopGatewayClient.fromConnection(SavedConnection connection) {
    final baseUrl = normalizedGatewayBaseUrl(connection);
    final baseUri = Uri.parse(baseUrl);
    final pathPrefix = baseUri.path == '/' ? '' : baseUri.path;
    return DesktopGatewayClient._(
      connectionId: connection.id,
      baseUrl: baseUrl,
      dashboard: DashboardClient(
        host: baseUri.host,
        // The normalized base URL always carries an explicit port, so this
        // never falls back to a scheme default.
        port: baseUri.port,
        useHttps: baseUri.scheme == 'https',
        pathPrefix: pathPrefix,
        proxied: connection.dashboardProxied,
        username: connection.dashboardUsername,
        password: connection.dashboardPassword,
      ),
      gatewayProfile: connection.gatewayProfile,
    );
  }

  Future<_DesktopGatewaySession> _connect(
    String mobileSessionId, {
    String? workingDirectory,
  }) async {
    final requestedWorkingDirectory = workingDirectory?.trim();
    if (requestedWorkingDirectory != null &&
        requestedWorkingDirectory.isNotEmpty) {
      _workingDirectories[mobileSessionId] = requestedWorkingDirectory;
    }
    final effectiveWorkingDirectory = _workingDirectories[mobileSessionId];
    final existing = _ws;
    if (existing != null && existing.isConnected) {
      final mappedSessionId = _gatewaySessionIds[mobileSessionId];
      if (mappedSessionId != null) {
        return _DesktopGatewaySession(existing, mappedSessionId);
      }
      final binding = await _resumeOrCreateSingle(
        existing,
        mobileSessionId,
        workingDirectory: effectiveWorkingDirectory,
      );
      _rememberBinding(mobileSessionId, binding);
      return _DesktopGatewaySession(existing, binding.runtimeSessionId);
    }

    final client = await _ensureSocket();
    final binding = await _resumeOrCreateSingle(
      client,
      mobileSessionId,
      workingDirectory: effectiveWorkingDirectory,
    );
    _rememberBinding(mobileSessionId, binding);
    return _DesktopGatewaySession(client, binding.runtimeSessionId);
  }

  /// Single-flight wrapper for `_resumeOrCreate`: two concurrent callers for
  /// the same mobile session must not each issue a `session.create` and leave
  /// one gateway session orphaned.
  Future<_DesktopGatewayBinding> _resumeOrCreateSingle(
    WsClient client,
    String mobileSessionId, {
    String? workingDirectory,
  }) {
    final inFlight = _bindingInFlight[mobileSessionId];
    if (inFlight != null) return inFlight;
    final future = _resumeOrCreate(
      client,
      mobileSessionId,
      workingDirectory: workingDirectory,
    );
    _bindingInFlight[mobileSessionId] = future;
    future.whenComplete(() {
      if (identical(_bindingInFlight[mobileSessionId], future)) {
        _bindingInFlight.remove(mobileSessionId);
      }
    }).ignore();
    return future;
  }

  /// Single-flight socket establishment shared by `_connect` and
  /// `_connectControl`. Without this, concurrent callers both pass the
  /// `isConnected` check, both mint tickets, and both build sockets: the
  /// last assignment wins and the loser's socket leaks with the async-event
  /// bridge attached.
  Future<WsClient> _ensureSocket() {
    final existing = _ws;
    if (existing != null && existing.isConnected) {
      return Future.value(existing);
    }
    final inFlight = _socketInFlight;
    if (inFlight != null) return inFlight;
    final future = _openSocket(existing);
    _socketInFlight = future;
    future.whenComplete(() {
      if (identical(_socketInFlight, future)) _socketInFlight = null;
    }).ignore();
    return future;
  }

  Future<WsClient> _openSocket(WsClient? existing) async {
    if (_closed) throw StateError('DesktopGatewayClient is closed.');
    _connectionListener?.call(
      existing == null
          ? DesktopConnectionState.connecting
          : DesktopConnectionState.reconnecting,
    );
    existing?.close();
    _gatewaySessionIds.clear();
    _serverRequests.clear();
    _serverRequestClients.clear();
    _serverRequestMobileSessionIds.clear();
    _serverRequestEvents.clear();
    _serverClarifyRemaining.clear();
    _serverApprovalByMobileSession.clear();
    // A fresh socket means a possibly-replaced server: forget old
    // -32601 verdicts so an upgraded gateway's methods are re-discovered
    // instead of staying short-circuited until app restart. gateway.ready
    // on the new socket re-populates protocol/advertisement.
    _capabilities.reset();
    final ticket = await _dashboard.mintWebSocketTicket();
    if (_closed) throw StateError('DesktopGatewayClient is closed.');
    final client = WsClient(_baseUrl, ticket: ticket, profile: _gatewayProfile);
    _installAsyncEventBridge(client);
    final inheritedConnectionListener = client.onConnectionChanged;
    client.onConnectionChanged = (connected) {
      inheritedConnectionListener?.call(connected);
      if (connected) {
        // Fires inside connect() before _ws is assigned, so no identical()
        // guard is possible here. The single-flight in _ensureSocket keeps
        // loser sockets from being built concurrently.
        _reconnectAttempts = 0;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        // The drop cleared every runtime binding and the server forgot the
        // old socket's sessions. Re-bind each stored session on this
        // fresh socket immediately — a turn that completed detached during
        // the outage must be addressable (and its history refetchable)
        // without waiting for the next user action. Initial connects have
        // no stored ids, so this is a no-op there. Individual resume
        // failures are swallowed: a later explicit call retries the same
        // single-flight path.
        if (!_closed && _storedSessionIds.isNotEmpty) {
          unawaited(_rebindStoredSessions(client));
        }
        _connectionListener?.call(DesktopConnectionState.connected);
      } else if (identical(_ws, client)) {
        _gatewaySessionIds.clear();
        _connectionListener?.call(DesktopConnectionState.disconnected);
        // A socket that was once live and then dropped (phone sleep,
        // heartbeat timeout, gateway restart) must come back on its own:
        // the user is often not looking at the chat window when it dies,
        // and every later RPC would otherwise fail until app restart.
        // Stored session ids survive the drop, so the reopened socket
        // re-binds each session via session.resume on next use.
        _scheduleReconnect();
      }
    };
    try {
      await client.connect();
      if (_closed) {
        client.close();
        throw StateError('DesktopGatewayClient is closed.');
      }
      _ws = client;
      return client;
    } catch (_) {
      client.close();
      if (identical(_ws, client)) _ws = null;
      _connectionListener?.call(DesktopConnectionState.disconnected);
      rethrow;
    }
  }

  /// Exponential-backoff reconnect loop, started when a previously-live
  /// socket drops. Runs independently of the UI: the socket is back before
  /// the user opens the chat again. Retries until success or client close;
  /// detached-turn recovery has no safe deadline after which a reply may be
  /// abandoned. The delay remains capped so a long outage does not spin.
  void _scheduleReconnect() {
    if (_closed || _reconnectTimer != null) return;
    _reconnectAttempts++;
    final exponent = _reconnectAttempts.clamp(1, 5);
    final delay = Duration(seconds: (1 << (exponent - 1)).clamp(2, 30));
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (_closed) return;
      _connectionListener?.call(DesktopConnectionState.reconnecting);
      try {
        await _ensureSocket();
      } catch (_) {
        if (!_closed) _scheduleReconnect();
      }
    });
  }

  /// Re-establish the runtime binding for every stored session on a fresh
  /// socket. Runs fire-and-forget from the connected callback so a reply
  /// that finished server-side during an outage is immediately addressable
  /// on the new socket; the UI's resync (ensureSession + history refetch)
  /// then single-flights with these resumes instead of racing them.
  Future<void> _rebindStoredSessions(WsClient client) async {
    // The connected callback fires inside WsClient.connect() before the
    // await returns; hop off that frame so the socket's message pump is
    // fully live before we issue session.resume over it.
    await Future<void>.delayed(Duration.zero);
    // Snapshot: the map may mutate while resumes are in flight.
    final mobileIds = List<String>.from(_storedSessionIds.keys);
    for (final mobileId in mobileIds) {
      if (_closed || !client.isConnected) return;
      // _ws is null only while this client's own connect() is still
      // returning — that is this socket's own pending assignment, not a
      // replacement. A non-null different client means we were superseded.
      final current = _ws;
      if (current != null && !identical(current, client)) return;
      try {
        final binding = await _resumeOrCreateSingle(
          client,
          mobileId,
          workingDirectory: _workingDirectories[mobileId],
        );
        final after = _ws;
        if (_closed || (after != null && !identical(after, client))) return;
        _rememberBinding(mobileId, binding);
      } catch (_) {
        // Swallow: a later explicit action retries the same single-flight
        // resume path; a resume error must never escape the socket callback.
      }
    }
  }

  Future<_DesktopGatewayBinding> _resumeOrCreate(
    WsClient client,
    String mobileSessionId, {
    String? workingDirectory,
  }) async {
    final storedSessionId =
        _storedSessionIds[mobileSessionId] ?? mobileSessionId;
    try {
      final resumed = await client.resumeSessionDetails(storedSessionId);
      return _DesktopGatewayBinding(
        runtimeSessionId: resumed.runtimeSessionId,
        storedSessionId: storedSessionId,
        resumed: resumed,
      );
    } on JsonRpcError catch (error) {
      if (error.code != 4007 &&
          !error.message.toLowerCase().contains('session not found')) {
        rethrow;
      }
      // New mobile chats do not exist in Hermes yet. Stock Hermes rejects a
      // client-supplied `session_id` on session.create, so retain both gateway-
      // minted identities: runtime for this socket and stored for reconnect.
      final created = await client.createSession(
        workingDirectory: workingDirectory,
      );
      return _DesktopGatewayBinding(
        runtimeSessionId: created.runtimeSessionId,
        storedSessionId: created.storedSessionId,
      );
    }
  }

  void _rememberBinding(
    String mobileSessionId,
    _DesktopGatewayBinding binding,
  ) {
    _gatewaySessionIds[mobileSessionId] = binding.runtimeSessionId;
    _storedSessionIds[mobileSessionId] = binding.storedSessionId;
    final resumed = binding.resumed;
    if (resumed != null && resumed.openRequests.isNotEmpty) {
      // The resume payload carries unanswered server→client requests. Deliver
      // only after the runtime sid is mapped back to this mobile chat.
      _ws?.deliverOpenRequests(resumed.openRequests);
    }
    final inflight = resumed?.inflight;
    final error = inflight?['error']?.toString().trim() ?? '';
    final status = (inflight?['status'] ?? resumed?.status)
        ?.toString()
        .trim()
        .toLowerCase();
    const terminalFailures = {
      'error',
      'failed',
      'interrupted',
      'cancelled',
      'canceled',
    };
    if (resumed != null &&
        (error.isNotEmpty || terminalFailures.contains(status))) {
      if (binding.resumeStateDelivered) return;
      binding.resumeStateDelivered = true;
      // Deliver after the binding maps are authoritative. The UI may already
      // have begun a history fetch from the connected callback; its recovery
      // generation makes that fetch harmless once this failure clears it.
      scheduleMicrotask(() {
        _asyncEventListener?.call(
          mobileSessionId,
          StreamEvent(
            type: 'turn.error',
            data: {
              'session_id': binding.runtimeSessionId,
              'message': error.isNotEmpty ? error : 'Detached turn $status',
              if (status != null && status.isNotEmpty) 'status': status,
            },
            isComplete: true,
            sessionId: binding.runtimeSessionId,
          ),
        );
      });
    }
  }

  /// The gateway's stored session key bound to a mobile session id, when a
  /// binding exists. Stored keys address rows in the session DB (move,
  /// resume); mobile ids do not survive into gateway-side lookups.
  String? storedSessionKeyFor(String mobileSessionId) =>
      _storedSessionIds[mobileSessionId];

  /// True when [error] says the runtime session id the gateway was handed no
  /// longer exists — the detached/orphan-reap or eviction signature. The
  /// gateway's own rejection text tells the client to resume the STORED id
  /// (`_sess_nowait`, 4001), so this is a recoverable stale-binding, not a
  /// hard failure.
  static bool _isStaleRuntimeSession(JsonRpcError error) {
    if (error.code == 4001) return true;
    final message = error.message.toLowerCase();
    return message.contains('session not found') ||
        message.contains('not in memory');
  }

  /// Runs a session-scoped gateway call with one automatic recovery from a
  /// stale runtime binding.
  ///
  /// The gateway orphan-reaps detached runtimes and LRU-evicts idle ones, so
  /// a cached runtime sid can name a session the server no longer holds even
  /// while the stored row lives on. Every session-scoped RPC then fails with
  /// 4001 "session not found" and the UI shows a dropped chat. Recovery is
  /// exactly what the gateway's rejection asks for: drop the stale runtime
  /// mapping, `session.resume` the stored key on the live socket, and retry
  /// the call once with the fresh runtime sid. A second stale failure is a
  /// real one (stored row gone too) and propagates.
  Future<T> _callSessionScoped<T>(
    String mobileSessionId,
    Future<T> Function(_DesktopGatewaySession session) call,
  ) async {
    final session = await _connect(mobileSessionId);
    try {
      return await call(session);
    } on JsonRpcError catch (error) {
      if (!_isStaleRuntimeSession(error)) rethrow;
      final client = _ws;
      if (client == null ||
          !client.isConnected ||
          !_rememberedRuntimeIsStale(mobileSessionId, session.sessionId)) {
        rethrow;
      }
      _gatewaySessionIds.remove(mobileSessionId);
      final binding = await _resumeOrCreateSingle(
        client,
        mobileSessionId,
        workingDirectory: _workingDirectories[mobileSessionId],
      );
      _rememberBinding(mobileSessionId, binding);
      return call(_DesktopGatewaySession(client, binding.runtimeSessionId));
    }
  }

  /// Guard against retrying a call whose sid was not the one we cached: if
  /// some other path already re-bound the session while the call was in
  /// flight, the error came from a different generation and a blind retry
  /// could double-execute against the new binding.
  bool _rememberedRuntimeIsStale(
    String mobileSessionId,
    String usedRuntimeId,
  ) => _gatewaySessionIds[mobileSessionId] == usedRuntimeId;

  Future<void> ensureSession(
    String sessionId, {
    String? workingDirectory,
  }) async {
    await _connect(sessionId, workingDirectory: workingDirectory);
  }

  /// The dashboard client backing this gateway's auth/ticket flow.
  ///
  /// Exposed so collaborators (e.g. the Projects folder provisioner) can
  /// reuse this connection's cached auth and single-flight login instead of
  /// standing up a second unauthenticated HTTP client.
  DashboardClient get dashboard => _dashboard;

  /// Server-owned Hermes Projects for this gateway.
  ///
  /// Projects are connection-scoped, not session-scoped, so this opens the
  /// shared socket without resuming or creating any chat session. An older
  /// gateway without `projects.*` surfaces a [ProjectsUnsupportedException]
  /// instead of an error state, so callers can fall back to local grouping.
  ProjectsGatewayClient get projects {
    return _projects ??= ProjectsGatewayClient((method, params) async {
      final client = await _connectControl();
      return client.send(method, params);
    }, capabilities: _capabilities);
  }

  /// What this gateway advertises or has been proven to support.
  ///
  /// Populated from `gateway.ready` on every connect and refined by the
  /// outcome of real calls, so a feature can degrade politely on an older
  /// gateway instead of failing.
  CapabilityRegistry get capabilities => _capabilities;

  /// Opens (or reuses) the gateway socket without binding it to a session.
  Future<WsClient> _connectControl() => _ensureSocket();

  /// Creates the source-only recovery-v2 registry without changing any legacy
  /// session, submit, interrupt, or event route in this client.
  GatewayTurnCoordinatorRegistry enableTurnRecoveryCoordinator({
    GatewayTurnJournal? journal,
  }) {
    return _turnCoordinatorRegistry ??=
        GatewayTurnCoordinatorRegistry(
            connectionId: _connectionId,
            endpointDigest: _endpointDigest(_baseUrl),
            journal: journal ?? GatewayTurnJournal(),
            freshSocketFactory: () async {
              final ticket = await _dashboard.mintWebSocketTicket();
              final client = WsClient(
                _baseUrl,
                ticket: ticket,
                profile: _gatewayProfile,
              );
              _installAsyncEventBridge(client);
              return client;
            },
          )
          ..onRuntimeBound = (localSessionId, runtimeSessionId) {
            _gatewaySessionIds[localSessionId] = runtimeSessionId;
          };
  }

  void setConnectionListener(DesktopConnectionCallback? listener) {
    _connectionListener = listener;
  }

  Future<RemoteFileAttachment> attachFile({
    required String sessionId,
    required String name,
    required String dataUrl,
  }) async {
    return _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.attachFile(
        sessionId: gateway.sessionId,
        name: name,
        dataUrl: dataUrl,
      ),
    );
  }

  Future<void> submitPrompt({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
    required void Function() onSent,
  }) async {
    await _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.submitPrompt(
        text,
        sessionId: gateway.sessionId,
        onEvent: onEvent,
        onSent: onSent,
      ),
    );
  }

  /// Receives durable session-scoped events plus terminal turn frames.
  ///
  /// Terminal frames are also delivered through [submitPrompt] while its
  /// listener is attached. The async path is required after socket close,
  /// when a detached turn can settle on the resumed session; ChatScreen
  /// ignores the duplicate unless legacy reattach recovery is pending.
  void setAsyncEventListener(
    DesktopAsyncEventCallback? listener, {
    DesktopAsyncEventSessionPredicate? acceptsSession,
  }) {
    _asyncEventListener = listener;
    _asyncEventAcceptsSession = listener == null ? null : acceptsSession;
  }

  void _installAsyncEventBridge(WsClient client) {
    // Every socket greets us with gateway.ready; that greeting is where the
    // capability registry learns what this Hermes instance offers.
    _capabilities.bindTo(client);
    _serverRequestClientOrdinals.putIfAbsent(
      client,
      () => _nextServerRequestClientOrdinal++,
    );
    client.onServerRequest = (request) => _handleServerRequest(client, request);
    client.onConnectionClosed = () => _forgetServerRequestsFrom(client);
    client.onStreamEvent = (event) {
      if (!_asyncEventTypes.contains(event.type)) return;
      var deliveredEvent = event;
      if (event.type == 'request.cancel') {
        final wireRequestId = event.data['id']?.toString() ?? '';
        final requestId = _findServerRequestKey(client, wireRequestId);
        if (requestId != null) {
          _forgetServerRequest(requestId);
          deliveredEvent = StreamEvent(
            type: event.type,
            data: {...event.data, 'id': requestId},
            sessionId: event.sessionId,
          );
        }
      }
      final mobileSessionId = _mobileSessionIdFor(
        event.data['session_id']?.toString(),
      );
      if (mobileSessionId == null) return;
      _asyncEventListener?.call(mobileSessionId, deliveredEvent);
    };
  }

  String _serverRequestKey(WsClient client, String wireRequestId) =>
      '$_serverRequestNamespace.${_serverRequestClientOrdinals[client]}:'
      '$wireRequestId';

  String? _findServerRequestKey(WsClient client, String wireRequestId) {
    for (final entry in _serverRequestClients.entries) {
      if (identical(entry.value, client) &&
          _serverRequests[entry.key]?.id == wireRequestId) {
        return entry.key;
      }
    }
    return null;
  }

  String? _mobileSessionIdFor(String? gatewaySessionId) {
    if (gatewaySessionId != null && gatewaySessionId.isNotEmpty) {
      for (final entry in _gatewaySessionIds.entries) {
        if (entry.value == gatewaySessionId) return entry.key;
      }
    } else if (_gatewaySessionIds.length == 1) {
      return _gatewaySessionIds.keys.single;
    }
    return null;
  }

  bool _handleServerRequest(WsClient client, GatewayServerRequest request) {
    const supported = {'clarify', 'approval', 'sudo', 'secret'};
    if (!supported.contains(request.method)) return false;

    final gatewaySessionId = request.params['session_id']?.toString();
    final mobileSessionId = _mobileSessionIdFor(gatewaySessionId);
    if (mobileSessionId == null || _asyncEventListener == null) return false;
    final acceptsSession = _asyncEventAcceptsSession;
    if (acceptsSession != null && !acceptsSession(mobileSessionId)) {
      return false;
    }

    final requestId = _serverRequestKey(client, request.id);
    _serverRequests[requestId] = request;
    _serverRequestClients[requestId] = client;
    _serverRequestMobileSessionIds[requestId] = mobileSessionId;
    final data = Map<String, dynamic>.from(request.params);
    data['server_request_id'] = requestId;

    if (request.method == 'clarify') {
      data['request_id'] = requestId;
      final questions = data['questions'];
      final lockedAnswers = data['answers'];
      final lockedQuestionIds = lockedAnswers is Map
          ? lockedAnswers.keys.map((key) => key.toString()).toSet()
          : const <String>{};
      final qids = <String>{};
      final remainingQuestions = <dynamic>[];
      if (questions is List) {
        for (final raw in questions) {
          if (raw is! Map) continue;
          final qid = raw['qid']?.toString().trim() ?? '';
          if (qid.isEmpty || lockedQuestionIds.contains(qid)) continue;
          qids.add(qid);
          remainingQuestions.add(raw);
        }
      }
      if (qids.isEmpty) {
        _forgetServerRequest(requestId);
        return false;
      }
      data['questions'] = remainingQuestions;
      _serverClarifyRemaining[requestId] = qids;
    } else if (request.method == 'approval') {
      final previous = _serverApprovalByMobileSession[mobileSessionId];
      if (previous != null && previous != requestId) {
        // ChatScreen presents one approval route at a time. Reject a concurrent
        // request instead of replacing the visible request and stranding both.
        _forgetServerRequest(requestId);
        return false;
      }
      _serverApprovalByMobileSession[mobileSessionId] = requestId;
    } else {
      // Legacy event models key sensitive prompts by `request_id`; for the
      // peer-to-peer protocol the JSON-RPC id is the response correlation.
      data['request_id'] = requestId;
    }

    final event = StreamEvent(
      type: '${request.method}.request',
      data: data,
      sessionId: gatewaySessionId,
    );
    _serverRequestEvents[requestId] = event;
    _asyncEventListener!.call(mobileSessionId, event);
    return true;
  }

  void _forgetServerRequest(String requestId) {
    _serverRequests.remove(requestId);
    _serverRequestClients.remove(requestId);
    _serverRequestMobileSessionIds.remove(requestId);
    _serverRequestEvents.remove(requestId);
    _serverClarifyRemaining.remove(requestId);
    _serverApprovalByMobileSession.removeWhere((_, id) => id == requestId);
  }

  void _forgetServerRequestsFrom(WsClient client) {
    final requestIds = _serverRequestClients.entries
        .where((entry) => identical(entry.value, client))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final requestId in requestIds) {
      final request = _serverRequests[requestId];
      final mobileSessionId = _serverRequestMobileSessionIds[requestId];
      _forgetServerRequest(requestId);
      if (request != null && mobileSessionId != null) {
        _asyncEventListener?.call(
          mobileSessionId,
          StreamEvent(
            type: 'request.cancel',
            data: {'id': requestId, 'method': request.method},
          ),
        );
      }
    }
    _serverRequestClientOrdinals.remove(client);
  }

  void _rejectServerRequest(String requestId, String message) {
    _serverRequests[requestId]?.fail(-32601, message);
    _forgetServerRequest(requestId);
  }

  /// Replays unresolved requests when a replacement route mounts.
  void replayServerRequestsForSession(String mobileSessionId) {
    final listener = _asyncEventListener;
    if (listener == null) return;
    for (final entry in _serverRequestMobileSessionIds.entries.toList()) {
      if (entry.value != mobileSessionId) continue;
      final event = _serverRequestEvents[entry.key];
      if (event != null) listener(mobileSessionId, event);
    }
  }

  /// Rejects requests that no mounted route can answer.
  void rejectServerRequestsForSession(String mobileSessionId) {
    final requestIds = _serverRequestMobileSessionIds.entries
        .where((entry) => entry.value == mobileSessionId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final requestId in requestIds) {
      _rejectServerRequest(
        requestId,
        'No mounted client can answer this request',
      );
    }
  }

  /// Whether this client owns an unresolved peer-to-peer request.
  bool ownsServerRequest(String requestId, String method) =>
      _serverRequests[requestId]?.method == method;

  /// Whether this client owns the active approval for [sessionId].
  bool ownsApprovalRequest(String sessionId) {
    final requestId = _serverApprovalByMobileSession[sessionId];
    return requestId != null &&
        _serverRequests[requestId]?.method == 'approval';
  }

  /// Interrupts the active turn in the Desktop gateway runtime.
  Future<bool> interruptPrompt({required String sessionId}) async {
    final gatewaySessionId = _gatewaySessionIds[sessionId];
    final client = _ws;
    if (gatewaySessionId == null || client == null || !client.isConnected) {
      return false;
    }
    await client.interruptSession(gatewaySessionId);
    return true;
  }

  /// Resolves an approval against an exact peer request when available, or
  /// falls back to the legacy session-keyed approval method.
  Future<void> respondToApproval({
    required String sessionId,
    required String choice,
    String? serverRequestId,
  }) async {
    final effectiveRequestId =
        serverRequestId ?? _serverApprovalByMobileSession[sessionId];
    final serverRequest = effectiveRequestId == null
        ? null
        : _serverRequests[effectiveRequestId];
    if (serverRequest != null) {
      if (!serverRequest.respond({'choice': choice})) {
        throw StateError('The server request socket is no longer connected');
      }
      _forgetServerRequest(effectiveRequestId!);
      return;
    }
    if (serverRequestId != null) {
      throw StateError('The approval request is no longer active');
    }
    final gatewaySessionId = _gatewaySessionIds[sessionId];
    final client = _ws;
    if (gatewaySessionId == null || client == null || !client.isConnected) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    await client.respondToApproval(sessionId: gatewaySessionId, choice: choice);
  }

  Future<void> respondToSudo({
    required String requestId,
    required String password,
  }) async {
    final serverRequest = _serverRequests[requestId];
    if (serverRequest?.method == 'sudo') {
      if (!serverRequest!.respond({'value': password})) {
        throw StateError('The server request socket is no longer connected');
      }
      _forgetServerRequest(requestId);
      return;
    }
    final client = _connectedClient();
    await client.respondToSudo(requestId: requestId, password: password);
  }

  Future<void> respondToSecret({
    required String requestId,
    required String value,
  }) async {
    final serverRequest = _serverRequests[requestId];
    if (serverRequest?.method == 'secret') {
      if (!serverRequest!.respond({'value': value})) {
        throw StateError('The server request socket is no longer connected');
      }
      _forgetServerRequest(requestId);
      return;
    }
    final client = _connectedClient();
    await client.respondToSecret(requestId: requestId, value: value);
  }

  Future<void> respondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
  }) async {
    final serverRequest = _serverRequests[requestId];
    final client = serverRequest?.method == 'clarify'
        ? _serverRequestClients[requestId]
        : _ws;
    if (client == null || !client.isConnected) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    if (serverRequest?.method == 'clarify') {
      final qid = questionId?.trim() ?? '';
      if (qid.isEmpty) {
        throw ArgumentError('questionId is required for a clarify request');
      }
      // Current Hermes locks each batch answer through clarify.lock; the last
      // lock resolves the original server request on the backend.
      final result = await client.respondToClarify(
        requestId: serverRequest!.id,
        answer: answer,
        questionId: qid,
        lockAnswer: true,
      );
      final status = result['status']?.toString();
      final rawRemaining = result['remaining'];
      final remaining =
          rawRemaining is List
                ? rawRemaining.map((value) => value.toString()).toSet()
                : status == 'expired'
                ? <String>{}
                : (_serverClarifyRemaining[requestId] ?? <String>{})
            ..remove(qid);
      _serverClarifyRemaining[requestId] = remaining;
      if (remaining.isNotEmpty) {
        final replayEvent = _serverRequestEvents[requestId];
        final rawQuestions = replayEvent?.data['questions'];
        if (replayEvent != null && rawQuestions is List) {
          _serverRequestEvents[requestId] = StreamEvent(
            type: replayEvent.type,
            data: {
              ...replayEvent.data,
              'questions': rawQuestions
                  .where(
                    (raw) =>
                        raw is Map &&
                        remaining.contains(raw['qid']?.toString()),
                  )
                  .toList(growable: false),
            },
            sessionId: replayEvent.sessionId,
          );
        }
      }
      final mobileSessionId = _serverRequestMobileSessionIds[requestId];
      if (mobileSessionId != null) {
        _asyncEventListener?.call(
          mobileSessionId,
          StreamEvent(
            type: 'clarify.remaining',
            data: {'id': requestId, 'remaining': remaining.toList()},
          ),
        );
      }
      if (remaining.isEmpty) {
        _forgetServerRequest(requestId);
      }
      return;
    }
    await client.respondToClarify(
      requestId: requestId,
      answer: answer,
      questionId: questionId,
    );
  }

  WsClient _connectedClient() {
    final client = _ws;
    if (client == null || !client.isConnected) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    return client;
  }

  /// The profile-scoped catalog and default shown by Hermes Desktop.  Keeping
  /// these reads on the Dashboard endpoint means Android never guesses model
  /// names or providers from the OpenAI-compatible API.
  Future<Map<String, dynamic>> getModelInfo() => _dashboard.getModelInfo();

  Future<Map<String, dynamic>> getModelOptions() =>
      _dashboard.getModelOptions();

  Future<void> setSessionModel({
    required String sessionId,
    required String provider,
    required String model,
  }) async {
    await _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.setSessionModel(
        sessionId: gateway.sessionId,
        provider: provider,
        model: model,
      ),
    );
  }

  Future<String> getSessionReasoning(String sessionId) {
    return _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.getSessionReasoning(gateway.sessionId),
    );
  }

  Future<void> setSessionReasoning({
    required String sessionId,
    required String effort,
  }) async {
    await _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.setSessionReasoning(
        sessionId: gateway.sessionId,
        effort: effort,
      ),
    );
  }

  Future<void> renameSession({
    required String sessionId,
    required String title,
  }) async {
    await _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.setSessionTitle(gateway.sessionId, title),
    );
  }

  Future<Map<String, dynamic>> branchSession({
    required String sessionId,
    required String name,
  }) async {
    return _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.branchSession(gateway.sessionId, name: name),
    );
  }

  void close() {
    _closed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _asyncEventListener = null;
    _asyncEventAcceptsSession = null;
    _connectionListener = null;
    _projects = null;
    _ws?.close();
    _ws = null;
    _gatewaySessionIds.clear();
    _storedSessionIds.clear();
    _workingDirectories.clear();
    _serverRequests.clear();
    _serverRequestClients.clear();
    _serverRequestMobileSessionIds.clear();
    _serverRequestEvents.clear();
    _serverRequestClientOrdinals.clear();
    _serverClarifyRemaining.clear();
    _serverApprovalByMobileSession.clear();
    final turnCoordinatorRegistry = _turnCoordinatorRegistry;
    _turnCoordinatorRegistry = null;
    if (turnCoordinatorRegistry != null) {
      final closing = turnCoordinatorRegistry.closeAll();
      unawaited(closing.then<void>((_) {}, onError: (_, _) {}));
    }
    _dashboard.close();
  }
}

String documentIntakeProfileForConnection(SavedConnection connection) {
  final candidates = <String>[
    connection.gatewayPrefix ?? '',
    Uri.tryParse(connection.desktopGatewayUrl ?? '')?.path ?? '',
  ];
  final segments = candidates
      .expand((value) => value.toLowerCase().split('/'))
      .where((value) => value.isNotEmpty)
      .toSet();
  if (segments.contains('personal')) return 'personal';
  if (segments.contains('pro') || segments.contains('professional')) {
    return 'pro';
  }
  return 'organizator';
}

class _DesktopGatewaySession {
  final WsClient client;
  final String sessionId;

  const _DesktopGatewaySession(this.client, this.sessionId);
}

class _DesktopGatewayBinding {
  final String runtimeSessionId;
  final String storedSessionId;
  final ResumedGatewaySession? resumed;
  bool resumeStateDelivered = false;

  _DesktopGatewayBinding({
    required this.runtimeSessionId,
    required this.storedSessionId,
    this.resumed,
  });
}
