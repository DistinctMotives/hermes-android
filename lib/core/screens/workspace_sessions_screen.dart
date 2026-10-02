import 'dart:async';

import 'package:flutter/material.dart';

import '../models/session.dart';
import '../theme/hermes_theme.dart';
import '../utils/relative_time.dart';
import '../widgets/hermes_components.dart';

const kWorkspaceSessionSearchKey = Key('workspace-session-search');

enum WorkspaceSessionView { all, unassigned, archivedQuick, search }

/// The chip filters the Chats browser offers (decision #4 of the final UI
/// spec): every conversation, recent activity, unassigned, and archived.
enum WorkspaceChatsFilter {
  all('All'),
  recent('Recent'),
  unassigned('Unassigned'),
  archived('Archived');

  final String label;
  const WorkspaceChatsFilter(this.label);
}

/// How recently a conversation was last active, for date group headers.
enum ChatDateBucket {
  today('Today'),
  yesterday('Yesterday'),
  thisWeek('This week'),
  earlier('Earlier');

  final String label;
  const ChatDateBucket(this.label);
}

/// How long "Recent" means in the Chats browser.
const Duration kRecentChatsWindow = Duration(days: 7);

/// Machine-generated session sources. The server's `projects.tree`
/// deliberately never claims these (`_PROJECT_TREE_EXCLUDED_SOURCES` in
/// tui_gateway/methods_projects.py), and `filing.suggest` skips them too —
/// automated runs carry no human filing intent. The Unassigned view must
/// mirror that exclusion or every cron run shows up as "unfiled" noise the
/// filing engine can never answer for. The Chats browser excludes them from
/// every chip (desktop parity): cron runs are browsed per-job from the
/// Cron screen's run list, not as chat-list entries.
const Set<String> kMachineSessionSources = {'cron', 'kanban', 'oneshot'};

bool isMachineSession(Session session) =>
    kMachineSessionSources.contains(session.source);

