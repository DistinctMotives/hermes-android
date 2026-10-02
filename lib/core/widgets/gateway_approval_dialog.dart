import 'package:flutter/material.dart';

import '../models/gateway_approval.dart';

typedef ApprovalResponder = Future<void> Function(GatewayApprovalChoice choice);

class GatewayApprovalDialog extends StatefulWidget {
  final GatewayApprovalRequest request;
  final ApprovalResponder onRespond;

  const GatewayApprovalDialog({
    required this.request,
    required this.onRespond,
    super.key,
  });

  @override
  State<GatewayApprovalDialog> createState() => _GatewayApprovalDialogState();
}

class _GatewayApprovalDialogState extends State<GatewayApprovalDialog> {
  GatewayApprovalChoice? _submitting;
  bool _confirmAlways = false;
  String? _error;

  Future<void> _respond(GatewayApprovalChoice choice) async {
    if (_submitting != null) return;
    if (choice == GatewayApprovalChoice.always && !_confirmAlways) {
      setState(() {
        _confirmAlways = true;
        _error = null;
      });
      return;
    }

    setState(() {
      _submitting = choice;
      _error = null;
    });
    try {
      await widget.onRespond(choice);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = null;
        _error = 'Could not send the approval: $error';
      });
    }
  }

  String _labelFor(GatewayApprovalChoice choice) {
    return switch (choice) {
      GatewayApprovalChoice.once => 'Allow once',
      GatewayApprovalChoice.session => 'Allow for this session',
      GatewayApprovalChoice.always =>
        _confirmAlways ? 'Confirm always allow' : 'Always allow',
      GatewayApprovalChoice.deny => 'Deny',
    };
  }

  String _scopeFor(GatewayApprovalChoice choice) {
    return switch (choice) {
      GatewayApprovalChoice.once => 'Run only this command.',
      GatewayApprovalChoice.session =>
        'Allow matching commands until this Hermes session ends.',
      GatewayApprovalChoice.always =>
        'Save a permanent rule in the Hermes configuration.',
      GatewayApprovalChoice.deny => 'Do not run this command.',
    };
  }

  IconData _iconFor(GatewayApprovalChoice choice) {
    return switch (choice) {
      GatewayApprovalChoice.once => Icons.play_arrow_rounded,
      GatewayApprovalChoice.session => Icons.timer_outlined,
      GatewayApprovalChoice.always => Icons.verified_user_outlined,
      GatewayApprovalChoice.deny => Icons.block_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = widget.request;
    final busy = _submitting != null;

    return AlertDialog(
      icon: const Icon(Icons.gpp_maybe_outlined),
      title: const Text('Approval needed'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(request.description),
              if (request.command.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Command', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    request.command,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
              if (_confirmAlways) ...[
                const SizedBox(height: 14),
                Text(
                  'This creates a permanent rule in Hermes. Review the full '
                  'command before confirming.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  key: const Key('approval-error'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              for (final choice in request.choices) ...[
                OutlinedButton.icon(
                  key: Key('approval-${choice.wireValue}'),
                  onPressed: busy ? null : () => _respond(choice),
                  icon: _submitting == choice
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_iconFor(choice)),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_labelFor(choice)),
                        Text(
                          _scopeFor(choice),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  style: choice == GatewayApprovalChoice.deny
                      ? OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        )
                      : null,
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
