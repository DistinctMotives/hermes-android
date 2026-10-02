import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Splits raw markdown into text segments and fenced code blocks.
///
/// Returns a list of [String] (regular markdown, rendered by MarkdownBody)
/// and [MarkdownCodeBlock] (rendered with copy/wrap controls). The fenced
/// blocks are removed from the surrounding markdown so they render once,
/// with full fidelity, instead of relying on flutter_markdown's `pre`
/// builder (which leaves its internal inline state unbalanced).
List<Object> splitMarkdownCodeBlocks(String content) {
  final result = <Object>[];
  final regex = RegExp(
    r'```([\w+-]*)[ \t]*\r?\n([\s\S]*?)```',
    multiLine: true,
  );
  var cursor = 0;

  for (final match in regex.allMatches(content)) {
    if (match.start > cursor) {
      result.add(content.substring(cursor, match.start));
    }
    result.add(
      MarkdownCodeBlock(
        code: match.group(2)!,
        language: match.group(1)?.isEmpty ?? true ? null : match.group(1),
      ),
    );
    cursor = match.end;
  }

  if (cursor < content.length) {
    result.add(content.substring(cursor));
  }
  return result;
}

/// Renders a fenced code block with a language label, copy, and wrap controls.
class MarkdownCodeBlock extends StatefulWidget {
  final String code;
  final String? language;

  const MarkdownCodeBlock({super.key, required this.code, this.language});

  @override
  State<MarkdownCodeBlock> createState() => _MarkdownCodeBlockState();
}

class _MarkdownCodeBlockState extends State<MarkdownCodeBlock> {
  bool _wrap = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Code copied'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF141414)
        : const Color(0xFFF2F2F2);
    final header = isDark ? const Color(0xFF232323) : const Color(0xFFE4E4E4);
    final foreground = isDark ? Colors.white70 : Colors.black87;

    final body = _wrap
        ? SelectableText(
            widget.code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.45,
              color: foreground,
            ),
          )
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              widget.code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.45,
                color: foreground,
              ),
            ),
          );

    return Container(
      key: const Key('markdown-code-block'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            color: header,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.language ?? 'code',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_wrap)
                  Tooltip(
                    message: 'Scroll horizontally',
                    child: IconButton(
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      onPressed: () => setState(() => _wrap = false),
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                    ),
                  ),
                Tooltip(
                  message: 'Wrap lines',
                  child: IconButton(
                    icon: const Icon(Icons.wrap_text, size: 18),
                    onPressed: () => setState(() => _wrap = true),
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Copy code',
                  child: IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    onPressed: _copy,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: body,
          ),
        ],
      ),
    );
  }
}
