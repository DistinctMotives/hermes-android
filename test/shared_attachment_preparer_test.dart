import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/services/android_share_intent_service.dart';
import 'package:hermes_android/core/services/attachment_draft_service.dart';
import 'package:hermes_android/core/services/shared_attachment_preparer.dart';
import 'package:image/image.dart' as image_lib;

void main() {
  test('prepares shared images and documents in Android share order', () async {
    final root = await Directory.systemTemp.createTemp('shared-preparer-');
    addTearDown(() => root.delete(recursive: true));
    final input = Directory('${root.path}/input')..createSync();
    final cache = Directory('${root.path}/cache')..createSync();
    final pdf = File('${input.path}/report.pdf')
      ..writeAsBytesSync([0x25, 0x50, 0x44, 0x46]);
    final photo = File('${input.path}/photo.png')
      ..writeAsBytesSync(
        image_lib.encodePng(image_lib.Image(width: 2, height: 2)),
      );
    final service = AttachmentDraftService(
      cacheDirectoryProvider: () async => cache,
    );

    final drafts = await prepareAndroidSharedFiles(
      const [
        AndroidSharedFile(
          path: 'PDF_PATH',
          name: 'report.pdf',
          mediaType: 'application/pdf',
          byteLength: 4,
        ),
        AndroidSharedFile(
          path: 'PHOTO_PATH',
          name: 'photo.png',
          mediaType: 'image/png',
          byteLength: 1,
        ),
      ].map(
        (file) => AndroidSharedFile(
          path: file.path == 'PDF_PATH' ? pdf.path : photo.path,
          name: file.name,
          mediaType: file.mediaType,
          byteLength: file.byteLength,
        ),
      ),
      service: service,
    );

    expect(drafts.map((draft) => draft.name), ['report.pdf', 'photo.png']);
    expect(drafts.first.mediaType, 'application/pdf');
    expect(drafts.first.kind, AttachmentDraftKind.genericFile);
    expect(drafts.last.kind, AttachmentDraftKind.image);
    expect(drafts.last.sanitized, isTrue);
  });
}
