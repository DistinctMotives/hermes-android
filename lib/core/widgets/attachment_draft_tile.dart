import 'dart:io';

import 'package:flutter/material.dart';

import '../models/attachment_draft.dart';

class AttachmentDraftTile extends StatelessWidget {
  final AttachmentDraft draft;
  final int index;
  final int total;
  final bool busy;
  final VoidCallback onMovePrevious;
  final VoidCallback onMoveNext;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const AttachmentDraftTile({
    required this.draft,
    required this.index,
    required this.total,
    required this.busy,
    required this.onMovePrevious,
    required this.onMoveNext,
    required this.onRetry,
    required this.onRemove,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Attachment ${index + 1} of $total',
      value: _statusLabel(),
      child: ListTile(
        minVerticalPadding: 4,
        leading: ExcludeSemantics(child: _leading(context)),
        title: ExcludeSemantics(
          child: Text(draft.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        subtitle: ExcludeSemantics(
          child: Text(
            draft.status == AttachmentDraftStatus.failed
                ? 'Upload failed • tap retry'
                : '${_formatFileSize(draft.byteLength)} • ${draft.status.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _semanticIconButton(
              icon: Icons.arrow_upward,
              label: 'Move attachment previous',
              onPressed: busy || index == 0 ? null : onMovePrevious,
            ),
            _semanticIconButton(
              icon: Icons.arrow_downward,
              label: 'Move attachment next',
              onPressed: busy || index == total - 1 ? null : onMoveNext,
            ),
            if (draft.status == AttachmentDraftStatus.failed)
              _semanticIconButton(
                icon: Icons.refresh,
                label: 'Retry upload',
                onPressed: busy ? null : onRetry,
              )
            else
              _semanticIconButton(
                icon: Icons.close,
                label: 'Remove attachment',
                onPressed: busy ? null : onRemove,
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel() => switch (draft.status) {
    AttachmentDraftStatus.ready => 'Ready to upload',
    AttachmentDraftStatus.uploading => 'Uploading',
    AttachmentDraftStatus.attached => 'Uploaded',
    AttachmentDraftStatus.failed => 'Upload failed',
  };

  Widget _leading(BuildContext context) {
    return switch (draft.status) {
      AttachmentDraftStatus.uploading => const SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      AttachmentDraftStatus.attached => const Icon(
        Icons.check_circle_outline,
        color: Colors.green,
      ),
      AttachmentDraftStatus.failed => Icon(
        Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      AttachmentDraftStatus.ready when draft.isImage => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(draft.cachedPath),
          width: 44,
          height: 44,
          cacheWidth: 112,
          cacheHeight: 112,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        ),
      ),
      AttachmentDraftStatus.ready => const Icon(Icons.description_outlined),
    };
  }

  Widget _semanticIconButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return Semantics(
      label: label,
      button: true,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: IconButton(
        icon: Icon(icon, size: 20),
        tooltip: label,
        onPressed: onPressed,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}
