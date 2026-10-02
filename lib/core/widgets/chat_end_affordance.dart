import 'package:flutter/material.dart';

/// Accessible floating action that returns a chat to its current end.
class ChatEndAffordance extends StatelessWidget {
  static const buttonKey = Key('chat-go-to-end');
  static const countKey = Key('chat-new-message-count');

  final int newMessageCount;
  final VoidCallback onPressed;

  const ChatEndAffordance({
    required this.newMessageCount,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final hasNewMessages = newMessageCount > 0;
    final indicatorText = hasNewMessages ? '$newMessageCount new' : 'Latest';
    final semanticsValue = switch (newMessageCount) {
      0 => 'No new messages',
      1 => '1 new message',
      _ => '$newMessageCount new messages',
    };

    return Semantics(
      label: 'Go to end',
      value: semanticsValue,
      button: true,
      excludeSemantics: true,
      child: FloatingActionButton.extended(
        key: buttonKey,
        heroTag: null,
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_downward_rounded),
        label: Text(indicatorText, key: countKey),
      ),
    );
  }
}
