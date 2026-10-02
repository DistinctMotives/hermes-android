import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/gateway_turn_contract.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_journal.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';

import 'support/memory_turn_journal_store.dart';

const _digestA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _digestB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _clientA = '33333333-3333-4333-8333-333333333333';
const _clientB = '44444444-4444-4444-8444-444444444444';
const _mobileA = '11111111-1111-4111-8111-111111111111';

/// A fixed clock so the staleness boundary stays asserted rather than
/// approximated.
final _now = DateTime.utc(2026, 8, 27, 12, 0, 0);

int _msAgo(Duration ago) => _now.subtract(ago).millisecondsSinceEpoch;

GatewayTurnJournalBinding _binding({
  String connectionId = 'connection-a',
  String endpointDigest = _digestA,
  String localSessionId = 'session-a',
}) {
  return GatewayTurnJournalBinding(
    connectionId: connectionId,
    endpointDigest: endpointDigest,
    localSessionId: localSessionId,
    mobileSessionId: _mobileA,
    storedSessionId: 'stored-$localSessionId',
    bindingVersion: 1,
    updatedAtEpochMs: _msAgo(const Duration(minutes: 30)),
  );
}

GatewayTurnJournalEntry _entry({
  required GatewayTurnJournalBinding binding,
  String clientTurnId = _clientA,
  GatewayRecoveryTurnStatus? status,
  GatewayTurnRecoveryFailure? failure,
  Duration updatedAgo = const Duration(minutes: 1),
}) {
  final terminal = status?.isTerminal == true;
  final hasFailure = failure != null;
  return GatewayTurnJournalEntry(
    bindingIdentity: binding.bindingIdentity,
    clientTurnId: clientTurnId,
    turnId: status == null ? null : 'turn-$clientTurnId',
    status: status,
    lastSeq: status == null ? 0 : 3,
    eventPayloadBytes: 0,
    terminalEventRecorded: terminal && !hasFailure,
    terminalResult: status == GatewayRecoveryTurnStatus.completed && !hasFailure
        ? GatewayTurnTerminalResult(
            messageId: 'message-$clientTurnId',
            assistantText: 'Done.',
          )
        : null,
    ackUncertain: false,
    failure: failure,
    updatedAtEpochMs: _msAgo(updatedAgo),
  );
}

HomeTurnSignals _signals(
  List<GatewayTurnJournalBinding> bindings,
  List<GatewayTurnJournalEntry> entries, {
  String? connectionId = 'connection-a',
  String? endpointDigest = _digestA,
  DateTime? now,
}) {
  return buildHomeTurnSignals(
    snapshot: GatewayTurnJournalSnapshot(bindings: bindings, entries: entries),
    now: now ?? _now,
    connectionId: connectionId,
    endpointDigest: endpointDigest,
  );
}

