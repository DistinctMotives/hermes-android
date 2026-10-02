import 'package:flutter/material.dart';

import '../controllers/voice_composer_controller.dart';

class VoiceComposerIndicator extends StatelessWidget {
  static const indicatorKey = Key('voice-listening-indicator');
  static const stopKey = Key('voice-stop');
  static const cancelKey = Key('voice-cancel');

  final VoiceComposerController controller;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  const VoiceComposerIndicator({
    required this.controller,
    required this.onStop,
    required this.onCancel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final elapsed = _formatElapsed(controller.elapsed);
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Listening, elapsed $elapsed',
      child: Container(
        key: indicatorKey,
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(4, 2, 4, 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 420 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.4;
            final status = Row(
              mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Icon(
                  Icons.mic,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Flexible(child: Text('Listening • $elapsed')),
              ],
            );
            final actions = Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                Semantics(
                  label: 'Stop voice input',
                  button: true,
                  excludeSemantics: true,
                  child: TextButton.icon(
                    key: stopKey,
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop'),
                  ),
                ),
                Semantics(
                  label: 'Cancel voice input',
                  button: true,
                  excludeSemantics: true,
                  child: TextButton.icon(
                    key: cancelKey,
                    onPressed: onCancel,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                  ),
                ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  status,
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: status),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }

  static String _formatElapsed(Duration elapsed) {
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class VoiceComposerStartButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const VoiceComposerStartButton({
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Start voice input',
      button: true,
      enabled: enabled,
      excludeSemantics: true,
      child: IconButton.filledTonal(
        icon: const Icon(Icons.mic),
        onPressed: enabled ? onPressed : null,
        tooltip: 'Speak to Hermes',
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      ),
    );
  }
}
