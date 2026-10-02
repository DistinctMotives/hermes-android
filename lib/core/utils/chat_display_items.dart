import '../models/gateway_activity.dart';
import '../models/gateway_insight.dart';
import 'message_content.dart';

/// Assistant reasoning rendered as its own collapsible item in the chat list.
class ChatReasoningItem {
  final String text;
  final bool initiallyExpanded;

  const ChatReasoningItem(this.text, this.initiallyExpanded);
}

/// Project a raw Hermes message list into the heterogeneous list the chat
/// screen renders.
///
/// The result mixes four item kinds, in the order the conversation produced
/// them:
///
/// - `Map<String, dynamic>` — a user or assistant bubble, carrying
///   `_display_content` (tool-result blocks stripped) and, for assistant
///   replies, `_retry_prompt` with the user prompt that caused it;
/// - `List<GatewayToolActivity>` — consecutive tool results collapsed into one
///   activity card;
/// - [ChatReasoningItem] — assistant reasoning, emitted before its bubble;
/// - `GatewaySubagentActivity` list and [GatewayNotice] — appended last.
///
/// Tool results are matched positionally against [toolActivities]: stored tool
/// messages consume activities in order, and any activity left over (streamed
/// but not yet persisted by the server) is appended as a trailing card. The
/// caller's [toolActivities] list is never mutated.
List<dynamic> buildChatDisplayItems({
  required List<Map<String, dynamic>> messages,
  List<GatewayToolActivity> toolActivities = const [],
  List<GatewaySubagentActivity> subagentActivities = const [],
  List<GatewayNotice> notices = const [],
  bool verbose = false,
}) {
  final toolQueue = List<GatewayToolActivity>.from(toolActivities);
  final displayItems = <dynamic>[];
  final currentGroup = <GatewayToolActivity>[];
  String? lastUserPrompt;

  void flushToolGroup() {
    if (currentGroup.isEmpty) return;
    displayItems.add(currentGroup.toList());
    currentGroup.clear();
  }

  for (final msg in messages) {
    final rawRole = (msg['role'] as String?) ?? 'assistant';
    final role = rawRole == 'agent' ? 'assistant' : rawRole;
    if (isToolResultMessage(msg)) {
      if (toolQueue.isNotEmpty) currentGroup.add(toolQueue.removeAt(0));
      continue;
    }
    if (role != 'user' && role != 'assistant') continue;

    final content = stripToolResultText(messageContentToText(msg['content']));
    final reasoning = msg['_gateway_reasoning']?.toString() ?? '';
    final hasReasoning = role == 'assistant' && reasoning.trim().isNotEmpty;
    if (content.isEmpty && !hasReasoning) continue;

    flushToolGroup();

    if (hasReasoning) {
      displayItems.add(
        ChatReasoningItem(
          reasoning,
          verbose || msg['_gateway_reasoning_verbose'] == true,
        ),
      );
    }
    if (content.isNotEmpty) {
      if (role == 'user') lastUserPrompt = content;
      displayItems.add({
        ...msg,
        'role': role,
        '_display_content': content,
        if (role == 'assistant' && lastUserPrompt != null)
          '_retry_prompt': lastUserPrompt,
      });
    }
  }
  flushToolGroup();

  // Tools from gateway events that arrived during streaming but were never
  // matched to a stored message — show them as a trailing card.
  if (toolQueue.isNotEmpty) displayItems.add(toolQueue.toList());
  if (subagentActivities.isNotEmpty) {
    displayItems.add(List<GatewaySubagentActivity>.from(subagentActivities));
  }
  displayItems.addAll(notices);

  return displayItems;
}
