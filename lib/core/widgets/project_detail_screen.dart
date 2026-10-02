/// The project detail screen: Overview and Chats for one server-owned project.
///
/// `ProjectsRepository.projectSessions` and the `projects.project_sessions`
/// RPC beneath it were both delivered before anything rendered them, so a
/// project card in [ProjectsPane] had nowhere to go. This screen is that
/// destination.
///
/// Two decisions are worth stating because they are easy to get wrong later:
///
/// * **Counts come from the server, never from the rows on screen.** The
///   overview tier of `projects.tree` deliberately ships lanes with their
///   session rows emptied, so deriving a count from what is rendered would
///   make every project report zero chats.
/// * **A failed re-read is not a failed screen.** The first read owns the
///   error state; every later failure keeps the chats already visible behind
///   an offline notice, because losing the network must never blank a screen
///   the user is reading.
///
/// See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md` (Phase 1).
library;

import 'package:flutter/material.dart';

import '../models/hermes_project.dart';
import '../models/project_sessions_tree.dart';
import '../models/session.dart';
import '../services/projects_repository.dart';
import '../theme/hermes_theme.dart';
import '../utils/project_session_filter.dart';
import '../utils/relative_time.dart';
import 'hermes_components.dart';

/// Reads one project's chats. Mirrors `ProjectsRepository.projectSessions` so
/// the screen can be driven by a fake in tests without a gateway.
typedef ProjectSessionsLoader =
    Future<ProjectSessionsView> Function({required bool refresh});
typedef ProjectSessionMover =
    Future<String?> Function(Session session, String? projectId);
typedef ProjectRenamer = Future<void> Function(String name);
typedef ProjectArchiver = Future<void> Function();
typedef ProjectDeleter = Future<void> Function();

const kProjectNewChatButtonKey = Key('project-detail-new-chat');
const kProjectSearchFieldKey = Key('project-detail-search');

class ProjectDetailScreen extends StatefulWidget {
  final String projectId;

  /// Shown in the app bar before the first read lands, so the screen never
  /// opens on the word "Untitled".
  final String projectName;

  final ProjectSessionsLoader loadSessions;

  /// Opens one chat. When null the rows are drawn inert rather than
  /// fake-tappable.
  final ValueChanged<Session>? onOpenSession;

  /// Starts a chat already scoped to this Project.
  final VoidCallback? onNewChat;

  /// Server Projects offered as move destinations for existing chats.
  final List<HermesProject> projects;
  final ProjectSessionMover? onMoveSession;

  /// Reversible Project administration backed by the Gateway.
  final ProjectRenamer? onRenameProject;
  final ProjectArchiver? onArchiveProject;

  /// Permanently removes this server Project. Its chat sessions survive and
  /// become Unassigned because the Gateway deletes only their assignments.
  final ProjectDeleter? onDeleteProject;

