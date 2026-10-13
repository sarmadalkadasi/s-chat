import 'package:flutter/material.dart';
import 'package:s_chat/utils/text_formatting_utils.dart';

class FormattedTextRenderer extends StatefulWidget {
  const FormattedTextRenderer({
    super.key,
    required this.text,
    this.style,
    this.isMe = false,
  });

  final String text;
  final TextStyle? style;
  final bool isMe;

  @override
  State<FormattedTextRenderer> createState() =>
      _FormattedTextRendererState();
}

class _FormattedTextRendererState extends State<FormattedTextRenderer> {
  final Set<String> _revealedSpoilers = {};

  void _toggleSpoiler(String id) {
    setState(() {
      if (!_revealedSpoilers.add(id)) {
        _revealedSpoilers.remove(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = widget.style ??
        TextStyle(
          fontSize: 15,
          height: 1.25,
          color: widget.isMe
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSecondaryContainer,
        );

    final lines = widget.text.split('\n');
    var globalSpoilerCounter = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final lineIndex in Iterable<int>.generate(lines.length))
          Builder(
            builder: (context) {
              final line = lines[lineIndex];
              final isRtl = TextFormattingUtils.isRtlLine(line);
              final spoilerStart = globalSpoilerCounter;

              globalSpoilerCounter += _countSpoilers(line);

              final spans = _parseLineSpans(
                line,
                defaultStyle,
                lineIndex,
                spoilerStart,
              );

              return Directionality(
                textDirection:
                isRtl ? TextDirection.rtl : TextDirection.ltr,
                child: SizedBox(
                  width: double.infinity,
                  child: Text.rich(
                    TextSpan(
                      style: defaultStyle,
                      children: spans,
                    ),
                    textAlign:
                    isRtl ? TextAlign.right : TextAlign.left,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  int _countSpoilers(String line) {
    return RegExp(r'\|\|.*?\|\|').allMatches(line).length;
  }


  List<InlineSpan> _parseLineSpans(
      String line,
      TextStyle baseStyle,
      int lineIndex,
      int spoilerStartIndex,
      ) {
    var spoilerIndex = spoilerStartIndex;

    return _parseInline(
      line,
      baseStyle,
      lineIndex,
          () => spoilerIndex++,
    );
  }

  List<InlineSpan> _parseInline(
      String text,
      TextStyle style,
      int lineIndex,
      int Function() nextSpoilerIndex,
      ) {
    final spans = <InlineSpan>[];
    var position = 0;

    // Check longer markers before shorter ones.
    const markers = ['**', '~~', '||', '`', '^^'];

    while (position < text.length) {
      String? marker;
      var markerPosition = text.length;

      // Find the next formatting marker.
      for (final candidate in markers) {
        final index = text.indexOf(candidate, position);

        if (index != -1 && index < markerPosition) {
          marker = candidate;
          markerPosition = index;
        }
      }

      // No more formatting markers.
      if (marker == null) {
        spans.add(TextSpan(text: text.substring(position)));
        break;
      }

      // Preserve ordinary text before the marker.
      if (markerPosition > position) {
        spans.add(
          TextSpan(
            text: text.substring(position, markerPosition),
          ),
        );
      }

      final contentStart = markerPosition + marker.length;

      // Find the matching closing marker.
      final closingPosition = text.indexOf(marker, contentStart);

      // If unmatched, preserve the marker as literal text.
      if (closingPosition == -1) {
        spans.add(TextSpan(text: marker));
        position = contentStart;
        continue;
      }

      final content = text.substring(
        contentStart,
        closingPosition,
      );

      final contentStyle = switch (marker) {
        '**' => style.copyWith(
          fontWeight: FontWeight.bold,
        ),
        '^^' => style.copyWith(
          fontStyle: FontStyle.italic,
        ),
        '~~' => style.copyWith(
          decoration: TextDecoration.lineThrough,
        ),
        '`' => style.copyWith(
          fontFamily: 'monospace',
          backgroundColor: widget.isMe
              ? Colors.black26
              : Colors.grey.shade300,
        ),
        _ => style,
      };

      if (marker == '`') {
        // Code content is literal; do not parse its inner markers.
        spans.add(
          TextSpan(
            text: content,
            style: contentStyle,
          ),
        );
      } else if (marker == '||') {
        final id = '$lineIndex:${nextSpoilerIndex()}';
        final isRevealed = _revealedSpoilers.contains(id);

        // Parse the spoiler's content recursively, preserving styles.
        final spoilerStyle = style.copyWith(
          color: isRevealed
              ? style.color
              : Colors.transparent,
        );

        final spoilerSpans = _parseInline(
          content,
          spoilerStyle,
          lineIndex,
          nextSpoilerIndex,
        );

        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: () => _toggleSpoiler(id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: isRevealed
                      ? Colors.transparent
                      : widget.isMe
                      ? Colors.white30
                      : Colors.grey.shade600,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text.rich(
                  TextSpan(
                    style: spoilerStyle,
                    children: spoilerSpans,
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        // Recursively parse nested formatting.
        final nestedSpans = _parseInline(
          content,
          contentStyle,
          lineIndex,
          nextSpoilerIndex,
        );

        spans.add(
          TextSpan(
            style: contentStyle,
            children: nestedSpans,
          ),
        );
      }

      position = closingPosition + marker.length;
    }

    return spans;
  }

}