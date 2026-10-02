import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android publishes a static New Quick Chat launcher shortcut', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();
    final shortcuts = await File(
      'android/app/src/main/res/xml/shortcuts.xml',
    ).readAsString();

    expect(manifest, contains('android.app.shortcuts'));
    expect(manifest, contains('@xml/shortcuts'));
    expect(shortcuts, contains('android:shortcutId="new_quick_chat"'));
    expect(
      shortcuts,
      contains('com.hermesagent.hermes_android.action.QUICK_CHAT'),
    );
  });

  test('MainActivity forwards cold and warm shortcut launches', () async {
    final source = await File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/MainActivity.kt',
    ).readAsString();

    expect(source, contains('getInitialLaunchAction'));
    expect(source, contains('launchAction'));
    expect(source, contains('QUICK_CHAT'));
  });
}
