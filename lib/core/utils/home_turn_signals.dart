/// Turns the durable recovery journal into Home's attention and running
/// signals.
///
/// Home already knows how to *rank* work ([buildHomeDigest]), but until now it
/// received no attention or running input, so every chat ranked as
/// `Continue working` and the shell's attention badge stayed empty. The turn
/// journal is the one place that already survives process death and knows what
/// a chat was doing, so it is the honest source for those two inputs — no new
/// gateway contract is required and legacy gateways keep working.
///
/// Three rules drive the shape:
///
/// 1. **Attention outranks running.** A session with any blocked turn is
///    reported only as needing the user, never also as running, so the digest
///    cannot show the same chat twice.
/// 2. **Never claim live work that is not live.** A running turn whose journal
///    entry has not moved for [kHomeRunningStaleAfter] is almost certainly a
///    zombie from a killed process, so it is dropped rather than displayed as
///    progressing. Blocked work is never aged out — being stuck is the point.
/// 3. **Never invent a row.** Entries with no matching binding, and bindings
///    belonging to another connection or gateway endpoint, are ignored.
///
/// See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md`.
library;

import '../models/connection.dart';
import '../models/gateway_turn_contract.dart';
import '../services/desktop_gateway_client.dart';
import '../services/gateway_turn_journal.dart';

/// How long a running turn may go without a journal update before Home stops
/// presenting it as live.
const Duration kHomeRunningStaleAfter = Duration(minutes: 15);

/// The two inputs Home's digest needs beyond the session list.
class HomeTurnSignals {
  /// Local session id to the reason Hermes cannot continue.
  final Map<String, String> attention;

  /// Local session ids with a turn believed to be in flight.
  final Set<String> running;

  const HomeTurnSignals({required this.attention, required this.running});

  static const empty = HomeTurnSignals(attention: {}, running: {});

  bool get isEmpty => attention.isEmpty && running.isEmpty;
}

/// Derives Home's attention and running signals from a journal [snapshot].
///
/// When [connectionId] and [endpointDigest] are supplied, only turns recorded
/// for that exact gateway scope are reported: a saved connection re-pointed at
/// a different endpoint must not resurrect the previous endpoint's work.
/// Passing `null` for either reads every scope, which is what a diagnostics
/// view wants.
HomeTurnSignals buildHomeTurnSignals({
  required GatewayTurnJournalSnapshot snapshot,
  required DateTime now,
  String? connectionId,
  String? endpointDigest,
  Duration runningStaleAfter = kHomeRunningStaleAfter,
}) {
  final sessionForBinding = <String, String>{};
  for (final binding in snapshot.bindings) {
    if (connectionId != null && binding.connectionId != connectionId) continue;
    if (endpointDigest != null && binding.endpointDigest != endpointDigest) {
      continue;
    }
    sessionForBinding[binding.bindingIdentity] = binding.localSessionId;
  }
  if (sessionForBinding.isEmpty) return HomeTurnSignals.empty;

  final nowMs = now.millisecondsSinceEpoch;
  final staleMs = runningStaleAfter.inMilliseconds;

  // Keep the freshest blocking reason per session rather than the first one
  // encountered: a chat that failed and then asked a question is waiting on an
  // answer, not on the old failure.
  final attentionAt = <String, int>{};
  final attention = <String, String>{};
  final running = <String>{};

  for (final entry in snapshot.entries) {
    final sessionId = sessionForBinding[entry.bindingIdentity];
    if (sessionId == null) continue;

    final reason = _attentionReason(entry);
    if (reason != null) {
      final previous = attentionAt[sessionId];
      if (previous == null || entry.updatedAtEpochMs >= previous) {
        attentionAt[sessionId] = entry.updatedAtEpochMs;
        attention[sessionId] = reason;
      }
      continue;
    }

    if (!_isInFlight(entry)) continue;
    // A negative age means the clock is behind the journal; trust the journal
    // rather than hiding live work over a skewed clock.
    final ageMs = nowMs - entry.updatedAtEpochMs;
    if (ageMs > staleMs) continue;
    running.add(sessionId);
  }

  // Attention wins outright, so a session reported as blocked is removed from
  // the running set even if another of its turns is still streaming.
  running.removeWhere(attention.containsKey);

  return HomeTurnSignals(
    attention: Map.unmodifiable(attention),
    running: Set.unmodifiable(running),
  );
}

/// The recovery-journal endpoint scope for [connection], or `null` when the
/// connection names no usable Desktop Gateway.
///
/// Delegates to [DesktopGatewayClient.endpointDigestFor] rather than
/// recomputing the hash, so the scope Home reads can never drift from the one
/// the coordinator writes.
String? endpointDigestForConnection(SavedConnection connection) =>
    DesktopGatewayClient.endpointDigestFor(connection);

/// Reads [journal] and derives Home's signals for one connection scope.
///
/// A journal that cannot be read degrades to [HomeTurnSignals.empty] instead
/// of throwing: on a device where secure storage is unavailable, losing the
/// attention badge is acceptable, losing the Home screen is not.
Future<HomeTurnSignals> readHomeTurnSignals({
  required GatewayTurnJournal journal,
  required String? connectionId,
  required String? endpointDigest,
  DateTime? now,
  Duration runningStaleAfter = kHomeRunningStaleAfter,
}) async {
  try {
    final snapshot = await journal.loadSnapshot();
    return buildHomeTurnSignals(
      snapshot: snapshot,
      now: now ?? DateTime.now(),
      connectionId: connectionId,
      endpointDigest: endpointDigest,
      runningStaleAfter: runningStaleAfter,
    );
  } catch (_) {
    return HomeTurnSignals.empty;
  }
}

/// Why this turn blocks the user, or `null` when it does not.
String? _attentionReason(GatewayTurnJournalEntry entry) {
  // A recovery failure outranks the reported status: the turn may well have
  // completed server-side, but the client could not reconcile it and the
  // composer stays blocked, which is exactly what Home must surface.
  if (entry.failure != null) return 'Turn recovery failed';
  switch (entry.status) {
    case GatewayRecoveryTurnStatus.waitingInput:
      return 'Waiting for your input';
    case GatewayRecoveryTurnStatus.failed:
      return 'The last turn failed';
    case GatewayRecoveryTurnStatus.accepted:
    case GatewayRecoveryTurnStatus.running:
    case GatewayRecoveryTurnStatus.completed:
    case GatewayRecoveryTurnStatus.interrupted:
    case null:
      return null;
  }
}

/// Whether this turn is believed to still be progressing.
///
/// A null status is deliberately in flight: the submit was written ahead but
/// the gateway has not answered yet, so the work is outstanding.
bool _isInFlight(GatewayTurnJournalEntry entry) {
  switch (entry.status) {
    case null:
    case GatewayRecoveryTurnStatus.accepted:
    case GatewayRecoveryTurnStatus.running:
      return true;
    case GatewayRecoveryTurnStatus.waitingInput:
    case GatewayRecoveryTurnStatus.completed:
    case GatewayRecoveryTurnStatus.failed:
    case GatewayRecoveryTurnStatus.interrupted:
      return false;
  }
}