/// Assigns a conversation to its date bucket, by calendar day.
ChatDateBucket chatDateBucket(DateTime now, double lastActiveSeconds) {
  final activity = DateTime.fromMillisecondsSinceEpoch(
    (lastActiveSeconds * 1000).round(),
  );
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(activity.year, activity.month, activity.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return ChatDateBucket.today;
  if (diff == 1) return ChatDateBucket.yesterday;
  if (diff < 7) return ChatDateBucket.thisWeek;
  return ChatDateBucket.earlier;
}

/// Filters and sorts the Chats browser list for one chip filter.
///
/// Sorting is always by most recent activity, so a conversation moving up in
/// the list is the honest signal that it changed. [now] is injectable so the
/// "Recent" window and date buckets are deterministic in tests.
List<Session> filterChats({
  required List<Session> sessions,
  required WorkspaceChatsFilter filter,
  Set<String> claimedSessionIds = const {},
  Set<String> archivedQuickChatIds = const {},
  String query = '',
  DateTime? now,
  bool projectsKnown = true,
}) {
  final current = now ?? DateTime.now();
  final normalized = query.trim().toLowerCase();
  final recentCutoff =
      current.subtract(kRecentChatsWindow).millisecondsSinceEpoch / 1000.0;

  final filtered = [
    for (final session in sessions)
      if (switch (filter) {
            // Machine-generated runs (cron/kanban/oneshot) never enter the
            // chat browser at all — the desktop's sidebar applies the same
            // exclusion (SIDEBAR_EXCLUDED_SOURCES in
            // use-session-list-actions.ts). Cron runs live in the Cron
            // screen's per-job run list instead, so the scheduler's
            // always-newest sessions can't crowd human chats out.
            WorkspaceChatsFilter.all =>
              !session.archived && !isMachineSession(session),
            WorkspaceChatsFilter.recent =>
              !session.archived &&
                  !isMachineSession(session) &&
                  session.lastActive >= recentCutoff,
            WorkspaceChatsFilter.unassigned =>
              // When the claim map is unknown (projects.tree timed out),
              // every chat would pass as 'unassigned' — a lie that turns
              // the whole archive into filing noise. Show none instead;
              // the UI surfaces the read failure.
              projectsKnown &&
                  !session.archived &&
                  !isMachineSession(session) &&
                  !claimedSessionIds.contains(session.id),
            WorkspaceChatsFilter.archived =>
              // Machine runs stay excluded even once archived — an archived
              // cron run is still cron noise, and its home is the Cron
              // screen's run drill-down. Quick-chat archives are human
              // rows and stay.
              !isMachineSession(session) &&
                  (session.archived ||
                      archivedQuickChatIds.contains(session.id)),
          } &&
          (normalized.isEmpty ||
              session.title.toLowerCase().contains(normalized) ||
              session.preview.toLowerCase().contains(normalized) ||
              session.id.toLowerCase().contains(normalized) ||
              session.model.toLowerCase().contains(normalized)))
        session,
  ]..sort((a, b) => b.lastActive.compareTo(a.lastActive));
  return filtered;
}

/// Groups conversations into date buckets, newest bucket first.
List<MapEntry<ChatDateBucket, List<Session>>> groupChatsByDate(
  DateTime now,
  List<Session> sessions,
) {
  final buckets = <ChatDateBucket, List<Session>>{
    for (final bucket in ChatDateBucket.values) bucket: <Session>[],
  };
  for (final session in sessions) {
    buckets[chatDateBucket(now, session.lastActive)]!.add(session);
  }
  return [
    for (final bucket in ChatDateBucket.values)
      if (buckets[bucket]!.isNotEmpty)
        MapEntry(bucket, List.unmodifiable(buckets[bucket]!)),
  ];
}

class WorkspaceSessionsData {
  final List<Session> sessions;
  final Set<String> claimedSessionIds;
  final Set<String> archivedQuickChatIds;

  /// Server-archived sessions, fetched from the dashboard's
  /// `archived=only` router. The gateway chat transport never returns
  /// archived rows, so without this the Archived chip only ever showed
  /// quick-chat expiries. Empty when the dashboard is unreachable — the
  /// chip then degrades to quick-chat-only rather than lying.
  final List<Session> archivedSessions;

  /// Best-effort session id → project label mapping.
  ///
  /// Built from the server `projects.tree` preview rows; a conversation whose
  /// project is unknown stays honest as "Unassigned" in the UI.
  final Map<String, String> projectLabels;

  /// Whether the claim map above actually reflects the server. False when
  /// `projects.tree` timed out or failed: an empty `claimedSessionIds` then
  /// means "unknown", not "nothing is filed", and the Unassigned chip must
  /// say so instead of presenting the whole archive as unfiled noise.
  final bool projectsKnown;

  const WorkspaceSessionsData({
    this.sessions = const [],
    this.claimedSessionIds = const {},
    this.archivedQuickChatIds = const {},
    this.archivedSessions = const [],
    this.projectLabels = const {},
    this.projectsKnown = true,
  });
}

typedef WorkspaceSessionsLoader = Future<WorkspaceSessionsData> Function();

/// Moves a session and returns the destination Project label. Returning the
/// label lets the row update ownership and presentation in one state change,
/// without waiting for a second projects.tree request.
typedef WorkspaceSessionPromoter = Future<String> Function(Session session);

class QuickChatPromotionCancelled implements Exception {
  const QuickChatPromotionCancelled();
}

List<Session> filterWorkspaceSessions({
  required List<Session> sessions,
  required WorkspaceSessionView view,
  Set<String> claimedSessionIds = const {},
  Set<String> archivedQuickChatIds = const {},
  String query = '',
  bool projectsKnown = true,
}) {
  final normalized = query.trim().toLowerCase();
  return [
    for (final session in sessions)
      if (switch (view) {
            // Same contract as filterChats' unassigned chip: an unknown
            // claim map (projects.tree timed out) must not render every
            // chat as unfiled, and machine-source runs (cron/kanban/
            // oneshot) carry no human filing intent — they live in the
            // Cron screen's run drill-down, never in the Unassigned
            // bucket.
            WorkspaceSessionView.unassigned =>
              projectsKnown &&
                  !isMachineSession(session) &&
                  !claimedSessionIds.contains(session.id),
            WorkspaceSessionView.archivedQuick => archivedQuickChatIds.contains(
              session.id,
            ),
            // Machine sessions stay out of every human-facing list, the
            // archived view included — an archived cron run is still
            // cron noise. Quick-chat archives are human rows and stay.
            WorkspaceSessionView.all ||
            WorkspaceSessionView.search => !isMachineSession(session),
          } &&
          (normalized.isEmpty ||
              session.title.toLowerCase().contains(normalized) ||
              session.preview.toLowerCase().contains(normalized) ||
              session.id.toLowerCase().contains(normalized) ||
              session.model.toLowerCase().contains(normalized)))
        session,
  ];
}

class WorkspaceSessionsScreen extends StatefulWidget {
  final String title;
  final WorkspaceSessionView view;
  final WorkspaceSessionsLoader load;
  final ValueChanged<Session> onOpenSession;
  final WorkspaceSessionPromoter? onPromote;
  final bool embedded;

  /// Clock injection for deterministic filter/date tests. When null the
  /// screen uses `DateTime.now()`.
  final DateTime? now;

  const WorkspaceSessionsScreen({
    required this.title,
    required this.view,
    required this.load,
    required this.onOpenSession,
    this.onPromote,
    this.embedded = false,
    this.now,
    super.key,
  });

  @override
  State<WorkspaceSessionsScreen> createState() =>
      _WorkspaceSessionsScreenState();
}

class _WorkspaceSessionsScreenState extends State<WorkspaceSessionsScreen> {
  WorkspaceSessionsData? _data;
  Object? _error;
  String _query = '';
  final Set<String> _promoting = {};

  /// The active chip filter in the embedded Chats browser.
  WorkspaceChatsFilter _filter = WorkspaceChatsFilter.all;

  /// Injectable clock for deterministic tests.
  DateTime get _now => widget.now ?? DateTime.now();

  /// Whether the current surface is an Unassigned one (standalone view or
  /// the embedded chip browser with the Unassigned chip active).
  bool get _isUnassignedSurface =>
      widget.view == WorkspaceSessionView.unassigned ||
      (widget.embedded && _filter == WorkspaceChatsFilter.unassigned);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final data = await widget.load();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (error) {
      debugPrint('[workspace-sessions] load failed: $error');
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _promote(Session session) async {
    final promote = widget.onPromote;
    if (promote == null || _promoting.contains(session.id)) return;
    setState(() => _promoting.add(session.id));
    try {
      final projectLabel = await promote(session);
      if (!mounted) return;
      final data = _data;
      if (data != null) {
        setState(() {
          _data = WorkspaceSessionsData(
            sessions: data.sessions,
            // The move claims the chat: add it to the claim set so the
            // Unassigned view drops the row immediately instead of
            // waiting for the next reload.
            claimedSessionIds: {...data.claimedSessionIds, session.id},
            archivedQuickChatIds: {
              for (final id in data.archivedQuickChatIds)
                if (id != session.id) id,
            },
            // Ownership and its visible label are one piece of state. Updating
            // only claimedSessionIds made the row disappear from Unassigned,
            // then show "Unassigned" when All was selected immediately.
            projectLabels: {...data.projectLabels, session.id: projectLabel},
            archivedSessions: data.archivedSessions,
            projectsKnown: data.projectsKnown,
          );
          _promoting.remove(session.id);
        });
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Moved to a Project')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _promoting.remove(session.id));
      if (error is QuickChatPromotionCancelled) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          persist: false,
          content: const Text('Couldn’t promote conversation'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => unawaited(_promote(session)),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final body = data == null
        ? _error == null
              ? const Padding(
                  padding: EdgeInsets.only(top: HermesSpacing.lg),
                  child: LoadingSkeleton(rows: 5),
                )
              : ErrorState(
                  title: 'Could not load conversations',
                  message: 'Check the connection and try again.',
                  onRetry: _load,
                )
        : _buildLoaded(data);
    if (widget.embedded) {
      return Material(color: Colors.transparent, child: body);
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: body,
    );
  }

  Widget _buildLoaded(WorkspaceSessionsData data) {
    // The embedded browser filters over the union of the gateway's active
    // list and the dashboard's archived list: the Archived chip needs the
    // archived rows, and every other chip explicitly excludes
    // `session.archived`, so the union cannot leak them into All/Recent/
    // Unassigned. The two lists come from different backends at
    // different instants, so dedupe by id — the archived copy wins for
    // a session archived between the two fetches.
    final archivedIds = data.archivedSessions.map((s) => s.id).toSet();
    final unionSessions = <Session>[
      for (final s in data.sessions)
        if (!archivedIds.contains(s.id)) s,
      ...data.archivedSessions,
    ];
    final sessions = widget.embedded
        ? filterChats(
            sessions: unionSessions,
            filter: _filter,
            claimedSessionIds: data.claimedSessionIds,
            archivedQuickChatIds: data.archivedQuickChatIds,
            query: _query,
            now: _now,
            projectsKnown: data.projectsKnown,
          )
        : filterWorkspaceSessions(
            sessions: data.sessions,
            view: widget.view,
            claimedSessionIds: data.claimedSessionIds,
            archivedQuickChatIds: data.archivedQuickChatIds,
            query: _query,
            projectsKnown: data.projectsKnown,
          );

    final groups = widget.embedded
        ? groupChatsByDate(_now, sessions)
        : [
            MapEntry(
              ChatDateBucket.today,
              List<Session>.unmodifiable(sessions),
            ),
          ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          HermesSpacing.lg,
          HermesSpacing.md,
          HermesSpacing.lg,
          HermesSpacing.xl,
        ),
        children: [
          TextField(
            key: kWorkspaceSessionSearchKey,
            autofocus: widget.view == WorkspaceSessionView.search,
            decoration: InputDecoration(
              hintText: 'Search conversations',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => setState(() => _query = ''),
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          if (widget.embedded) ...[
            const SizedBox(height: HermesSpacing.md),
            _buildChips(),
          ],
          const SizedBox(height: HermesSpacing.lg),
          if (sessions.isEmpty)
            EmptyState(
              icon: _emptyIcon,
              title: _query.isEmpty ? 'Nothing here' : 'No matches',
              message: _emptyMessage,
            )
          else
            for (final group in groups) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: HermesSpacing.xs,
                  bottom: HermesSpacing.sm,
                ),
                child: Text(
                  widget.embedded ? group.key.label : widget.title,
                  style: HermesTokens.of(context).typography.section,
                ),
              ),
              for (final session in group.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: HermesSpacing.sm),
                  child: _buildSessionRow(session, data),
                ),
            ],
        ],
      ),
    );
  }

  Widget _buildChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in WorkspaceChatsFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: HermesSpacing.sm),
              child: ChoiceChip(
                label: Text(filter.label),
                selected: _filter == filter,
                onSelected: (_) => setState(() {
                  _filter = filter;
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(Session session, WorkspaceSessionsData data) {
    final tokens = HermesTokens.of(context);
    final projectLabel = data.projectLabels[session.id];
    // The move-to-project affordance serves the Archived-Quick view
    // (promote a lapsed quick chat) and any Unassigned surface — the
    // standalone view or the embedded chip browser with the Unassigned
    // chip active. Both call the same repository move.
    final showPromote =
        (widget.view == WorkspaceSessionView.archivedQuick ||
            _isUnassignedSurface) &&
        widget.onPromote != null;
    return HermesCard(
      onTap: () => widget.onOpenSession(session),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            session.pinned
                ? Icons.push_pin_outlined
                : Icons.chat_bubble_outline,
            size: 20,
            color: session.pinned ? tokens.accent : tokens.muted,
          ),
          const SizedBox(width: HermesSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title.isEmpty ? 'Untitled chat' : session.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (session.preview.isNotEmpty)
                  Text(
                    session.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.muted),
                  ),
                const SizedBox(height: HermesSpacing.xs),
                Wrap(
                  spacing: HermesSpacing.sm,
                  runSpacing: HermesSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(
                      status: session.isActive
                          ? HermesStatus.running
                          : HermesStatus.completed,
                      label: session.isActive ? 'Running' : 'Done',
                    ),
                    if (projectLabel != null)
                      _MetaChip(
                        label: projectLabel,
                        icon: Icons.folder_outlined,
                      )
                    else if (data.projectsKnown)
                      _MetaChip(
                        label: 'Unassigned',
                        icon: Icons.inbox_outlined,
                      ),
                    Text(
                      _relativeTime(_now, session.lastActive),
                      style: tokens.typography.label.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (showPromote)
            _promoting.contains(session.id)
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: _isUnassignedSurface
                        ? 'Move to project'
                        : 'Promote to project',
                    onPressed: () => unawaited(_promote(session)),
                    icon: const Icon(Icons.drive_file_move_outline),
                  ),
        ],
      ),
    );
  }

  IconData get _emptyIcon {
    if (widget.embedded) {
      return switch (_filter) {
        WorkspaceChatsFilter.unassigned => Icons.inbox_outlined,
        WorkspaceChatsFilter.archived => Icons.archive_outlined,
        WorkspaceChatsFilter.recent => Icons.history_outlined,
        WorkspaceChatsFilter.all => Icons.search_off,
      };
    }
    return widget.view == WorkspaceSessionView.unassigned
        ? Icons.inbox_outlined
        : Icons.search_off;
  }

  String get _emptyMessage {
    if (widget.embedded) {
      return switch (_filter) {
        WorkspaceChatsFilter.unassigned =>
          'Every conversation is already assigned to a Project.',
        WorkspaceChatsFilter.archived => 'Archived conversations appear here.',
        WorkspaceChatsFilter.recent =>
          'Nothing changed in the last seven days.',
        WorkspaceChatsFilter.all => 'No conversation matches this view.',
      };
    }
    return switch (widget.view) {
      WorkspaceSessionView.unassigned =>
        'Every conversation is already assigned to a Project.',
      WorkspaceSessionView.archivedQuick =>
        'Quick chats appear here after their retention period.',
      WorkspaceSessionView.all ||
      WorkspaceSessionView.search => 'No conversation matches this view.',
    };
  }

  /// Compact relative time: "now", "5m", "2h", "3d", else a date.
  String _relativeTime(DateTime now, double lastActiveSeconds) =>
      formatRelativeTime(now, lastActiveSeconds);
}

/// A small neutral label under a conversation row (project, unassigned).
class _MetaChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _MetaChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Semantics(
      label: label,
      container: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: HermesSpacing.sm,
            vertical: HermesSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: tokens.raised,
            borderRadius: BorderRadius.circular(HermesRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: tokens.muted),
              const SizedBox(width: 4),
              Text(label, style: tokens.typography.label),
            ],
          ),
        ),
      ),
    );
  }
}
