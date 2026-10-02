/// The Activity destination pane.
///
/// Draws the operational timeline produced by [buildActivityFeed]: what needs
/// the user, what is running, what failed, what finished — in that order. The
/// grouping rules live in the pure helper; this file owns only the
/// presentation and the four states Phase 1 acceptance requires (loading,
/// empty, offline, error).
///
/// Two behaviours are deliberate rather than incidental, and match [HomePane]
/// on purpose so the two screens never disagree about the same failure:
///
/// 1. **A later failure never blanks Activity.** Once a read has succeeded, a
///    failing refresh keeps the last known timeline behind an offline notice.
///    Only a *first* read with nothing to show becomes an error screen.
/// 2. **Nothing is silently hidden.** A group capped by
///    [kActivityGroupLimit] says how many rows it hid, and an untitled turn
///    still draws a row — the journal is the truth about work, so a turn whose
///    chat is missing from the session list is still real.
///
/// See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md`.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/hermes_theme.dart';
import '../utils/activity_feed.dart';
import 'hermes_components.dart';

/// Reads the timeline. Injectable so the pane can be tested — and later
/// re-pointed at a cache or a gateway feed — without reaching for a journal.
typedef ActivityFeedLoader = Future<ActivityFeed> Function();

/// Supplies "now", so the elapsed-time labels stay assertable.
typedef ActivityClock = DateTime Function();

class ActivityPane extends StatefulWidget {
  final ActivityFeedLoader loadFeed;

  /// When true, this pane becomes the action Inbox: only blocked and failed
  /// work is shown. Running and completed work remain available in Activity.
  final bool actionableOnly;

  /// Called when the user taps a row. When null, rows are drawn inert rather
  /// than looking tappable and doing nothing.
  final ValueChanged<ActivityItem>? onOpenItem;

  final ActivityClock? clock;

  const ActivityPane({
    required this.loadFeed,
    this.actionableOnly = false,
    this.onOpenItem,
    this.clock,
    super.key,
  });

  @override
  State<ActivityPane> createState() => ActivityPaneState();
}

class ActivityPaneState extends State<ActivityPane> {
  /// The last successful read. `null` until one lands, which is exactly the
  /// condition for showing the skeleton.
  ActivityFeed? _feed;

  /// Set when the most recent read failed. Combined with [_feed] it tells
  /// stale-but-usable apart from nothing-to-show.
  Object? _error;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Re-reads the timeline.
  ///
  /// Public so a host can refresh Activity after the user acts elsewhere —
  /// coming back from a chat to a row that still claims the turn is blocked
  /// would be worse than a spinner.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final feed = await widget.loadFeed();
      if (!mounted) return;
      setState(() {
        _feed = feed;
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
    final feed = _feed;

    if (feed == null) {
      if (_error != null) {
        return ErrorState(
          title: 'Could not read activity',
          message:
              'Activity reads the durable turn journal to know what Hermes is '
              'doing. Check that the gateway is reachable, then try again.',
          onRetry: _load,
        );
      }
      return const Padding(
        padding: EdgeInsets.only(top: HermesSpacing.lg),
        child: LoadingSkeleton(rows: 4),
      );
    }

    final groups = widget.actionableOnly
        ? feed.groups
              .where(
                (group) =>
                    group.kind == ActivityGroupKind.needsYou ||
                    group.kind == ActivityGroupKind.failed,
              )
              .toList(growable: false)
        : feed.groups;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: HermesSpacing.xxl),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_error != null) const _OfflineBanner(),
          if (groups.isEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.sizeOf(context).height * 0.12,
              ),
              child: EmptyState(
                icon: widget.actionableOnly
                    ? Icons.inbox_outlined
                    : Icons.bolt_outlined,
                title: widget.actionableOnly
                    ? 'Inbox is clear'
                    : 'Nothing is running',
                message: widget.actionableOnly
                    ? 'No turn needs your input or has failed.'
                    : 'No turn is blocked, in flight, or recently finished. '
                          'Work you start will show up here.',
              ),
            )
          else
            for (final group in groups) ..._group(group),
        ],
      ),
    );
  }

  List<Widget> _group(ActivityGroup group) {
    return [
      SectionHeader(title: group.title, count: group.totalCount),
      for (final item in group.items)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HermesSpacing.lg,
            0,
            HermesSpacing.lg,
            HermesSpacing.md,
          ),
          child: _ActivityItemCard(
            item: item,
            now: _now,
            onTap: widget.onOpenItem == null
                ? null
                : () => widget.onOpenItem!(item),
          ),
        ),
      if (group.overflow > 0) _OverflowNote(count: group.overflow),
    ];
  }
}

/// Says how many rows a cap hid, so Activity never quietly loses work.
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

class _ActivityItemCard extends StatelessWidget {
  final ActivityItem item;
  final DateTime now;
  final VoidCallback? onTap;

  const _ActivityItemCard({required this.item, required this.now, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final title = item.title?.trim();

    return HermesCard(
      onTap: onTap,
      // Only work that needs the user or broke is tinted: tinting every row
      // would make none of them read as urgent.
      status:
          item.status == HermesStatus.blocked ||
              item.status == HermesStatus.failed
          ? item.status
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title == null || title.isEmpty ? 'Untitled chat' : title,
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
          const SizedBox(height: HermesSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.body.copyWith(
                    color: tokens.colorForStatus(item.status),
                  ),
                ),
              ),
              const SizedBox(width: HermesSpacing.sm),
              Text(
                formatActivityAge(item.updatedAt, now),
                style: tokens.typography.label.copyWith(color: tokens.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How long ago [updatedAt] happened, in the compact form a timeline row uses.
///
/// A blocked row without an elapsed time is not actionable, so this is a
/// first-class part of the presentation rather than a decoration. A timestamp
/// ahead of [now] — a skewed device clock — reads as `now` rather than as a
/// negative duration.
String formatActivityAge(DateTime updatedAt, DateTime now) {
  final elapsed = now.difference(updatedAt);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
  return '${elapsed.inDays}d ago';
}