void main() {
  test('an empty journal produces no signals at all', () {
    final signals = _signals(const [], const []);

    expect(signals.attention, isEmpty);
    expect(signals.running, isEmpty);
    expect(signals.isEmpty, isTrue);
  });

  test('a live turn reports its session as running', () {
    final binding = _binding();
    final signals = _signals(
      [binding],
      [_entry(binding: binding, status: GatewayRecoveryTurnStatus.running)],
    );

    expect(signals.running, {'session-a'});
    expect(signals.attention, isEmpty);
  });

  test('an unacknowledged submit still counts as running', () {
    // No status yet: the gateway has not answered. The work is in flight, so
    // Home must not present the chat as idle.
    final binding = _binding();
    final signals = _signals([binding], [_entry(binding: binding)]);

    expect(signals.running, {'session-a'});
  });

  test('a turn waiting on the user needs attention, never running', () {
    final binding = _binding();
    final signals = _signals(
      [binding],
      [
        _entry(
          binding: binding,
          status: GatewayRecoveryTurnStatus.waitingInput,
        ),
      ],
    );

    expect(signals.attention, {'session-a': 'Waiting for your input'});
    expect(signals.running, isEmpty);
  });

  test('a failed turn needs attention', () {
    final binding = _binding();
    final signals = _signals(
      [binding],
      [_entry(binding: binding, status: GatewayRecoveryTurnStatus.failed)],
    );

    expect(signals.attention, {'session-a': 'The last turn failed'});
    expect(signals.running, isEmpty);
  });

  test('a recovery failure needs attention even on a completed turn', () {
    // The turn finished server-side but the client could not reconcile it, so
    // the composer stays blocked: this is exactly what Home must surface.
    final binding = _binding();
    final signals = _signals(
      [binding],
      [
        _entry(
          binding: binding,
          status: GatewayRecoveryTurnStatus.completed,
          failure: GatewayTurnRecoveryFailure.replayPruned,
        ),
      ],
    );

    expect(signals.attention, {'session-a': 'Turn recovery failed'});
    expect(signals.running, isEmpty);
  });

  test('completed and interrupted turns produce no signal', () {
    final done = _binding(localSessionId: 'session-done');
    final stopped = _binding(localSessionId: 'session-stopped');
    final signals = _signals(
      [done, stopped],
      [
        _entry(binding: done, status: GatewayRecoveryTurnStatus.completed),
        _entry(binding: stopped, status: GatewayRecoveryTurnStatus.interrupted),
      ],
    );

    expect(signals.isEmpty, isTrue);
  });

  test('attention outranks a concurrent running turn on the same session', () {
    final binding = _binding();
    final signals = _signals(
      [binding],
      [
        _entry(
          binding: binding,
          clientTurnId: _clientA,
          status: GatewayRecoveryTurnStatus.running,
        ),
        _entry(
          binding: binding,
          clientTurnId: _clientB,
          status: GatewayRecoveryTurnStatus.failed,
        ),
      ],
    );

    expect(signals.attention.keys, ['session-a']);
    expect(signals.running, isEmpty);
  });

  test('the most recent attention reason wins', () {
    final binding = _binding();
    final signals = _signals(
      [binding],
      [
        _entry(
          binding: binding,
          clientTurnId: _clientA,
          status: GatewayRecoveryTurnStatus.failed,
          updatedAgo: const Duration(minutes: 20),
        ),
        _entry(
          binding: binding,
          clientTurnId: _clientB,
          status: GatewayRecoveryTurnStatus.waitingInput,
          updatedAgo: const Duration(minutes: 2),
        ),
      ],
    );

    expect(signals.attention, {'session-a': 'Waiting for your input'});
  });

  test('a stale running turn is dropped rather than shown as live', () {
    // A turn that has not moved for hours is almost certainly a zombie from a
    // killed process. Claiming it is running would be a lie.
    final binding = _binding();
    final signals = _signals(
      [binding],
      [
        _entry(
          binding: binding,
          status: GatewayRecoveryTurnStatus.running,
          updatedAgo: kHomeRunningStaleAfter + const Duration(minutes: 1),
        ),
      ],
    );

    expect(signals.running, isEmpty);
  });

  test('blocked work is never aged out', () {
    final binding = _binding();
    final signals = _signals(
      [binding],
      [
        _entry(
          binding: binding,
          status: GatewayRecoveryTurnStatus.failed,
          updatedAgo: const Duration(days: 5),
        ),
      ],
    );

    expect(signals.attention, {'session-a': 'The last turn failed'});
  });

  test('a clock skewed behind the journal keeps the turn running', () {
    final binding = _binding();
    final signals = _signals(
      [binding],
      [
        _entry(
          binding: binding,
          status: GatewayRecoveryTurnStatus.running,
          updatedAgo: const Duration(hours: -3),
        ),
      ],
    );

    expect(signals.running, {'session-a'});
  });

  test('another connection never leaks into this connection signals', () {
    final mine = _binding(localSessionId: 'session-a');
    final other = _binding(
      connectionId: 'connection-b',
      localSessionId: 'session-b',
    );
    final signals = _signals(
      [mine, other],
      [
        _entry(binding: other, status: GatewayRecoveryTurnStatus.running),
        _entry(
          binding: other,
          clientTurnId: _clientB,
          status: GatewayRecoveryTurnStatus.failed,
        ),
      ],
    );

    expect(signals.isEmpty, isTrue);
  });

  test('another endpoint on the same connection is also excluded', () {
    // The same saved connection can be re-pointed at a different gateway
    // endpoint; turns from the old endpoint are not this gateway's work.
    final other = _binding(
      endpointDigest: _digestB,
      localSessionId: 'session-b',
    );
    final signals = _signals(
      [other],
      [_entry(binding: other, status: GatewayRecoveryTurnStatus.running)],
    );

    expect(signals.isEmpty, isTrue);
  });

  test('an unscoped read reports every connection', () {
    final mine = _binding(localSessionId: 'session-a');
    final other = _binding(
      connectionId: 'connection-b',
      endpointDigest: _digestB,
      localSessionId: 'session-b',
    );
    final signals = _signals(
      [mine, other],
      [
        _entry(binding: mine, status: GatewayRecoveryTurnStatus.running),
        _entry(binding: other, status: GatewayRecoveryTurnStatus.running),
      ],
      connectionId: null,
      endpointDigest: null,
    );

    expect(signals.running, {'session-a', 'session-b'});
  });

  test('an entry with no matching binding is ignored, not invented', () {
    final orphan = _binding(localSessionId: 'session-orphan');
    final signals = _signals(const [], [
      _entry(binding: orphan, status: GatewayRecoveryTurnStatus.running),
    ]);

    expect(signals.isEmpty, isTrue);
  });

  test('the returned collections are unmodifiable', () {
    final binding = _binding();
    final signals = _signals(
      [binding],
      [_entry(binding: binding, status: GatewayRecoveryTurnStatus.running)],
    );

    expect(() => signals.running.add('injected'), throwsUnsupportedError);
    expect(
      () => signals.attention['injected'] = 'nope',
      throwsUnsupportedError,
    );
  });

  group('connection scoping', () {
    SavedConnection connection({String? desktopGatewayUrl}) => SavedConnection(
      id: 'conn-1',
      label: 'Miniserver',
      host: 'carlos-miniserver',
      port: 8642,
      apiKey: 'key',
      desktopGatewayUrl: desktopGatewayUrl,
    );

    test('a connection with no gateway URL has no endpoint digest', () {
      expect(endpointDigestForConnection(connection()), isNull);
    });

    test('a malformed gateway URL has no endpoint digest', () {
      expect(
        endpointDigestForConnection(
          connection(desktopGatewayUrl: 'ftp://nope'),
        ),
        isNull,
      );
    });

    test('the digest matches the one the journal is actually written with', () {
      // The scope key is only useful if it is byte-identical to the one the
      // coordinator stamps into every binding. Deriving it twice invites
      // drift, so this asserts the two agree.
      final saved = connection(
        desktopGatewayUrl: 'https://carlos-miniserver:8788/gw',
      );
      final client = DesktopGatewayClient.fromConnection(saved);
      addTearDown(client.close);
      final registry = client.enableTurnRecoveryCoordinator(
        journal: GatewayTurnJournal(store: MemoryTurnJournalStore()),
      );

      expect(endpointDigestForConnection(saved), registry.endpointDigest);
    });

    test('equivalent URL spellings produce the same digest', () {
      // An explicit default port and an omitted one address the same gateway;
      // treating them as different scopes would hide live work.
      expect(
        endpointDigestForConnection(
          connection(desktopGatewayUrl: 'https://carlos-miniserver'),
        ),
        endpointDigestForConnection(
          connection(desktopGatewayUrl: 'https://carlos-miniserver:443'),
        ),
      );
    });
  });

  group('readHomeTurnSignals', () {
    test('reads the live journal for one connection scope', () async {
      final store = MemoryTurnJournalStore();
      final journal = GatewayTurnJournal(store: store);
      final binding = _binding();
      await journal.upsertBinding(binding);
      await journal.upsert(
        _entry(binding: binding, status: GatewayRecoveryTurnStatus.running),
        now: _now,
      );

      final signals = await readHomeTurnSignals(
        journal: journal,
        connectionId: 'connection-a',
        endpointDigest: _digestA,
        now: _now,
      );

      expect(signals.running, {'session-a'});
    });

    test('an unreadable journal degrades to no signals, never an error', () {
      // Home must keep working on a device where secure storage is broken:
      // losing the badge is acceptable, losing the screen is not.
      final store = MemoryTurnJournalStore()..unavailable = true;

      expect(
        readHomeTurnSignals(
          journal: GatewayTurnJournal(store: store),
          connectionId: 'connection-a',
          endpointDigest: _digestA,
          now: _now,
        ),
        completion(
          isA<HomeTurnSignals>().having((s) => s.isEmpty, 'isEmpty', isTrue),
        ),
      );
    });
  });
}
