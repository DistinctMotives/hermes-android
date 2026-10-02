import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';

Session _session(
  String id,
  String title, {
  double? lastActive,
  bool archived = false,
  bool isActive = false,
  bool pinned = false,
  String source = 'gateway',
}) => Session(
  id: id,
  title: title,
  model: 'claude-opus-5',
  source: source,
  messageCount: 1,
  isActive: isActive,
  preview: 'preview $title',
  startedAt: 1750000000,
  lastActive: lastActive ?? 1750000000,
  archived: archived,
  pinned: pinned,
);

void main() {
  test('Unassigned excludes every server-scoped session', () {
    final result = filterWorkspaceSessions(
      sessions: [_session('s1', 'Filed'), _session('s2', 'Inbox')],
      view: WorkspaceSessionView.unassigned,
      claimedSessionIds: const {'s1'},
    );
    expect(result.map((session) => session.id), ['s2']);
  });

  group('WorkspaceChatsFilter', () {
    test('declares the four validated chip filters in order', () {
      expect(WorkspaceChatsFilter.values, [
        WorkspaceChatsFilter.all,
        WorkspaceChatsFilter.recent,
        WorkspaceChatsFilter.unassigned,
        WorkspaceChatsFilter.archived,
      ]);
      for (final filter in WorkspaceChatsFilter.values) {
        expect(filter.label, isNotEmpty);
      }
    });

    test('All keeps every non-archived session', () {
      final result = filterChats(
        sessions: [_session('s1', 'A'), _session('s2', 'B')],
        filter: WorkspaceChatsFilter.all,
        now: DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000),
      );
      expect(result.map((s) => s.id), ['s1', 's2']);
    });

    test('All, Recent and Unassigned hide server-archived sessions', () {
      // The Chats browser feeds the filter the union of the gateway's
      // active list and the dashboard's archived list; the non-archived
      // chips must therefore exclude archived rows explicitly or the
      // union would leak them.
      final live = _session('s1', 'Live');
      final archived = _session('s2', 'Archived', archived: true);
      final now = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000);

      for (final filter in [
        WorkspaceChatsFilter.all,
        WorkspaceChatsFilter.recent,
        WorkspaceChatsFilter.unassigned,
      ]) {
        final result = filterChats(
          sessions: [live, archived],
          filter: filter,
          now: now,
        );
        expect(result.map((s) => s.id), ['s1'], reason: filter.label);
      }
    });

    test('Recent keeps only sessions active within seven days', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000);
      final recent = _session('s1', 'Fresh', lastActive: 1750000000);
      final old = _session('s2', 'Stale', lastActive: 1745000000);

      final result = filterChats(
        sessions: [old, recent],
        filter: WorkspaceChatsFilter.recent,
        now: now,
      );

      expect(result.map((s) => s.id), ['s1']);
    });

    test('Unassigned excludes claimed sessions', () {
      final result = filterChats(
        sessions: [_session('s1', 'Filed'), _session('s2', 'Inbox')],
        filter: WorkspaceChatsFilter.unassigned,
        claimedSessionIds: const {'s1'},
        now: DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000),
      );
      expect(result.map((s) => s.id), ['s2']);
    });

    test('Unassigned hides machine-generated sessions', () {
      // projects.tree never claims cron/kanban/oneshot rows, so without
      // this exclusion every automated run piles up as unfilable
      // "unassigned" noise the filing engine can never answer for.
      final human = _session('s1', 'Human chat');
      final cron = _session('s2', 'Cron run', source: 'cron');
      final kanban = _session('s3', 'Kanban run', source: 'kanban');
      final oneshot = _session('s4', 'Oneshot run', source: 'oneshot');

      final result = filterChats(
        sessions: [human, cron, kanban, oneshot],
        filter: WorkspaceChatsFilter.unassigned,
        now: DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000),
      );
      expect(result.map((s) => s.id), ['s1']);
    });

    test('All and Recent hide machine sessions (desktop parity)', () {
      // Cron/kanban/oneshot runs are excluded from every chat chip, not
      // just Unassigned — the desktop sidebar drops these sources from
      // recents entirely so the scheduler's always-newest sessions can't
      // crowd human chats out. Cron runs are browsed per-job from the
      // Cron screen instead.
      final human = _session('s1', 'Human chat');
      final cron = _session('s2', 'Cron run', source: 'cron');
      final kanban = _session('s3', 'Kanban run', source: 'kanban');
      final now = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000);

      final all = filterChats(
        sessions: [human, cron, kanban],
        filter: WorkspaceChatsFilter.all,
        now: now,
      );
      expect(all.map((s) => s.id).toSet(), {'s1'});

      final recent = filterChats(
        sessions: [human, cron, kanban],
        filter: WorkspaceChatsFilter.recent,
        now: now,
      );
      expect(recent.map((s) => s.id).toSet(), {'s1'});
    });

    test('Archived merges server-archived and quick-chat archived ids', () {
      final server = _session('s1', 'Server archived', archived: true);
      final quick = _session('s2', 'Quick archived');
      final live = _session('s3', 'Live');

      final result = filterChats(
        sessions: [live, server, quick],
        filter: WorkspaceChatsFilter.archived,
        archivedQuickChatIds: const {'s2'},
        now: DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000),
      );

      expect(result.map((s) => s.id).toSet(), {'s1', 's2'});
    });

    test('query narrows the active filter', () {
      final result = filterChats(
        sessions: [_session('s1', 'Migration'), _session('s2', 'Taxes')],
        filter: WorkspaceChatsFilter.all,
        query: 'migration',
        now: DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000),
      );
      expect(result.map((s) => s.id), ['s1']);
    });
  });

  group('chatDateBucket', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000);
    final today = now.millisecondsSinceEpoch / 1000.0;
    final yesterday =
        now.subtract(const Duration(days: 1)).millisecondsSinceEpoch / 1000.0;
    final thisWeek =
        now.subtract(const Duration(days: 3)).millisecondsSinceEpoch / 1000.0;
    final earlier =
        now.subtract(const Duration(days: 20)).millisecondsSinceEpoch / 1000.0;

    test('buckets by age', () {
      expect(chatDateBucket(now, today), ChatDateBucket.today);
      expect(chatDateBucket(now, yesterday), ChatDateBucket.yesterday);
      expect(chatDateBucket(now, thisWeek), ChatDateBucket.thisWeek);
      expect(chatDateBucket(now, earlier), ChatDateBucket.earlier);
    });

    test('groupChatsByDate returns buckets in order with labels', () {
      final groups = groupChatsByDate(now, [
        _session('s1', 'old', lastActive: earlier),
        _session('s2', 'fresh', lastActive: today),
      ]);
      expect(groups.length, 2);
      expect(groups[0].key, ChatDateBucket.today);
      expect(groups[0].value.map((s) => s.id), ['s2']);
      expect(groups[1].key, ChatDateBucket.earlier);
      expect(groups[1].value.map((s) => s.id), ['s1']);
    });

    test('bucket labels are human readable', () {
      expect(ChatDateBucket.today.label, 'Today');
      expect(ChatDateBucket.yesterday.label, 'Yesterday');
      expect(ChatDateBucket.thisWeek.label, 'This week');
      expect(ChatDateBucket.earlier.label, 'Earlier');
    });
  });

  test(
    'Archived Quick shows only archived quick chats and stays searchable',
    () {
      final sessions = [
        _session('s1', 'Old research'),
        _session('s2', 'Current'),
      ];
      final result = filterWorkspaceSessions(
        sessions: sessions,
        view: WorkspaceSessionView.archivedQuick,
        archivedQuickChatIds: const {'s1'},
        query: 'research',
      );
      expect(result.map((session) => session.id), ['s1']);
    },
  );

  testWidgets('embedded mode reuses the browser without a nested scaffold', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceSessionsScreen(
          title: 'Chats',
          view: WorkspaceSessionView.all,
          embedded: true,
          load: () async =>
              WorkspaceSessionsData(sessions: [_session('s1', 'Daily driver')]),
          onOpenSession: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(kWorkspaceSessionSearchKey), findsOneWidget);
    expect(find.text('Daily driver'), findsOneWidget);
  });

  group('the Chats chip filters', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000);
    final recent = _session('s1', 'Fresh', lastActive: 1750000000);
    final old = _session('s2', 'Stale', lastActive: 1745000000);
    final claimed = _session('s3', 'Filed');
    final quickArchived = _session('s4', 'Quick archived');

    Future<void> pumpChats(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: hermesTheme(Brightness.dark),
          home: WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            now: now,
            load: () async => WorkspaceSessionsData(
              sessions: [recent, old, claimed, quickArchived],
              claimedSessionIds: const {'s3'},
              archivedQuickChatIds: const {'s4'},
            ),
            onOpenSession: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers the four validated chips in embedded mode', (
      tester,
    ) async {
      await pumpChats(tester);

      for (final filter in WorkspaceChatsFilter.values) {
        expect(find.widgetWithText(ChoiceChip, filter.label), findsOneWidget);
      }
    });

    testWidgets('Recent shows only sessions active within the window', (
      tester,
    ) async {
      await pumpChats(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Recent'));
      await tester.pumpAndSettle();

      expect(find.text('Fresh'), findsOneWidget);
      expect(find.text('Stale'), findsNothing);
    });

    testWidgets('Unassigned shows only non-claimed sessions', (tester) async {
      await pumpChats(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Unassigned'));
      await tester.pumpAndSettle();

      expect(find.text('Filed'), findsNothing);
      expect(find.text('Fresh'), findsOneWidget);
    });

    testWidgets('Archived shows quick-archived sessions', (tester) async {
      await pumpChats(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await tester.pumpAndSettle();

      expect(find.text('Quick archived'), findsOneWidget);
      expect(find.text('Fresh'), findsNothing);
    });

    testWidgets('Archived shows server-archived sessions from the dashboard', (
      tester,
    ) async {
      // The gateway's active list never contains archived rows, so the
      // dashboard-sourced archivedSessions list is the only way an
      // explicitly archived chat reaches the chip. It must show under
      // Archived and stay hidden under All.
      final serverArchived = _session(
        's9',
        'Archived on server',
        archived: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: hermesTheme(Brightness.dark),
          home: WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            now: now,
            load: () async => WorkspaceSessionsData(
              sessions: [recent],
              archivedSessions: [serverArchived],
            ),
            onOpenSession: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Archived on server'), findsNothing);
      expect(find.text('Fresh'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await tester.pumpAndSettle();

      expect(find.text('Archived on server'), findsOneWidget);
      expect(find.text('Fresh'), findsNothing);
    });

    testWidgets('groups rows under date headers', (tester) async {
      await pumpChats(tester);

      expect(find.text(ChatDateBucket.today.label), findsOneWidget);
      expect(find.text(ChatDateBucket.earlier.label), findsOneWidget);
    });
  });

  group('the conversation rows', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000);

    Future<void> pumpRows(
      WidgetTester tester, {
      List<Session> sessions = const [],
      Map<String, String> projectLabels = const {},
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: hermesTheme(Brightness.dark),
          home: WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            now: now,
            load: () async => WorkspaceSessionsData(
              sessions: sessions,
              projectLabels: projectLabels,
            ),
            onOpenSession: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('marks a running session and a finished one', (tester) async {
      await pumpRows(
        tester,
        sessions: [
          _session('s1', 'Building', isActive: true, lastActive: 1750000000),
          _session('s2', 'Finished', lastActive: 1749990000),
        ],
      );

      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('labels the project when known, Unassigned otherwise', (
      tester,
    ) async {
      await pumpRows(
        tester,
        sessions: [
          _session('s1', 'In project', lastActive: 1750000000),
          _session('s2', 'Loose', lastActive: 1749990000),
        ],
        projectLabels: const {'s1': 'Hermes Android'},
      );

      expect(find.text('Hermes Android'), findsOneWidget);
      // The Unassigned chip plus the row meta-chip are both present; the
      // row-level marker is the inbox icon.
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    });

    testWidgets('shows the pinned marker', (tester) async {
      await pumpRows(
        tester,
        sessions: [
          _session('s1', 'Pinned chat', lastActive: 1750000000, pinned: true),
        ],
      );

      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    });
  });

  testWidgets('search opens a result and Archived Quick offers Promote', (
    tester,
  ) async {
    final opened = <String>[];
    final promoted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceSessionsScreen(
          title: 'Archived Quick chats',
          view: WorkspaceSessionView.archivedQuick,
          load: () async => WorkspaceSessionsData(
            sessions: [_session('s1', 'Old research')],
            archivedQuickChatIds: const {'s1'},
          ),
          onOpenSession: (session) => opened.add(session.id),
          onPromote: (session) async {
            promoted.add(session.id);
            return 'Project';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Old research'), findsOneWidget);
    await tester.enterText(find.byKey(kWorkspaceSessionSearchKey), 'old');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Old research'));
    expect(opened, ['s1']);

    await tester.tap(find.byTooltip('Promote to project'));
    await tester.pumpAndSettle();
    expect(promoted, ['s1']);
    expect(find.text('Old research'), findsNothing);
  });

  testWidgets('Unassigned rows offer Move to project and drop on move', (
    tester,
  ) async {
    final moved = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceSessionsScreen(
          title: 'Unassigned chats',
          view: WorkspaceSessionView.unassigned,
          load: () async => WorkspaceSessionsData(
            sessions: [
              _session('s1', 'Loose chat'),
              _session('s2', 'Also loose'),
            ],
          ),
          onOpenSession: (_) {},
          onPromote: (session) async {
            moved.add(session.id);
            return 'Project';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Loose chat'), findsOneWidget);
    await tester.tap(find.byTooltip('Move to project').first);
    await tester.pumpAndSettle();

    expect(moved, ['s1']);
    // The moved chat leaves the Unassigned list immediately (claimed);
    // the other stays.
    expect(find.text('Loose chat'), findsNothing);
    expect(find.text('Also loose'), findsOneWidget);
  });

  testWidgets('moving a chat updates its project label before showing All', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hermesTheme(Brightness.dark),
        home: Scaffold(
          body: WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            load: () async => WorkspaceSessionsData(
              sessions: [_session('s1', 'Loose chat')],
              archivedSessions: [
                _session('s2', 'Archived chat', archived: true),
              ],
            ),
            onOpenSession: (_) {},
            onPromote: (_) async => 'Hermes Android',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Unassigned'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move to project'));
    await tester.pumpAndSettle();
    expect(find.text('Loose chat'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.text('Loose chat'),
      matching: find.byType(HermesCard),
    );
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Hermes Android')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Unassigned')),
      findsNothing,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
    await tester.pumpAndSettle();
    expect(find.text('Archived chat'), findsOneWidget);
  });
}
