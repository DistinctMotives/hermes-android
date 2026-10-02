import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_digest.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/core/widgets/home_pane.dart';

/// A fixed clock so the window boundaries the digest owns stay asserted
/// rather than approximated.
final _now = DateTime.utc(2026, 8, 27, 12, 0, 0);

double _epoch(Duration ago) =>
    _now.subtract(ago).millisecondsSinceEpoch / 1000.0;

Session _session({
  required String id,
  String title = 'Session',
  Duration startedAgo = const Duration(minutes: 5),
  Duration? endedAgo,
  String preview = 'preview',
}) {
  return Session(
    id: id,
    title: title,
    model: 'claude-opus-5',
    source: 'gateway',
    messageCount: 4,
    isActive: endedAgo == null,
    preview: preview,
    startedAt: _epoch(startedAgo),
    endedAt: endedAgo == null ? null : _epoch(endedAgo),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required HomeSessionsLoader loadSessions,
  Map<String, String> attention = const {},
  Set<String> running = const {},
  Map<String, String> projectNames = const {},
  ValueChanged<Session>? onOpenSession,
  Size size = const Size(400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: hermesTheme(Brightness.dark),
      home: Scaffold(
        body: HomePane(
          loadSessions: loadSessions,
          attention: attention,
          running: running,
          projectNames: projectNames,
          onOpenSession: onOpenSession,
          clock: () => _now,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('holds a loading skeleton until the first read lands', (
    tester,
  ) async {
    final gate = Completer<List<Session>>();
    await _pump(tester, loadSessions: () => gate.future);
    await tester.pump();

    expect(find.byType(LoadingSkeleton), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);

    gate.complete([_session(id: 's1', title: 'Roadmap')]);
    await tester.pumpAndSettle();

    expect(find.byType(LoadingSkeleton), findsNothing);
    expect(find.text('Roadmap'), findsOneWidget);
  });

  testWidgets('renders the digest sections in attention order', (tester) async {
    await _pump(
      tester,
      loadSessions: () async => [
        _session(
          id: 'done',
          title: 'Finished work',
          endedAgo: const Duration(hours: 2),
        ),
        _session(
          id: 'idle',
          title: 'Resume this',
          startedAgo: const Duration(hours: 3),
        ),
        _session(id: 'live', title: 'Working now'),
        _session(id: 'blocked', title: 'Waiting on you'),
      ],
      attention: const {'blocked': 'Approval needed'},
      running: const {'live'},
    );
    await tester.pumpAndSettle();

    double topOf(String text) => tester.getTopLeft(find.text(text).first).dy;

    expect(
      topOf(HomeSectionKind.needsYou.title),
      lessThan(topOf(HomeSectionKind.running.title)),
    );
    expect(
      topOf(HomeSectionKind.running.title),
      lessThan(topOf(HomeSectionKind.continueWorking.title)),
    );
    expect(
      topOf(HomeSectionKind.continueWorking.title),
      lessThan(topOf(HomeSectionKind.completedRecently.title)),
    );
  });

  testWidgets(
    'a blocked session states its reason and never doubles as running',
    (tester) async {
      await _pump(
        tester,
        loadSessions: () async => [
          _session(id: 'blocked', title: 'Waiting on you'),
        ],
        attention: const {'blocked': 'Approval needed'},
        // The same session is reported as running by a stale event.
        running: const {'blocked'},
      );
      await tester.pumpAndSettle();

      expect(find.text('Approval needed'), findsOneWidget);
      expect(find.text('Waiting on you'), findsOneWidget);
      expect(find.text(HomeSectionKind.running.title), findsNothing);
    },
  );

  testWidgets('shows the owning project so a row says where it happened', (
    tester,
  ) async {
    await _pump(
      tester,
      loadSessions: () async => [_session(id: 's1', title: 'Roadmap')],
      projectNames: const {'s1': 'Hermes Android'},
    );
    await tester.pumpAndSettle();

    expect(find.text('Hermes Android'), findsOneWidget);
  });

  testWidgets('a calm state replaces an empty list when nothing needs you', (
    tester,
  ) async {
    await _pump(tester, loadSessions: () async => const <Session>[]);
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.byType(ErrorState), findsNothing);
    expect(find.textContaining('Nothing needs you'), findsOneWidget);
  });

  testWidgets('a first read that fails offers a retry that recovers', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      loadSessions: () async {
        calls++;
        if (calls == 1) throw Exception('offline');
        return [_session(id: 's1', title: 'Roadmap')];
      },
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('Roadmap'), findsOneWidget);
  });

  testWidgets(
    'a later failure keeps the last known Home behind an offline notice',
    (tester) async {
      var calls = 0;
      await _pump(
        tester,
        loadSessions: () async {
          calls++;
          if (calls == 1) return [_session(id: 's1', title: 'Roadmap')];
          throw Exception('offline');
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('Roadmap'), findsOneWidget);

      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 320),
        1000,
      );
      await tester.pumpAndSettle();

      expect(calls, greaterThan(1));
      // Losing the network must never blank the screen the user relies on.
      expect(find.text('Roadmap'), findsOneWidget);
      expect(find.byType(ErrorState), findsNothing);
      expect(find.textContaining('Offline'), findsOneWidget);
    },
  );

  testWidgets('a capped section reports what it hid', (tester) async {
    await _pump(
      tester,
      loadSessions: () async => [
        for (var index = 0; index < kHomeSectionLimit + 2; index++)
          _session(
            id: 'blocked-$index',
            title: 'Blocked $index',
            startedAgo: Duration(minutes: index),
          ),
      ],
      attention: {
        for (var index = 0; index < kHomeSectionLimit + 2; index++)
          'blocked-$index': 'Approval needed',
      },
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('2 more'), findsOneWidget);
  });

  testWidgets('tapping a row reports the session to the host', (tester) async {
    final opened = <Session>[];
    await _pump(
      tester,
      loadSessions: () async => [_session(id: 's1', title: 'Roadmap')],
      onOpenSession: opened.add,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Roadmap'));
    await tester.pumpAndSettle();

    expect(opened.map((session) => session.id), ['s1']);
  });

  testWidgets('a stale attention id cannot conjure a row', (tester) async {
    await _pump(
      tester,
      loadSessions: () async => [_session(id: 's1', title: 'Roadmap')],
      attention: const {'ghost': 'Approval needed'},
    );
    await tester.pumpAndSettle();

    expect(find.text(HomeSectionKind.needsYou.title), findsNothing);
    expect(find.text('Roadmap'), findsOneWidget);
  });
}
