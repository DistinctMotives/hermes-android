import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android advertises single and multiple file sharing', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();

    expect(manifest, contains('android.intent.action.SEND'));
    expect(manifest, contains('android.intent.action.SEND_MULTIPLE'));
    expect(manifest, contains('android:mimeType="*/*"'));
  });

  test(
    'MainActivity copies shared streams before handing them to Flutter',
    () async {
      final source = await File(
        'android/app/src/main/kotlin/com/hermesagent/hermes_android/MainActivity.kt',
      ).readAsString();

      expect(source, contains('Intent.ACTION_SEND_MULTIPLE'));
      expect(source, contains('Intent.EXTRA_STREAM'));
      expect(source, contains('contentResolver.openInputStream'));
      expect(source, contains('sharePayload'));
    },
  );
}
