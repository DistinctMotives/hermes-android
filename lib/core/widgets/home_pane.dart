/// The Home destination pane.
///
/// Draws the attention digest produced by [buildHomeDigest]: what needs the
/// user, what is running, what is worth resuming, what just finished — in that
/// order. The ranking rules live in the pure helper; this file owns only the
/// presentation and the four states Phase 1 acceptance requires (loading,
/// empty, offline, error).
///
/// Two behaviours are deliberate rather than incidental:
///
/// 1. **A later failure never blanks Home.** Once a read has succeeded, a
///    failing refresh keeps the last known digest behind an offline notice.
///    Only a *first* read with nothing to show is allowed to become an error
///    screen, because there is genuinely nothing else to draw.
/// 2. **Nothing is silently hidden.** A section capped by
///    [kHomeSectionLimit] says how many rows it hid.
///
/// See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md`.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/session.dart';
import '../theme/hermes_theme.dart';
import '../utils/home_digest.dart';
import 'hermes_components.dart';

/// Reads the sessions Home ranks. Injectable so the pane can be tested — and
/// later re-pointed at a cache — without reaching for a transport.
typedef HomeSessionsLoader = Future<List<Session>> Function();

/// Supplies "now". Injectable so window boundaries stay assertable.
typedef HomeClock = DateTime Function();

class HomePane extends StatefulWidget {
  final HomeSessionsLoader loadSessions;

  /// Session id to the reason it is blocked.
  final Map<String, String> attention;

  /// Session ids with live work.
  final Set<String> running;

  /// Session ids that have left the resumable views — the Quick chats past
  /// their retention deadline. Blocked and running work is exempt inside
  /// [buildHomeDigest], so this can never hide something that needs the user.
  final Set<String> archived;

  /// Session id to its owning project's name.
  final Map<String, String> projectNames;

  final ValueChanged<Session>? onOpenSession;

  final HomeClock? clock;

  const HomePane({
    required this.loadSessions,
    this.attention = const {},
    this.running = const {},
    this.archived = const {},
    this.projectNames = const {},
    this.onOpenSession,
    this.clock,
    super.key,
  });

  @override
  State<HomePane> createState() => HomePaneState();
}

class HomePaneState extends State<HomePane> {
  /// The last successful read. `null` until one lands, which is exactly the
  /// condition for showing the skeleton.
  List<Session>? _sessions;

  /// Set when the most recent read failed. Combined with [_sessions] it tells
  /// stale-but-usable apart from nothing-to-show.
  Object? _error;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Re-reads the ranked sessions.
  ///
  /// Public so a host can refresh Home after the user acts elsewhere — coming
  /// back from a chat to a digest that still lists the work as blocked would
  /// be worse than a spinner.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final sessions = await widget.loadSessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;

    if (sessions == null) {
      if (_error != null) {
        return ErrorState(
          title: 'Could not reach Hermes',
          message:
              'Home needs your recent chats to know what deserves your '
              'attention. Check that the gateway is reachable, then try again.',
          onRetry: _load,
        );
      }
      return const Padding(
        padding: EdgeInsets.only(top: HermesSpacing.lg),
        child: LoadingSkeleton(rows: 4),
      );
    }

    final digest = buildHomeDigest(
      sessions: sessions,
      now: _now,
      attention: widget.attention,
      running: widget.running,
      archived: widget.archived,
      projectNames: widget.projectNames,
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: HermesSpacing.xxl),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_error != null) const _OfflineBanner(),
          if (digest.isEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.sizeOf(context).height * 0.12,
              ),
              child: const EmptyState(
                icon: Icons.check_circle_outline,
                title: 'Nothing needs you',
                message:
                    'No chat is blocked, running, or waiting to be resumed. '
                    'Start a new one whenever you are ready.',
              ),
            )
          else
            for (final section in digest.sections) ..._section(section),
        ],
      ),
    );
  }

  List<Widget> _section(HomeSection section) {
    return [
      SectionHeader(title: section.title, count: section.totalCount),
      for (final item in section.items)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HermesSpacing.lg,
            0,
            HermesSpacing.lg,
            HermesSpacing.md,
          ),
          child: _HomeItemCard(
            item: item,
            onTap: widget.onOpenSession == null
                ? null
                : () => widget.onOpenSession!(item.session),
          ),
        ),
      if (section.overflow > 0) _OverflowNote(count: section.overflow),
    ];
  }
}

/// Says how many rows a cap hid, so Home never quietly loses work.
class _OverflowNote extends StatelessWidget {
  final int count;

  const _OverflowNote({required this.count});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HermesSpacing.lg,
        0,
        HermesSpacing.lg,
        HermesSpacing.lg,
      ),
      child: Text(
        'and $count more',
        style: tokens.typography.label.copyWith(color: tokens.muted),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HermesSpacing.lg,
        HermesSpacing.lg,
        HermesSpacing.lg,
        0,
      ),
      child: HermesCard(
        status: HermesStatus.idle,
        padding: const EdgeInsets.all(HermesSpacing.md),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 18, color: tokens.muted),
            const SizedBox(width: HermesSpacing.sm),
            Expanded(
              child: Text(
                'Offline — showing the last known activity.',
                style: tokens.typography.label.copyWith(color: tokens.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeItemCard extends StatelessWidget {
  final HomeItem item;
  final VoidCallback? onTap;

  const _HomeItemCard({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final title = item.session.title.trim().isEmpty
        ? 'Untitled chat'
        : item.session.title;
    final project = item.projectName;
    final reason = item.attentionLabel;

    return HermesCard(
      onTap: onTap,
      // Only blocked work is tinted: tinting every row would make none of
      // them read as urgent.
      status: item.status == HermesStatus.blocked ? item.status : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.section.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: HermesSpacing.sm),
              StatusChip(status: item.status),
            ],
          ),
          if (reason != null) ...[
            const SizedBox(height: HermesSpacing.xs),
            Text(
              reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.body.copyWith(
                color: tokens.colorForStatus(HermesStatus.blocked),
              ),
            ),
          ],
          if (project != null) ...[
            const SizedBox(height: HermesSpacing.xs),
            Text(
              project,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.label.copyWith(color: tokens.muted),
            ),
          ],
        ],
      ),
    );
  }
}