  const ProjectDetailScreen({
    required this.projectId,
    required this.projectName,
    required this.loadSessions,
    this.onOpenSession,
    this.onNewChat,
    this.projects = const [],
    this.onMoveSession,
    this.onRenameProject,
    this.onArchiveProject,
    this.onDeleteProject,
    super.key,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);

  ProjectSessionsView? _view;

  /// True until the first read resolves, which is what separates a retryable
  /// first failure from a refresh failure over content.
  bool _loading = true;

  /// Per-Project search: filters the sessions the server already returned.
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _deleting = false;
  bool _managing = false;
  late String _projectName;

  @override
  void initState() {
    super.initState();
    _projectName = widget.projectName;
    _load(refresh: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
  }

  Future<void> _load({required bool refresh}) async {
    try {
      final view = await widget.loadSessions(refresh: refresh);
      if (!mounted) return;
      setState(() {
        _view = view;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      // The repository already reports failures inside the view; this guards
      // the loader contract itself so a throw cannot leave a stuck skeleton.
      setState(() {
        _view = ProjectSessionsView(projectId: widget.projectId, error: error);
        _loading = false;
      });
    }
  }

  Future<void> _chooseMoveDestination(Session session) async {
    final target = await showModalBottomSheet<_MoveTarget>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                HermesSpacing.lg,
                HermesSpacing.lg,
                HermesSpacing.lg,
                HermesSpacing.sm,
              ),
              child: Text('Move conversation'),
            ),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Unassigned'),
              onTap: () => Navigator.pop(
                context,
                const _MoveTarget(projectId: null, label: 'Unassigned'),
              ),
            ),
            for (final project in widget.projects)
              if (!project.archived && project.id != widget.projectId)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(project.name),
                  onTap: () => Navigator.pop(
                    context,
                    _MoveTarget(projectId: project.id, label: project.name),
                  ),
                ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    await _moveSession(session, target);
  }

  Future<void> _moveSession(Session session, _MoveTarget target) async {
    try {
      final reason = await widget.onMoveSession!(session, target.projectId);
      if (!mounted) return;
      if (reason != null) {
        // The gateway could not perform this move (e.g. a stock gateway
        // files chats by folder and cannot un-file one). Report the real
        // reason instead of a generic failure with a doomed Retry.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn\u2019t move to ${target.label}: $reason')),
        );
        return;
      }
      await _load(refresh: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Moved to ${target.label}')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          persist: false,
          content: const Text('Couldn’t move conversation'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _moveSession(session, target),
          ),
        ),
      );
    }
  }

  Future<void> _renameProject() async {
    final rename = widget.onRenameProject;
    if (rename == null || _managing) return;
    var draft = _projectName;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Rename $_projectName'),
        content: TextFormField(
          key: const Key('rename-project-name'),
          initialValue: _projectName,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (value) => draft = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = draft.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name == null || !mounted || name == _projectName) return;
    setState(() => _managing = true);
    try {
      await rename(name);
      if (mounted) {
        setState(() {
          _projectName = name;
          _managing = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _managing = false);
      _showManagementError('rename', _renameProject);
    }
  }

  Future<void> _confirmArchive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Archive $_projectName?'),
        content: const Text(
          'The Project will move to Archived. Its chats and files stay intact, '
          'and you can restore it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _archiveProject();
  }

  Future<void> _archiveProject() async {
    final archive = widget.onArchiveProject;
    if (archive == null || _managing) return;
    setState(() => _managing = true);
    try {
      await archive();
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(true);
      } else {
        setState(() => _managing = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _managing = false);
      _showManagementError('archive', _archiveProject);
    }
  }

  void _showManagementError(String action, Future<void> Function() retry) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        persist: false,
        content: Text('Couldn’t $action project'),
        action: SnackBarAction(label: 'Retry', onPressed: retry),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $_projectName?'),
        content: const Text(
          'This permanently deletes the Project. Chats will not be deleted; '
          'they’ll return to Unassigned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _deleteProject();
  }

  Future<void> _deleteProject() async {
    final delete = widget.onDeleteProject;
    if (delete == null || _deleting) return;
    setState(() => _deleting = true);
    try {
      await delete();
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(true);
      } else {
        // Embedders may mount the detail as their root rather than a route.
        // There is nowhere to return in that case, but the action must still
        // settle instead of leaving an infinite progress indicator.
        setState(() => _deleting = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          persist: false,
          content: const Text('Couldn’t delete project'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _deleteProject(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final title = _projectName;
    final hasActions =
        widget.onRenameProject != null ||
        widget.onArchiveProject != null ||
        widget.onDeleteProject != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (hasActions)
            if (_deleting || _managing)
              const Padding(
                padding: EdgeInsets.all(HermesSpacing.md),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              PopupMenuButton<String>(
                tooltip: 'Project actions',
                onSelected: (action) {
                  switch (action) {
                    case 'rename':
                      _renameProject();
                    case 'archive':
                      _confirmArchive();
                    case 'delete':
                      _confirmDelete();
                  }
                },
                itemBuilder: (context) => [
                  if (widget.onRenameProject != null)
                    const PopupMenuItem<String>(
                      value: 'rename',
                      child: Text('Rename project'),
                    ),
                  if (widget.onArchiveProject != null)
                    const PopupMenuItem<String>(
                      value: 'archive',
                      child: Text('Archive project'),
                    ),
                  if (widget.onDeleteProject != null)
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: HermesSpacing.sm),
                          Text(
                            'Delete project',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Chats'),
            Tab(text: 'Overview'),
            Tab(text: 'Files'),
            Tab(text: 'Assets'),
            Tab(text: 'Activity'),
          ],
          isScrollable: true,
        ),
      ),
      body: _buildBody(view),
      floatingActionButton: widget.onNewChat == null
          ? null
          : FloatingActionButton.extended(
              key: kProjectNewChatButtonKey,
              onPressed: widget.onNewChat,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New chat'),
            ),
    );
  }

  Widget _buildBody(ProjectSessionsView? view) {
    if (_loading || view == null) {
      return const Padding(
        padding: EdgeInsets.only(top: HermesSpacing.lg),
        child: LoadingSkeleton(rows: 4),
      );
    }

    // An older gateway is not a crash and not an empty project: saying "no
    // chats" here would state something this gateway cannot actually know.
    if (view.support == ProjectsSupport.unsupported) {
      return const ErrorState.unsupported(
        title: 'Project chats unavailable',
        message:
            'This Hermes gateway does not support opening a project yet. '
            'Update Hermes on the server to browse a project from your phone.',
      );
    }

    // Only a *first* read with nothing to show is an error screen.
    if (view.error != null && view.sessions.isEmpty && !view.isStale) {
      return ErrorState(
        title: 'Could not open this project',
        message:
            'Check that the gateway is running and reachable, then try again.',
        onRetry: () => _load(refresh: true),
      );
    }

    return TabBarView(
      controller: _tabs,
      children: [
        _buildChats(view),
        _buildOverview(view),
        _buildFiles(view),
        _buildAssets(view),
        _buildActivity(view),
      ],
    );
  }

  Widget _buildChats(ProjectSessionsView view) {
    final sessions = view.sessions;
    final filtered = filterProjectSessions(sessions, _searchQuery);
    final querying = _searchQuery.trim().isNotEmpty;

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: CustomScrollView(
        // Always scrollable, so pull-to-refresh works on an empty project too.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (view.isStale) const SliverToBoxAdapter(child: _OfflineNotice()),
          // The search field exists only when there is something to search.
          // An empty project keeps its honest "No chats yet" state.
          if (sessions.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.lg,
                  HermesSpacing.md,
                  HermesSpacing.lg,
                  HermesSpacing.sm,
                ),
                child: SearchBar(
                  key: kProjectSearchFieldKey,
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  hintText: 'Search chats',
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (querying)
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      ),
                  ],
                ),
              ),
            ),
          if (sessions.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.forum_outlined,
                title: 'No chats yet',
                message:
                    'Chats you start in this project will appear here, on '
                    'every device signed in to this Hermes.',
              ),
            )
          else if (filtered.isEmpty)
            // A query that matches nothing is not the same as an empty
            // project: saying "No chats yet" would tell the user the chat
            // they are looking for does not exist.
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off,
                title: 'No matches',
                message:
                    'No chats in this project match '
                    '“${_searchQuery.trim()}”.',
              ),
            )
          else
            SliverList.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final session = filtered[index];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HermesSpacing.lg,
                    HermesSpacing.sm,
                    HermesSpacing.lg,
                    0,
                  ),
                  child: _SessionCard(
                    session: session,
                    onTap: widget.onOpenSession == null
                        ? null
                        : () => widget.onOpenSession!(session),
                    onMove: widget.onMoveSession == null
                        ? null
                        : () => _chooseMoveDestination(session),
                  ),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: HermesSpacing.lg)),
        ],
      ),
    );
  }

  Widget _buildOverview(ProjectSessionsView view) {
    final tree = view.tree;
    final tokens = HermesTokens.of(context);

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
        children: [
          if (view.isStale) const _OfflineNotice(),
          const SectionHeader(title: 'Chats'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
            child: HermesCard(
              child: Row(
                children: [
                  Icon(Icons.forum_outlined, color: tokens.muted, size: 20),
                  const SizedBox(width: HermesSpacing.md),
                  Expanded(
                    child: Text(
                      'Conversations in this project',
                      style: tokens.typography.body.copyWith(
                        color: tokens.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    // The server's count, not the rows we happen to hold.
                    '${tree?.sessionCount ?? view.sessions.length}',
                    style: tokens.typography.title.copyWith(
                      color: tokens.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (tree != null && tree.repos.isNotEmpty) ...[
            const SectionHeader(title: 'Repositories'),
            for (final repo in tree.repos)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.lg,
                  0,
                  HermesSpacing.lg,
                  HermesSpacing.md,
                ),
                child: _RepoCard(repo: repo),
              ),
          ],
          if (tree?.path != null) ...[
            const SectionHeader(title: 'Location'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
              child: HermesCard(
                child: Text(
                  tree!.path!,
                  style: tokens.typography.mono.copyWith(color: tokens.muted),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The project's folders, exactly as the server described them.
  ///
  /// Paths come from `projects.project_sessions` (project, repos, lanes); the
  /// screen never scans local storage and never invents a tree of its own.
  Widget _buildFiles(ProjectSessionsView view) {
    final tokens = HermesTokens.of(context);
    final paths = <String>[];
    void add(String? path) {
      if (path != null && path.trim().isNotEmpty && !paths.contains(path)) {
        paths.add(path);
      }
    }

    final tree = view.tree;
    add(tree?.path);
    for (final repo in tree?.repos ?? const <ProjectRepo>[]) {
      add(repo.path);
      for (final lane in repo.lanes) {
        add(lane.path);
      }
    }

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
        children: [
          if (view.isStale) const _OfflineNotice(),
          if (paths.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: HermesSpacing.xl),
              child: EmptyState(
                icon: Icons.folder_open_outlined,
                title: 'No folders yet',
                message:
                    'The server has not reported folders for this project yet. '
                    'Global Files stays available from More.',
              ),
            )
          else ...[
            const SectionHeader(title: 'Folders'),
            for (final path in paths)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.lg,
                  0,
                  HermesSpacing.lg,
                  HermesSpacing.sm,
                ),
                child: HermesCard(
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 18,
                        color: tokens.muted,
                      ),
                      const SizedBox(width: HermesSpacing.md),
                      Expanded(
                        child: Text(
                          path,
                          style: tokens.typography.mono.copyWith(
                            color: tokens.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Honest capability gate: no server Assets index, no fake gallery.
  Widget _buildAssets(ProjectSessionsView view) {
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
        children: [
          if (view.isStale) const _OfflineNotice(),
          const Padding(
            padding: EdgeInsets.only(top: HermesSpacing.xl),
            child: ErrorState.unsupported(
              title: 'Assets unavailable',
              message:
                  'Assets need a server-authoritative Assets index in the '
                  'Hermes Gateway before they can be shown per project.',
            ),
          ),
        ],
      ),
    );
  }

  /// The project's own activity: every chat with its current state and when
  /// it was last active, newest first.
  Widget _buildActivity(ProjectSessionsView view) {
    final tokens = HermesTokens.of(context);
    final now = DateTime.now();
    final sessions = [...view.sessions]
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
        children: [
          if (view.isStale) const _OfflineNotice(),
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: HermesSpacing.xl),
              child: EmptyState(
                icon: Icons.bolt_outlined,
                title: 'No activity yet',
                message:
                    'Chats in this project will show their state and last '
                    'activity here.',
              ),
            )
          else
            for (final session in sessions)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.lg,
                  0,
                  HermesSpacing.lg,
                  HermesSpacing.sm,
                ),
                child: HermesCard(
                  onTap: () => widget.onOpenSession?.call(session),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.title.trim().isEmpty
                                  ? 'Untitled chat'
                                  : session.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: HermesSpacing.xs),
                            Text(
                              formatRelativeTime(now, session.lastActive),
                              style: tokens.typography.label.copyWith(
                                color: tokens.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusChip(
                        status: session.isActive
                            ? HermesStatus.running
                            : HermesStatus.completed,
                        label: session.isActive ? 'Running' : 'Done',
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// States that the content is the last known good copy, not live data.
class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HermesSpacing.lg,
        HermesSpacing.md,
        HermesSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 16, color: tokens.warning),
          const SizedBox(width: HermesSpacing.sm),
          Expanded(
            child: Text(
              'Offline — showing the last known chats',
              style: tokens.typography.label.copyWith(color: tokens.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoveTarget {
  final String? projectId;
  final String label;

  const _MoveTarget({required this.projectId, required this.label});
}

class _SessionCard extends StatelessWidget {
  final Session session;
  final VoidCallback? onTap;
  final VoidCallback? onMove;

  const _SessionCard({required this.session, this.onTap, this.onMove});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return HermesCard(
      onTap: onTap,
      status: session.isActive ? HermesStatus.running : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.body.copyWith(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (session.isActive) ...[
                const SizedBox(width: HermesSpacing.sm),
                const StatusChip(status: HermesStatus.running),
              ],
              if (onMove != null) ...[
                const SizedBox(width: HermesSpacing.xs),
                IconButton(
                  key: Key('move-session-${session.id}'),
                  tooltip: 'Move conversation',
                  onPressed: onMove,
                  icon: const Icon(Icons.drive_file_move_outline, size: 20),
                ),
              ],
            ],
          ),
          if (session.preview.isNotEmpty) ...[
            const SizedBox(height: HermesSpacing.xs),
            Text(
              session.preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.label.copyWith(color: tokens.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _RepoCard extends StatelessWidget {
  final ProjectRepo repo;

  const _RepoCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final lanes = repo.lanes;

    return HermesCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 18, color: tokens.muted),
              const SizedBox(width: HermesSpacing.sm),
              Expanded(
                child: Text(
                  repo.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.body.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
              ),
              Text(
                '${repo.sessionCount}',
                style: tokens.typography.label.copyWith(color: tokens.muted),
              ),
            ],
          ),
          if (lanes.isNotEmpty) ...[
            const SizedBox(height: HermesSpacing.sm),
            Wrap(
              spacing: HermesSpacing.sm,
              runSpacing: HermesSpacing.xs,
              children: [
                for (final lane in lanes)
                  Text(
                    lane.isMain ? '${lane.label} · main' : lane.label,
                    style: tokens.typography.label.copyWith(
                      color: lane.isMain ? tokens.accent : tokens.muted,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
