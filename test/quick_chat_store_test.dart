import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/quick_chat_store.dart';
import 'package:hermes_android/core/utils/new_chat_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final created = DateTime.utc(2026, 8, 29, 12);
  final deadline = created.add(kQuickChatRetention);

  Future<QuickChatStore> storeFor(String connectionId) async {
    final prefs = await SharedPreferences.getInstance();
    return QuickChatStore(prefs, connectionId: connectionId);
  }

  test('a recorded quick chat is tracked with its deadline', () async {
    final store = await storeFor('gateway');

    await store.record('quick-1', expiresAt: deadline);
    final state = await store.load();

    expect(state.isQuick('quick-1'), isTrue);
    expect(state.expiresAtFor('quick-1'), deadline);
    expect(state.statusFor('quick-1', created), QuickChatStatus.active);
  });

  test('an untracked chat is not quick and has no status', () async {
    final store = await storeFor('gateway');

    final state = await store.load();

    expect(state.isQuick('durable-1'), isFalse);
    expect(state.expiresAtFor('durable-1'), isNull);
    expect(state.statusFor('durable-1', created), isNull);
    expect(state.archivedAt(created.add(const Duration(days: 30))), isEmpty);
  });

  test('quick chats stay scoped to their connection', () async {
    final first = await storeFor('gateway-a');
    final second = await storeFor('gateway-b');

    await first.record('quick-1', expiresAt: deadline);

    expect((await first.load()).isQuick('quick-1'), isTrue);
    expect((await second.load()).isQuick('quick-1'), isFalse);
  });

  test('re-recording a quick chat never extends its deadline', () async {
    final store = await storeFor('gateway');

    await store.record('quick-1', expiresAt: deadline);
    await store.record(
      'quick-1',
      expiresAt: deadline.add(const Duration(days: 7)),
    );

    // Reopening a quick chat must not keep it alive forever: the 72 h clock
    // starts once, at creation.
    expect((await store.load()).expiresAtFor('quick-1'), deadline);
  });

  test(
    'a quick chat past its deadline reads as archived, not deleted',
    () async {
      final store = await storeFor('gateway');
      await store.record('quick-1', expiresAt: deadline);

      final state = await store.load();
      final after = deadline.add(const Duration(minutes: 1));

      expect(state.statusFor('quick-1', after), QuickChatStatus.archived);
      expect(state.archivedAt(after), {'quick-1'});
      // Still recorded, still searchable: archiving is a lifecycle state, never
      // a deletion.
      expect(state.expiresAtFor('quick-1'), deadline);
      expect((await store.load()).isQuick('quick-1'), isTrue);
    },
  );

  test('the deadline itself has not passed yet', () async {
    final store = await storeFor('gateway');
    await store.record('quick-1', expiresAt: deadline);

    final state = await store.load();

    expect(state.statusFor('quick-1', deadline), QuickChatStatus.active);
    expect(state.archivedAt(deadline), isEmpty);
  });

  test('promoting a quick chat makes it durable for good', () async {
    final store = await storeFor('gateway');
    await store.record('quick-1', expiresAt: deadline);

    await store.promote('quick-1');
    final state = await store.load();
    final after = deadline.add(const Duration(days: 30));

    expect(state.isQuick('quick-1'), isFalse);
    expect(state.statusFor('quick-1', after), QuickChatStatus.promoted);
    expect(state.archivedAt(after), isEmpty);
  });

  test('a promoted chat can never be re-marked as quick', () async {
    final store = await storeFor('gateway');
    await store.record('quick-1', expiresAt: deadline);
    await store.promote('quick-1');

    // A stale draft replayed after the user deliberately kept this chat must
    // not put it back on an archive timer.
    await store.record('quick-1', expiresAt: deadline);

    final state = await store.load();
    expect(state.isQuick('quick-1'), isFalse);
    expect(state.archivedAt(deadline.add(const Duration(days: 30))), isEmpty);
  });

  test('promoting an untracked chat changes nothing', () async {
    final store = await storeFor('gateway');

    await store.promote('never-seen');

    expect((await store.load()).statusFor('never-seen', created), isNull);
  });

  test('pruning drops records for chats the gateway no longer has', () async {
    final store = await storeFor('gateway');
    await store.record('quick-1', expiresAt: deadline);
    await store.record('quick-2', expiresAt: deadline);
    await store.record('quick-3', expiresAt: deadline);
    await store.promote('quick-3');

    await store.prune({'quick-1'}, now: deadline.add(const Duration(days: 1)));
    final state = await store.load();

    expect(state.isQuick('quick-1'), isTrue);
    expect(state.statusFor('quick-2', created), isNull);
    expect(state.statusFor('quick-3', created), isNull);
  });

  test('pruning never drops a chat that is still inside its window', () async {
    // A quick chat created seconds ago is not in the gateway's session list
    // yet — it becomes one on its first turn. Pruning on absence alone would
    // delete the record before it was ever used, silently making the chat
    // durable.
    final store = await storeFor('gateway');
    await store.record('quick-1', expiresAt: deadline);

    await store.prune(const {}, now: created);

    expect((await store.load()).isQuick('quick-1'), isTrue);
  });

  test('a blank session id is rejected rather than stored', () async {
    final store = await storeFor('gateway');

    expect(() => store.record('  ', expiresAt: deadline), throwsArgumentError);
    expect(() => store.promote('  '), throwsArgumentError);
  });

  test('a corrupt store degrades to empty instead of throwing', () async {
    SharedPreferences.setMockInitialValues({
      'quick_chats_v1_gateway': 'not json at all',
    });
    final store = await storeFor('gateway');

    final state = await store.load();

    expect(state.isQuick('quick-1'), isFalse);
    // And it stays writable after the bad value.
    await store.record('quick-1', expiresAt: deadline);
    expect((await store.load()).isQuick('quick-1'), isTrue);
  });

  test(
    'a record with an unreadable deadline is dropped, never archived',
    () async {
      SharedPreferences.setMockInitialValues({
        'quick_chats_v1_gateway':
            '{"expiries":{"quick-1":"tomorrow","quick-2":${deadline.millisecondsSinceEpoch}},"promoted":[]}',
      });
      final store = await storeFor('gateway');

      final state = await store.load();

      // Undatable work must never be silently archived on a guess.
      expect(state.isQuick('quick-1'), isFalse);
      expect(state.archivedAt(deadline.add(const Duration(days: 30))), {
        'quick-2',
      });
    },
  );

  test('the loaded state is immutable', () async {
    final store = await storeFor('gateway');
    await store.record('quick-1', expiresAt: deadline);

    final state = await store.load();

    expect(() => state.expiries['quick-2'] = deadline, throwsUnsupportedError);
    expect(() => state.promoted.add('quick-1'), throwsUnsupportedError);
  });
}
