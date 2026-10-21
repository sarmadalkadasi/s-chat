import 'package:flutter/material.dart';
import 'package:s_chat/widgets/text_formatter/formatted_text_renderer.dart';

class ExpandableFormattedText extends StatefulWidget {
  const ExpandableFormattedText({
    super.key,
    required this.text,
    this.isMe = false,
    this.previewCharacters = 500,
  }) : assert(previewCharacters > 0);

  final String text;
  final bool isMe;
  final int previewCharacters;

  @override
  State<ExpandableFormattedText> createState() =>
      _ExpandableFormattedTextState();
}

class _ExpandableFormattedTextState
    extends State<ExpandableFormattedText> {
  bool _expanded = false;
  static const int _maxPreviewLines = 8;

  String _makePreview(String source) {
    final runes = source.runes.toList();
    var preview = source;

    // Limit the number of characters.
    if (runes.length > widget.previewCharacters) {
      var cut = widget.previewCharacters;
      final minimumCut = (cut * 0.8).floor();

      for (var i = cut - 1; i >= minimumCut; i--) {
        if ([32, 9, 10, 13].contains(runes[i])) {
          cut = i;
          break;
        }
      }

      preview = String.fromCharCodes(
        runes.take(cut),
      ).trimRight();
    }

    // Limit explicit newline-separated lines as well.
    final lines = preview.split('\n');

    if (lines.length > _maxPreviewLines) {
      preview = lines.take(_maxPreviewLines).join('\n');
    }

    if (preview == source) {
      return source;
    }

    return _closeFormatting(preview);
  }

  // Close formatting markers that were opened before the preview cutoff.
  // This prevents truncated text from displaying unfinished formatting.
  String _closeFormatting(String text) {
    final stack = <String>[];
    var position = 0;
    var inCode = false;

    const markers = ['**', '~~', '||', '^'];

    while (position < text.length) {
      if (text.startsWith('```', position)) {
        if (inCode) {
          inCode = false;
          if (stack.isNotEmpty && stack.last == '```') {
            stack.removeLast();
          }
        } else {
          inCode = true;
          stack.add('```');
        }

        position += 3;
        continue;
      }

      // Formatting inside code is literal text.
      if (inCode) {
        position++;
        continue;
      }

      String? foundMarker;

      for (final marker in markers) {
        if (text.startsWith(marker, position)) {
          foundMarker = marker;
          break;
        }
      }

      if (foundMarker == null) {
        position++;
        continue;
      }

      if (stack.isNotEmpty && stack.last == foundMarker) {
        stack.removeLast();
      } else {
        stack.add(foundMarker);
      }

      position += foundMarker.length;
    }

    return '$text…${stack.reversed.join()}';
  }

  @override
  Widget build(BuildContext context) {
    final needsExpansion =
        widget.text.runes.length > widget.previewCharacters;

    final displayedText = _expanded
        ? widget.text
        : _makePreview(widget.text);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormattedTextRenderer(
          text: displayedText,
          isMe: widget.isMe,
        ),

        if (needsExpansion)
          Align(
            alignment: widget.isMe
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                setState(() {
                  _expanded = !_expanded;
                });
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.only(top: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                _expanded ? '...Show less' : '...Read more',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: widget.isMe
                          ? Theme.of(context).colorScheme.onPrimary.withAlpha(200)
                          : Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}
