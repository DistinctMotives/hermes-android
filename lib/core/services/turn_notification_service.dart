import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The Android/iOS notification channel a [TurnNotification] belongs to.
///
/// Phase 3 of the daily-driver roadmap replaces the single Hermes Turns
/// channel with four prioritized channels; describing the channel as data
/// keeps that change testable.
class TurnNotificationChannel {
  final String id;
  final String name;
  final String description;

  const TurnNotificationChannel({
    required this.id,
    required this.name,
    required this.description,
  });
}

/// A notification Hermes wants Android to post, described as plain data.
class TurnNotification {
  final int id;
  final String title;
  final String body;
  final String payload;
  final TurnNotificationChannel channel;

  const TurnNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    required this.channel,
  });
}

/// The platform seam [TurnNotificationService] posts through.
///
/// The production implementation is [PluginTurnNotificationSink]; tests supply
/// a recording double so notification behaviour can be verified without a
/// platform channel.
abstract class TurnNotificationSink {
  Future<void> initialize();

  /// Asks the platform for permission to post notifications.
  ///
  /// Returns `true` when granted, `false` when denied, and `null` when the
  /// platform has no runtime gate (iOS, Android < 13) — in which case posting
  /// is already allowed.
  Future<bool?> requestPermission();

  Future<void> show(TurnNotification notification);

  Future<void> cancel(int id);

  Future<void> cancelAll();
}

/// Default sink backed by `flutter_local_notifications`.
class PluginTurnNotificationSink implements TurnNotificationSink {
  final FlutterLocalNotificationsPlugin _plugin;

  PluginTurnNotificationSink({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);
  }

  @override
  Future<bool?> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return android.requestNotificationsPermission();
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return ios.requestPermissions(alert: true, badge: true, sound: true);
    }

    // No platform implementation resolved: nothing gates posting here.
    return null;
  }

  @override
  Future<void> show(TurnNotification notification) async {
    final androidDetails = AndroidNotificationDetails(
      notification.channel.id,
      notification.channel.name,
      channelDescription: notification.channel.description,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      autoCancel: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      notification.id,
      notification.title,
      notification.body,
      details,
      payload: notification.payload,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}

/// Delivers Android notifications when a gateway turn completes while the app
/// is backgrounded, mirroring the Hermes Desktop tray notification behaviour.
///
/// The service owns a single notification channel ("Hermes Turns") and exposes
/// one idempotent [ensureInitialized] method safe to call from any lifecycle
/// point (including before the Flutter engine binding is ready).
class TurnNotificationService {
  static const turnChannel = TurnNotificationChannel(
    id: 'hermes_turn_notifications',
    name: 'Hermes Turns',
    description: 'Notifications for completed background turns',
  );

  final TurnNotificationSink _sink;

  bool _initialized = false;
  bool _permissionGranted = true;

  TurnNotificationService({
    TurnNotificationSink? sink,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _sink = sink ?? PluginTurnNotificationSink(plugin: plugin);

  /// Whether the platform currently allows Hermes to post notifications.
  ///
  /// `false` means Android 13+ denied POST_NOTIFICATIONS: turns still complete
  /// but the OS drops every notification, so the UI can surface that instead of
  /// leaving the user wondering why nothing arrives.
  bool get permissionGranted => _permissionGranted;

  /// One-shot initialisation of the Hermes notification channel.
  ///
  /// Safe to call repeatedly — once it has succeeded, subsequent calls are
  /// no-ops. A failed attempt (platform channel unavailable, e.g. in tests)
  /// degrades to a silent no-op and may be retried later.
  Future<void> ensureInitialized() async {
    if (_initialized) return;

    try {
      await _sink.initialize();
      _initialized = true;
    } catch (_) {
      // Platform not available (e.g. test environment) — notifications
      // silently degrade to no-op.
      return;
    }

    // Android 13+ denies POST_NOTIFICATIONS until it is requested at runtime,
    // even though the manifest declares it. Without this, every notification
    // is dropped by the OS with no error surfaced anywhere.
    try {
      final granted = await _sink.requestPermission();
      _permissionGranted = granted ?? true;
    } catch (_) {
      // A failing permission channel must not break the app; assume the
      // platform imposes no runtime gate rather than blocking notifications.
      _permissionGranted = true;
    }
  }

  /// Posts a notification when a gateway turn completes while the app is
  /// backgrounded.
  ///
  /// [turnSummary] is a short description (e.g. session title or prompt
  /// excerpt); [turnId] ensures the notification is stable and replaceable.
  Future<void> showTurnCompleted({
    required String turnSummary,
    required String turnId,
  }) async {
    if (!_initialized) return;

    await _sink.show(
      TurnNotification(
        id: notificationIdFor(turnId),
        title: 'Hermes response ready',
        body: turnSummary,
        payload: turnId,
        channel: turnChannel,
      ),
    );
  }

  /// Cancels a specific turn notification.
  Future<void> cancelTurnCompleted(String turnId) async {
    if (!_initialized) return;
    await _sink.cancel(notificationIdFor(turnId));
  }

  /// Removes all Hermes turn notifications.
  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _sink.cancelAll();
  }

  /// Stable, non-negative Android notification id derived from [turnId].
  ///
  /// Masking instead of negating keeps the id inside the 31-bit range Android
  /// accepts, and keeps one turn mapped to exactly one notification so a turn
  /// replaces its own notification instead of stacking duplicates.
  static int notificationIdFor(String turnId) => turnId.hashCode & 0x7fffffff;
}
