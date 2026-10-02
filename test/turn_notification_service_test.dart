import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';

import 'support/recording_turn_notification_sink.dart';

/// Characterization tests for the notification behaviour Hermes Android ships
/// today. Phase 3 of the daily-driver roadmap replaces this single channel with
/// four prioritized channels, deep links, and notification actions. These tests
/// pin the current contract first so that rework is a deliberate change and not
/// an accidental regression.
void main() {
  late RecordingTurnNotificationSink sink;
  late TurnNotificationService service;

  setUp(() {
    sink = RecordingTurnNotificationSink();
    service = TurnNotificationService(sink: sink);
  });

  group('initialization', () {
    test('is idempotent — the channel is only created once', () async {
      await service.ensureInitialized();
      await service.ensureInitialized();
      await service.ensureInitialized();

      expect(sink.initializeCount, 1);
    });

    test(
      'degrades to a no-op when the platform channel is unavailable',
      () async {
        sink.initializeError = StateError('no platform channel');

        await service.ensureInitialized();

        // Initialization must not rethrow: the app has to keep running on a
        // device where notifications are unavailable.
        await service.showTurnCompleted(turnSummary: 'Done', turnId: 't-1');
        expect(sink.shown, isEmpty);
      },
    );

    test('a failed initialization can be retried on the next call', () async {
      sink.initializeError = StateError('no platform channel');
      await service.ensureInitialized();
      expect(sink.initializeCount, 1);

      sink.initializeError = null;
      await service.ensureInitialized();

      expect(sink.initializeCount, 2);
      await service.showTurnCompleted(turnSummary: 'Done', turnId: 't-1');
      expect(sink.shown, hasLength(1));
    });
  });

  group('showTurnCompleted', () {
    test(
      'drops the notification when the service was never initialized',
      () async {
        await service.showTurnCompleted(turnSummary: 'Done', turnId: 't-1');

        expect(sink.shown, isEmpty);
      },
    );

    test(
      'posts the turn summary as the body under the Hermes turn channel',
      () async {
        await service.ensureInitialized();

        await service.showTurnCompleted(
          turnSummary: 'Roadmap: Response ready',
          turnId: 'turn-42',
        );

        expect(sink.shown, hasLength(1));
        final posted = sink.shown.single;
        expect(posted.title, 'Hermes response ready');
        expect(posted.body, 'Roadmap: Response ready');
        // The payload is the deep-link seed Phase 3 will extend.
        expect(posted.payload, 'turn-42');
        expect(posted.channel.id, 'hermes_turn_notifications');
        expect(posted.channel.name, 'Hermes Turns');
        expect(
          posted.channel.description,
          'Notifications for completed background turns',
        );
      },
    );

    test(
      'reuses one stable id per turn so a turn never stacks duplicates',
      () async {
        await service.ensureInitialized();

        await service.showTurnCompleted(
          turnSummary: 'first',
          turnId: 'turn-42',
        );
        await service.showTurnCompleted(
          turnSummary: 'second',
          turnId: 'turn-42',
        );

        expect(sink.shown.map((n) => n.id).toSet(), hasLength(1));
        expect(sink.shown.map((n) => n.body), ['first', 'second']);
      },
    );

    test('gives distinct turns distinct ids', () async {
      await service.ensureInitialized();

      await service.showTurnCompleted(turnSummary: 'a', turnId: 'turn-1');
      await service.showTurnCompleted(turnSummary: 'b', turnId: 'turn-2');

      expect(sink.shown.map((n) => n.id).toSet(), hasLength(2));
    });

    test('always produces a non-negative Android notification id', () async {
      await service.ensureInitialized();

      for (final turnId in [
        'turn-1',
        'client:9f3a-4d21',
        'a very long server issued turn identifier 0123456789',
        '',
      ]) {
        await service.showTurnCompleted(turnSummary: 's', turnId: turnId);
      }

      expect(sink.shown.map((n) => n.id), everyElement(isNonNegative));
    });
  });

  group('runtime permission', () {
    test(
      'initialization asks Android for the notification permission',
      () async {
        await service.ensureInitialized();

        // Android 13+ denies POST_NOTIFICATIONS by default even when the
        // manifest declares it. Never asking means every notification is
        // silently dropped by the OS.
        expect(sink.permissionRequestCount, 1);
      },
    );

    test('the permission is requested once, not on every call', () async {
      await service.ensureInitialized();
      await service.ensureInitialized();

      expect(sink.permissionRequestCount, 1);
    });

    test(
      'a denied permission is reported instead of silently dropping posts',
      () async {
        sink.permissionResult = false;

        await service.ensureInitialized();

        expect(service.permissionGranted, isFalse);
      },
    );

    test('a granted permission lets turn notifications through', () async {
      sink.permissionResult = true;

      await service.ensureInitialized();
      await service.showTurnCompleted(turnSummary: 'done', turnId: 'turn-1');

      expect(service.permissionGranted, isTrue);
      expect(sink.shown, hasLength(1));
    });

    test('a platform that needs no runtime permission stays usable', () async {
      // iOS and Android < 13 return null: no runtime gate to satisfy.
      sink.permissionResult = null;

      await service.ensureInitialized();
      await service.showTurnCompleted(turnSummary: 'done', turnId: 'turn-1');

      expect(service.permissionGranted, isTrue);
      expect(sink.shown, hasLength(1));
    });

    test(
      'a failing permission request does not break initialization',
      () async {
        sink.permissionError = StateError('no platform channel');

        await service.ensureInitialized();

        // The app must keep running; notifications degrade, they never crash.
        await service.showTurnCompleted(turnSummary: 'done', turnId: 'turn-1');
        expect(sink.shown, hasLength(1));
      },
    );
  });

  group('cancellation', () {
    test('cancels the exact id that was shown for that turn', () async {
      await service.ensureInitialized();
      await service.showTurnCompleted(turnSummary: 'done', turnId: 'turn-42');

      await service.cancelTurnCompleted('turn-42');

      expect(sink.cancelled, [sink.shown.single.id]);
    });

    test('is a no-op before initialization', () async {
      await service.cancelTurnCompleted('turn-42');
      await service.cancelAll();

      expect(sink.cancelled, isEmpty);
      expect(sink.cancelAllCount, 0);
    });

    test('cancelAll clears every Hermes turn notification', () async {
      await service.ensureInitialized();
      await service.showTurnCompleted(turnSummary: 'a', turnId: 'turn-1');
      await service.showTurnCompleted(turnSummary: 'b', turnId: 'turn-2');

      await service.cancelAll();

      expect(sink.cancelAllCount, 1);
    });
  });
}
