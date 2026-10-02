import 'dart:io';

import '../models/attachment_draft.dart';
import 'android_share_intent_service.dart';
import 'attachment_draft_service.dart';

Future<List<AttachmentDraft>> prepareAndroidSharedFiles(
  Iterable<AndroidSharedFile> files, {
  AttachmentDraftService? service,
}) async {
  final draftService = service ?? AttachmentDraftService();
  final drafts = <AttachmentDraft>[];
  try {
    for (final file in files) {
      final draft = file.isImage
          ? await draftService.prepareImage(
              sourcePath: file.path,
              displayName: file.name,
              existingDrafts: drafts,
              mode: AttachmentDraftMode.remoteGateway,
            )
          : await draftService.prepareGenericFile(
              sourcePath: file.path,
              displayName: file.name,
              mediaType: file.mediaType,
              existingDrafts: drafts,
            );
      drafts.add(draft);
    }
    draftService.validateRemoteDrafts(drafts);
    return drafts;
  } catch (_) {
    for (final draft in drafts) {
      try {
        await File(draft.cachedPath).delete();
      } catch (_) {}
    }
    rethrow;
  }
}
