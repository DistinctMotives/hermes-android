import 'package:hermes_android/core/services/turn_notification_service.dart';

/// In-memory [TurnNotificationSink] used to characterize what Hermes actually
/// posts to Android, without touching the platform plugin.
class RecordingTurnNotificationSink implements TurnNotificationSink {
  final List<TurnNotification> shown = <TurnNotification>[];
  final List<int> cancelled = <int>[];

  int initializeCount = 0;
  int cancelAllCount = 0;
  int permissionRequestCount = 0;

  /// Result [requestPermission] returns: true granted, false denied, null when
  /// the platform has no runtime notification gate (iOS, Android < 13).
  bool? permissionResult;

  /// When set, [requestPermission] throws it.
  Object? permissionError;

  /// When set, [initialize] throws it — mirroring a platform channel that is
  /// unavailable (test environment, missing plugin registration).
  Object? initializeError;

  @override
  Future<void> initialize() async {
    initializeCount++;
    final error = initializeError;
    if (error != null) throw error;
  }

  @override
  Future<bool?> requestPermission() async {
    permissionRequestCount++;
    final error = permissionError;
    if (error != null) throw error;
    return permissionResult;
  }

  @override
  Future<void> show(TurnNotification notification) async {
    shown.add(notification);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
  }
}
