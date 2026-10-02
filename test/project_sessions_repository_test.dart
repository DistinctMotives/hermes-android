/// Contract tests for reading one project's chats through [ProjectsRepository].
///
/// `ProjectsGatewayClient.projectSessions` already speaks the native
/// `projects.project_sessions` RPC, but nothing above it does: the Projects
/// pane can list projects and cannot open one. This is the repository half of
/// that drill-in — the layer that decides what happens when the read is slow,
/// repeated, concurrent, unsupported, or fails.
///
/// The rules pinned here are the ones a project screen would otherwise have to
/// reinvent (and get wrong) in widget code:
///
/// - an unknown project is an *empty* result, never an error screen;
/// - a gateway that predates the drill-in disables this one call, and must not
///   drag the whole Projects pane into local-only compatibility mode;
/// - a gateway already proven to lack `projects.*` costs no request at all;
/// - a failed re-read keeps the chats already on screen rather than blanking
///   them, while a failed *first* read is reported so the UI can offer retry;
/// - repeated opens of the same project reuse the last tree, and two opens
///   racing each other share one request instead of hammering the gateway.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _ok(Map<String, dynamic> result) => {
  'jsonrpc': '2.0',
  'id': 1,
  'result': result,
};

Map<String, dynamic> _rpcError(int code, String message) => {
  'jsonrpc': '2.0',
  'id': 1,
  'error': {'code': code, 'message': message},
};

Map<String, dynamic> _projectJson({required String id, required String name}) =>
    {
      'id': id,
      'slug': name.toLowerCase().replaceAll(' ', '-'),
      'name': name,
      'archived': false,
      'created_at': 1750000000,
      'folders': const [],
    };

/// One session row exactly as the gateway project tree emits it.
Map<String, dynamic> _sessionRow({String id = 's1', String title = 'Chat'}) => {
  'id': id,
  'title': title,
  'preview': 'Ran flutter analyze',
  'started_at': 1750000000,
  'ended_at': null,
  'source': 'cli',
  'message_count': 3,
  'model': 'claude-opus-5',
};

/// A project node with one repo, one lane, and the given chats.
Map<String, dynamic> _projectNode({
  String id = 'p1',
  List<Map<String, dynamic>> sessions = const [],
  List<Map<String, dynamic>>? repos,
  List<Map<String, dynamic>> previewSessions = const [],
  int? sessionCount,
}) => {
  'id': id,
  'label': 'Hermes Android',
  'path': '/home/carlos/dev/hermes-android',
  'sessionCount': sessionCount ?? sessions.length,
  'lastActive': 1750000900,
  'repos':
      repos ??
      [
        {
          'id': '/home/carlos/dev/hermes-android',
          'label': 'hermes-android',
          'path': '/home/carlos/dev/hermes-android',
          'sessionCount': sessions.length,
          'groups': [
            {
              'id': 'main',
              'label': 'main',
              'isMain': true,
              'isKanban': false,
              'sessions': sessions,
            },
          ],
        },
      ],
  'previewSessions': previewSessions,
};

/// A scriptable stand-in for the gateway `projects.*` family.
class _FakeGateway {
  final List<({String method, Map<String, dynamic> params})> calls = [];
  List<Map<String, dynamic>> projects;

  /// Answers `projects.list` with an unknown-method error when true.
  bool listSupported;

  /// Canned answers for `projects.project_sessions`, keyed by project id.
  final Map<String, Map<String, dynamic>?> trees;

  /// When set, the next `projects.project_sessions` returns this envelope.
  Map<String, dynamic>? sessionsEnvelope;

  /// When set, the next `projects.project_sessions` throws this instead.
  Object? failNextSessions;

  /// When set, `projects.project_sessions` waits on this before answering.
  Completer<void>? gate;

  _FakeGateway({
    List<Map<String, dynamic>>? projects,
    this.listSupported = true,
    Map<String, Map<String, dynamic>?>? trees,
  }) : projects = projects ?? [],
       trees = trees ?? {};

