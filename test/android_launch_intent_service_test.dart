import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/android_launch_intent_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AndroidLaunchIntentService.channelName);

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('initializes from a cold-start Quick Chat shortcut once', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getInitialLaunchAction');
          return 'quickChat';
        });

    final service = AndroidLaunchIntentService();
    await service.initialize();

    expect(service.pendingQuickChat.value, isTrue);
    expect(service.takePendingQuickChat(), isTrue);
    expect(service.takePendingQuickChat(), isFalse);
  });

  test('receives a warm Quick Chat shortcut from Android', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    final service = AndroidLaunchIntentService();
    await service.initialize();

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            const MethodCall('launchAction', 'quickChat'),
          ),
          (_) {},
        );

    expect(service.takePendingQuickChat(), isTrue);
    expect(service.takePendingQuickChat(), isFalse);
  });
}
