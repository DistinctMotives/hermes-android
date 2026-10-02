import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges Android launcher actions into the Flutter navigation lifecycle.
class AndroidLaunchIntentService {
  static const channelName = 'com.hermesagent.hermes_android/launch';
  static const _quickChatAction = 'quickChat';

  final MethodChannel _channel;
  final ValueNotifier<bool> pendingQuickChat = ValueNotifier(false);
  bool _initialized = false;

  AndroidLaunchIntentService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
    try {
      _publish(await _channel.invokeMethod<String>('getInitialLaunchAction'));
    } on MissingPluginException {
      // Non-Android builds do not provide launcher shortcuts.
    } on PlatformException {
      // A launcher failure must never prevent the app from opening normally.
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'launchAction') return;
    _publish(call.arguments as String?);
  }

  void _publish(String? action) {
    if (action == _quickChatAction) pendingQuickChat.value = true;
  }

  bool takePendingQuickChat() {
    final pending = pendingQuickChat.value;
    if (pending) pendingQuickChat.value = false;
    return pending;
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    pendingQuickChat.dispose();
  }
}