  int callsTo(String method) =>
      calls.where((call) => call.method == method).length;

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params,
  ) async {
    calls.add((method: method, params: params));
    switch (method) {
      case 'projects.list':
        if (!listSupported) {
          return _rpcError(-32601, 'unknown method: projects.list');
        }
        return _ok({'projects': projects, 'active_id': null});
      case 'projects.project_sessions':
        final gate = this.gate;
        if (gate != null) await gate.future;
        final failure = failNextSessions;
        if (failure != null) {
          failNextSessions = null;
          throw failure;
        }
        final envelope = sessionsEnvelope;
        if (envelope != null) {
          sessionsEnvelope = null;
          return envelope;
        }
        final id = params['project_id'] as String;
        return _ok({'project': trees[id]});
      default:
        return _ok(const {});
    }
  }
}

Future<ProjectsRepository> _repository(_FakeGateway gateway) async {
  return ProjectsRepository(
    client: ProjectsGatewayClient(gateway.call),
    preferences: await SharedPreferences.getInstance(),
    connectionId: 'gateway-a',
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reads a project tree and flattens its chats in server order', () async {
    final gateway = _FakeGateway(
      projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
      trees: {
        'p1': _projectNode(
          sessions: [
            _sessionRow(id: 's1', title: 'Projects pane'),
            _sessionRow(id: 's2', title: 'Activity timeline'),
          ],
        ),
      },
    );
    final repo = await _repository(gateway);
    await repo.refresh();

    final view = await repo.projectSessions('p1');

    expect(view.projectId, 'p1');
    expect(view.support, ProjectsSupport.native);
    expect(view.isStale, isFalse);
    expect(view.error, isNull);
    expect(view.sessions.map((s) => s.id), ['s1', 's2']);
    expect(view.sessions.first.title, 'Projects pane');
    expect(view.tree?.label, 'Hermes Android');
    expect(view.isEmpty, isFalse);
  });

  test('falls back to the server preview when no lane holds chats', () async {
    // The server ranks recent chats in `previewSessions` even when repo/lane
    // grouping produced nothing (an imported project, a chat with no cwd).
    // Rendering "no chats yet" while the server just listed some would be a
    // lie the user cannot resolve from the phone.
    final gateway = _FakeGateway(
      trees: {
        'p1': _projectNode(
          repos: const [],
          previewSessions: [_sessionRow(id: 's7', title: 'Imported chat')],
          sessionCount: 1,
        ),
      },
    );
    final repo = await _repository(gateway);
    await repo.refresh();

    final view = await repo.projectSessions('p1');

    expect(view.sessions.map((s) => s.id), ['s7']);
    expect(view.isEmpty, isFalse);
  });

  test('reads an unknown project as empty rather than as a failure', () async {
    final gateway = _FakeGateway(trees: {'ghost': null});
    final repo = await _repository(gateway);
    await repo.refresh();

    final view = await repo.projectSessions('ghost');

    expect(view.tree, isNull);
    expect(view.sessions, isEmpty);
    expect(view.isEmpty, isTrue);
    expect(view.error, isNull);
    expect(view.support, ProjectsSupport.native);
  });

  test('serves a repeated open from cache and re-reads on refresh', () async {
    final gateway = _FakeGateway(
      trees: {
        'p1': _projectNode(sessions: [_sessionRow(id: 's1')]),
      },
    );
    final repo = await _repository(gateway);
    await repo.refresh();

    await repo.projectSessions('p1');
    final second = await repo.projectSessions('p1');
    expect(gateway.callsTo('projects.project_sessions'), 1);
    expect(second.sessions.single.id, 's1');
    expect(second.isStale, isFalse);

    await repo.projectSessions('p1', refresh: true);
    expect(gateway.callsTo('projects.project_sessions'), 2);
  });

  test('shares one request between two opens racing each other', () async {
    final gateway = _FakeGateway(
      trees: {
        'p1': _projectNode(sessions: [_sessionRow(id: 's1')]),
      },
    );
    final repo = await _repository(gateway);
    await repo.refresh();

    gateway.gate = Completer<void>();
    final first = repo.projectSessions('p1', refresh: true);
    final second = repo.projectSessions('p1', refresh: true);
    gateway.gate!.complete();
    final views = await Future.wait([first, second]);

    expect(gateway.callsTo('projects.project_sessions'), 1);
    expect(views.first.sessions.single.id, 's1');
    expect(views.last.sessions.single.id, 's1');
  });

  test('caches each project separately', () async {
    final gateway = _FakeGateway(
      trees: {
        'p1': _projectNode(
          id: 'p1',
          sessions: [_sessionRow(id: 'a')],
        ),
        'p2': _projectNode(
          id: 'p2',
          sessions: [_sessionRow(id: 'b')],
        ),
      },
    );
    final repo = await _repository(gateway);
    await repo.refresh();

    expect((await repo.projectSessions('p1')).sessions.single.id, 'a');
    expect((await repo.projectSessions('p2')).sessions.single.id, 'b');
    expect((await repo.projectSessions('p1')).sessions.single.id, 'a');
    expect(gateway.callsTo('projects.project_sessions'), 2);
  });

  test('keeps the last known chats when a re-read fails', () async {
    final gateway = _FakeGateway(
      trees: {
        'p1': _projectNode(sessions: [_sessionRow(id: 's1')]),
      },
    );
    final repo = await _repository(gateway);
    await repo.refresh();
    await repo.projectSessions('p1');

    gateway.failNextSessions = JsonRpcError(
      'projects.project_sessions',
      'Desktop gateway connection closed',
      reason: 'connection_closed',
    );
    final view = await repo.projectSessions('p1', refresh: true);

    expect(view.sessions.single.id, 's1');
    expect(view.isStale, isTrue);
    expect(view.error, isA<JsonRpcError>());
  });

  test(
    'reports a failed first read instead of pretending it is empty',
    () async {
      final gateway = _FakeGateway(trees: {'p1': _projectNode()});
      final repo = await _repository(gateway);
      await repo.refresh();

      gateway.failNextSessions = StateError('socket died');
      final view = await repo.projectSessions('p1');

      expect(view.sessions, isEmpty);
      expect(view.error, isA<StateError>());
      // Nothing was ever shown, so there is no stale content to preserve: the
      // UI must draw a retryable error, not an "offline" banner over a blank.
      expect(view.isStale, isFalse);
    },
  );

  test(
    'disables only this call when the gateway predates the drill-in',
    () async {
      // A gateway can serve `projects.list` perfectly and predate
      // `projects.project_sessions`. Dropping the whole pane into local-only
      // compatibility mode for that would be a regression the cached verdict
      // never undoes.
      final gateway = _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
      );
      final repo = await _repository(gateway);
      await repo.refresh();

      gateway.sessionsEnvelope = _rpcError(
        -32601,
        'unknown method: projects.project_sessions',
      );
      final view = await repo.projectSessions('p1');

      expect(view.support, ProjectsSupport.unsupported);
      expect(view.error, isNull);
      expect(view.sessions, isEmpty);
      expect(repo.current.support, ProjectsSupport.native);
      expect(repo.current.projects.single.name, 'Hermes Android');
    },
  );

  test('spends no request on a gateway without the projects family', () async {
    final gateway = _FakeGateway(listSupported: false);
    final repo = await _repository(gateway);
    await repo.refresh();
    expect(repo.current.support, ProjectsSupport.unsupported);

    final view = await repo.projectSessions('p1');

    expect(view.support, ProjectsSupport.unsupported);
    expect(view.sessions, isEmpty);
    expect(view.error, isNull);
    expect(gateway.callsTo('projects.project_sessions'), 0);
  });
}
