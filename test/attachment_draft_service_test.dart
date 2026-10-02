import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/services/attachment_draft_service.dart';
import 'package:image/image.dart' as image_lib;

void main() {
  late Directory sandbox;
  late Directory cache;
  late AttachmentDraftService service;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('hermes-drafts-test-');
    cache = Directory('${sandbox.path}${Platform.pathSeparator}cache');
    service = AttachmentDraftService(
      cacheDirectoryProvider: () async => cache,
      clock: () => DateTime.utc(2026, 8, 9),
    );
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  AttachmentDraft fakeDraft({
    required String name,
    required int byteLength,
    AttachmentDraftKind kind = AttachmentDraftKind.genericFile,
    AttachmentDraftStatus status = AttachmentDraftStatus.ready,
  }) {
    return AttachmentDraft(
      id: name,
      cachedPath: '${sandbox.path}${Platform.pathSeparator}$name',
      name: name,
      byteLength: byteLength,
      mediaType: kind == AttachmentDraftKind.image
          ? 'image/png'
          : 'application/octet-stream',
      kind: kind,
      sanitized: kind == AttachmentDraftKind.image,
      status: status,
    );
  }

  Future<AttachmentDraft> cachedDraft(
    String name, {
    AttachmentDraftStatus status = AttachmentDraftStatus.ready,
    AttachmentDraftKind kind = AttachmentDraftKind.genericFile,
  }) async {
    final file = File('${sandbox.path}${Platform.pathSeparator}$name');
    await file.writeAsString('payload-$name');
    return AttachmentDraft(
      id: name,
      cachedPath: file.path,
      name: name,
      byteLength: await file.length(),
      mediaType: kind == AttachmentDraftKind.image
          ? 'image/png'
          : 'application/octet-stream',
      kind: kind,
      sanitized: kind == AttachmentDraftKind.image,
      status: status,
    );
  }

  group('file-backed drafts and limits', () {
    test(
      'generic selection copies into private cache without model bytes',
      () async {
        final source = File(
          '${sandbox.path}${Platform.pathSeparator}report.txt',
        );
        await source.writeAsString('synthetic report');

        final draft = await service.prepareGenericFile(
          sourcePath: source.path,
          displayName: 'report.txt',
          mediaType: 'text/plain',
          existingDrafts: const [],
        );

        expect(draft.cachedPath, isNot(source.path));
        expect(await File(draft.cachedPath).readAsString(), 'synthetic report');
        expect(draft.byteLength, await source.length());
        expect(draft.kind, AttachmentDraftKind.genericFile);
        expect(draft.mediaType, 'text/plain');

        final modelSource = await File(
          'lib/core/models/attachment_draft.dart',
        ).readAsString();
        expect(modelSource, isNot(contains('Uint8List')));
        expect(modelSource, isNot(contains('dataUrl')));

        await service.removeCachedFile(draft);
        expect(await File(draft.cachedPath).exists(), isFalse);
      },
    );

    test('accepts 10 items and rejects item 11', () {
      final ten = List.generate(
        maxRemoteAttachmentDrafts,
        (index) => fakeDraft(name: '$index.bin', byteLength: 1),
      );
      expect(() => service.validateRemoteDrafts(ten), returnsNormally);
      expect(
        () => service.validateRemoteDrafts([
          ...ten,
          fakeDraft(name: 'eleven.bin', byteLength: 1),
        ]),
        throwsA(isA<AttachmentDraftException>()),
      );
    });

    test('enforces the numeric 64 MiB aggregate budget', () {
      final exact = fakeDraft(
        name: 'exact.png',
        byteLength: 64 * 1024 * 1024,
        kind: AttachmentDraftKind.image,
      );
      expect(() => service.validateRemoteDrafts([exact]), returnsNormally);
      expect(
        () => service.validateRemoteDrafts([
          exact,
          fakeDraft(name: 'overflow.bin', byteLength: 1),
        ]),
        throwsA(isA<AttachmentDraftException>()),
      );
    });

    test('keeps the generic per-file limit at 16 MiB', () {
      expect(
        () => service.validateRemoteDrafts([
          fakeDraft(name: 'exact.bin', byteLength: 16 * 1024 * 1024),
        ]),
        returnsNormally,
      );
      expect(
        () => service.validateRemoteDrafts([
          fakeDraft(name: 'large.bin', byteLength: 16 * 1024 * 1024 + 1),
        ]),
        throwsA(isA<AttachmentDraftException>()),
      );
    });

    test('REST is fail-closed for multiple images and generic files', () {
      final first = fakeDraft(
        name: 'first.png',
        byteLength: 10,
        kind: AttachmentDraftKind.image,
      );
      final second = fakeDraft(
        name: 'second.png',
        byteLength: 10,
        kind: AttachmentDraftKind.image,
      );
      expect(() => service.validateRestDrafts([first]), returnsNormally);
      expect(allowsMultipleImageSelection(AttachmentDraftMode.rest), isFalse);
      expect(
        allowsMultipleImageSelection(AttachmentDraftMode.remoteGateway),
        isTrue,
      );
      expect(
        () => service.validateRestDrafts([first, second]),
        throwsA(isA<AttachmentDraftException>()),
      );
      expect(
        () => service.validateRestDrafts([
          fakeDraft(name: 'document.pdf', byteLength: 10),
        ]),
        throwsA(isA<AttachmentDraftException>()),
      );
    });

    test(
      'failed preparation retains two images and a document selection',
      () async {
        final firstImage = await cachedDraft(
          'first.png',
          kind: AttachmentDraftKind.image,
        );
        final secondImage = await cachedDraft(
          'second.png',
          kind: AttachmentDraftKind.image,
        );
        final document = await cachedDraft('retained.pdf');
        final drafts = [firstImage, secondImage, document];
        expect(() => service.validateRemoteDrafts(drafts), returnsNormally);
        final unsupported = File(
          '${sandbox.path}${Platform.pathSeparator}animation.gif',
        );
        final gifImage = image_lib.Image(width: 2, height: 2)
          ..setPixelRgba(0, 0, 0, 0, 255, 255);
        await unsupported.writeAsBytes(image_lib.encodeGif(gifImage));

        await expectLater(
          service.prepareImage(
            sourcePath: unsupported.path,
            displayName: 'animation.gif',
            existingDrafts: drafts,
            mode: AttachmentDraftMode.remoteGateway,
          ),
          throwsA(
            isA<AttachmentDraftException>().having(
              (error) => error.message,
              'message',
              contains('Unsupported image format'),
            ),
          ),
        );
        expect(drafts, [same(firstImage), same(secondImage), same(document)]);
        for (final draft in drafts) {
          expect(await File(draft.cachedPath).exists(), isTrue);
        }
      },
    );

    test(
      'partial sanitized output is deleted when cache writing fails',
      () async {
        final source = File(
          '${sandbox.path}${Platform.pathSeparator}source.png',
        );
        await source.writeAsBytes(
          image_lib.encodePng(image_lib.Image(width: 2, height: 2)),
        );
        final failingService = AttachmentDraftService(
          cacheDirectoryProvider: () async => cache,
          cacheFileWriter: (destination, bytes) async {
            await destination.writeAsBytes(bytes.take(8).toList());
            throw const FileSystemException('synthetic partial write');
          },
        );

        await expectLater(
          failingService.prepareImage(
            sourcePath: source.path,
            displayName: 'source.png',
            existingDrafts: const [],
            mode: AttachmentDraftMode.remoteGateway,
          ),
          throwsA(isA<AttachmentDraftException>()),
        );
        expect(await cache.exists(), isTrue);
        expect(await cache.list().toList(), isEmpty);
      },
    );
  });

  group('image sanitization', () {
    Future<AttachmentDraft> prepareBytes(String name, List<int> bytes) async {
      final source = File('${sandbox.path}${Platform.pathSeparator}$name');
      await source.writeAsBytes(bytes);
      return service.prepareImage(
        sourcePath: source.path,
        displayName: name,
        existingDrafts: const [],
        mode: AttachmentDraftMode.remoteGateway,
      );
    }

    test('JPEG is decoded, metadata-cleared, and re-encoded as JPEG', () async {
      final sourceImage = image_lib.Image(width: 2, height: 2)
        ..setPixelRgba(0, 0, 255, 0, 0, 255);
      sourceImage.exif.imageIfd[0x010e] = image_lib.IfdValueAscii(
        'synthetic GPS marker',
      );
      final sourceBytes = image_lib.encodeJpg(sourceImage);
      expect(utf8.decode(sourceBytes, allowMalformed: true), contains('Exif'));

      final draft = await prepareBytes('photo.jpg', sourceBytes);
      final output = await File(draft.cachedPath).readAsBytes();
      final decoded = image_lib.decodeJpg(output)!;

      expect(draft.mediaType, 'image/jpeg');
      expect(draft.name, 'photo.jpg');
      expect(draft.sourceImageFormat, AttachmentImageFormat.jpeg);
      expect(decoded.exif.isEmpty, isTrue);
      expect(decoded.iccProfile, isNull);
      expect(decoded.textData, anyOf(isNull, isEmpty));
    });

    test('PNG is decoded, metadata-cleared, and re-encoded as PNG', () async {
      final sourceImage = image_lib.Image(width: 2, height: 2)
        ..setPixelRgba(0, 0, 0, 255, 0, 255)
        ..textData = {'GPS': 'synthetic marker'};
      final draft = await prepareBytes(
        'diagram.png',
        image_lib.encodePng(sourceImage),
      );
      final decoded = image_lib.decodePng(
        await File(draft.cachedPath).readAsBytes(),
      )!;

      expect(draft.mediaType, 'image/png');
      expect(draft.name, 'diagram.png');
      expect(draft.sourceImageFormat, AttachmentImageFormat.png);
      expect(decoded.exif.isEmpty, isTrue);
      expect(decoded.iccProfile, isNull);
      expect(decoded.textData, anyOf(isNull, isEmpty));
    });

    test(
      'WebP is decoded and explicitly re-encoded as metadata-free PNG',
      () async {
        final webp = base64Decode(
          'UklGRh4AAABXRUJQVlA4TBEAAAAvAUAAAAdQiirUo/+BiOh/AAA=',
        );
        final draft = await prepareBytes('camera.webp', webp);
        final output = await File(draft.cachedPath).readAsBytes();
        final decoded = image_lib.decodePng(output)!;

        expect(draft.mediaType, 'image/png');
        expect(draft.name, 'camera.png');
        expect(draft.sourceImageFormat, AttachmentImageFormat.webp);
        expect(output.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        expect(decoded.exif.isEmpty, isTrue);
        expect(decoded.iccProfile, isNull);
        expect(decoded.textData, anyOf(isNull, isEmpty));
      },
    );
  });

  group('ordered upload, retry, and cleanup', () {
    test(
      'reorder changes sequential file.attach order with concurrency one',
      () async {
        final first = await cachedDraft('first.txt');
        final second = await cachedDraft('second.txt');
        final third = await cachedDraft('third.txt');
        final drafts = [first, second, third];
        expect(service.moveDraft(drafts, fromIndex: 2, offset: -1), isTrue);
        expect(drafts.map((draft) => draft.name), [
          'first.txt',
          'third.txt',
          'second.txt',
        ]);

        final calls = <String>[];
        var active = 0;
        var maxActive = 0;
        var promptSubmitCalls = 0;
        final coordinator = AttachmentDraftSendCoordinator(service);
        await coordinator.uploadThenSubmit(
          drafts: drafts,
          upload: ({required draft, required dataUrl}) async {
            active++;
            if (active > maxActive) maxActive = active;
            calls.add(draft.name);
            expect(
              dataUrl,
              startsWith('data:application/octet-stream;base64,'),
            );
            await Future<void>.delayed(const Duration(milliseconds: 5));
            active--;
            return AttachmentUploadReceipt(refText: '@file:${draft.name}');
          },
          submitPrompt: (refs) async {
            promptSubmitCalls++;
            expect(active, 0);
            expect(calls, ['first.txt', 'third.txt', 'second.txt']);
            expect(refs, [
              '@file:first.txt',
              '@file:third.txt',
              '@file:second.txt',
            ]);
          },
        );

        expect(calls, ['first.txt', 'third.txt', 'second.txt']);
        expect(maxActive, 1);
        expect(promptSubmitCalls, 1);
        expect(
          drafts.map((draft) => draft.status),
          everyElement(AttachmentDraftStatus.attached),
        );
        for (final draft in drafts) {
          expect(await File(draft.cachedPath).exists(), isFalse);
        }
      },
    );

    test('upload failure keeps selection and cache for retry', () async {
      final first = await cachedDraft('failed.txt');
      final second = await cachedDraft('waiting.txt');
      final drafts = [first, second];

      await expectLater(
        service.uploadSequential(
          drafts: drafts,
          upload: ({required draft, required dataUrl}) async {
            throw StateError('synthetic upload failure');
          },
        ),
        throwsStateError,
      );

      expect(drafts, [same(first), same(second)]);
      expect(first.status, AttachmentDraftStatus.failed);
      expect(second.status, AttachmentDraftStatus.ready);
      expect(await File(first.cachedPath).exists(), isTrue);
      expect(await File(second.cachedPath).exists(), isTrue);
    });

    test(
      'retry uploads only the failed item and never submits a prompt',
      () async {
        final failed = await cachedDraft(
          'failed.txt',
          status: AttachmentDraftStatus.failed,
        );
        final untouched = await cachedDraft('untouched.txt');
        var attachCalls = 0;
        var promptSubmitCalls = 0;
        final coordinator = AttachmentDraftSendCoordinator(service);

        final receipt = await coordinator.retryFailed(
          draft: failed,
          upload: ({required draft, required dataUrl}) async {
            attachCalls++;
            expect(draft, same(failed));
            return const AttachmentUploadReceipt(refText: '@file:failed.txt');
          },
        );

        expect(receipt.refText, '@file:failed.txt');
        expect(attachCalls, 1);
        expect(promptSubmitCalls, 0);
        expect(failed.status, AttachmentDraftStatus.attached);
        expect(untouched.status, AttachmentDraftStatus.ready);
        expect(await File(failed.cachedPath).exists(), isFalse);
        expect(await File(untouched.cachedPath).exists(), isTrue);
      },
    );
  });
}
