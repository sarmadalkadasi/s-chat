import 'package:flutter/material.dart';

class BiDiTextEditingController extends TextEditingController {
  BiDiTextEditingController({super.text});

  static const String _lrm = '\u200E'; // Left-to-Right Mark
  static const String _rlm = '\u200F'; // Right-to-Left Mark

  /// Clean text without invisible BiDi markers for sending/saving
  String get cleanText {
    return text.replaceAll(_lrm, '').replaceAll(_rlm, '').trim();
  }

  @override
  set value(TextEditingValue newValue) {
    final processed = _applyBiDiMarkers(newValue);
    super.value = processed;
  }

  TextEditingValue _applyBiDiMarkers(TextEditingValue newValue) {
    final rawText = newValue.text;
    if (rawText.isEmpty) return newValue;

    final lines = rawText.split('\n');
    final StringBuffer sb = StringBuffer();

    for (int i = 0; i < lines.length; i++) {
      var line = lines[i];

      // Strip existing leading markers
      while (line.startsWith(_lrm) || line.startsWith(_rlm)) {
        line = line.substring(1);
      }

      if (line.isNotEmpty) {
        final isRtl = TextFormattingUtils.isRtlLine(line);
        final marker = isRtl ? _rlm : _lrm;
        sb.write('$marker$line');
      } else {
        sb.write(line);
      }

      if (i < lines.length - 1) {
        sb.write('\n');
      }
    }

    final newText = sb.toString();
    if (newText == newValue.text) return newValue;

    final diff = newText.length - newValue.text.length;
    final selection = newValue.selection;
    final newOffset = (selection.baseOffset + diff).clamp(0, newText.length);

    return TextEditingValue(
      text: newText,
      selection: selection.isCollapsed
          ? TextSelection.collapsed(offset: newOffset)
          : TextSelection(
              baseOffset: (selection.baseOffset + diff).clamp(0, newText.length),
              extentOffset: (selection.extentOffset + diff).clamp(0, newText.length),
            ),
      composing: newValue.composing,
    );
  }
}

class TextFormattingUtils {
  TextFormattingUtils._();

  /// Strong RTL character ranges (Arabic, Persian, Hebrew, Urdu, etc.)
  static final RegExp _rtlRegExp = RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF\u0590-\u05FF]',
  );

  /// Checks if the first strong character in a line is RTL
  static bool isRtlLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;

    for (int i = 0; i < trimmed.length; i++) {
      final char = trimmed[i];
      // Skip numbers, spaces, and punctuation symbols
      if (RegExp(r'[0-9\s\p{P}\p{S}]', unicode: true).hasMatch(char)) {
        continue;
      }
      return _rtlRegExp.hasMatch(char);
    }
    return _rtlRegExp.hasMatch(trimmed);
  }

  /// Wraps selected text in a TextEditingController with formatting symbols
  static void formatSelectedText(TextEditingController controller, String symbol) {
    final text = controller.text;
    final selection = controller.selection;

    if (selection.isCollapsed || !selection.isValid) return;

    final selectedText = selection.textInside(text);
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      '$symbol$selectedText$symbol',
    );

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + (symbol.length * 2) + selectedText.length,
      ),
    );
  }

  /// Builds context menu formatting items (Bold, Italic, Spoiler, Strikethrough, Code)
  static Widget buildFormattingContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
    TextEditingController controller,
  ) {
    final List<ContextMenuButtonItem> buttonItems =
        editableTextState.contextMenuButtonItems;

    final List<ContextMenuButtonItem> customButtons = [
      ContextMenuButtonItem(
        label: 'Bold',
        onPressed: () {
          formatSelectedText(controller, '**');
          ContextMenuController.removeAny();
        },
      ),
      ContextMenuButtonItem(
        label: 'Italic',
        onPressed: () {
          formatSelectedText(controller, '^^');
          ContextMenuController.removeAny();
        },
      ),
      ContextMenuButtonItem(
        label: 'Spoiler',
        onPressed: () {
          formatSelectedText(controller, '||');
          ContextMenuController.removeAny();
        },
      ),
      ContextMenuButtonItem(
        label: 'Strikethrough',
        onPressed: () {
          formatSelectedText(controller, '~~');
          ContextMenuController.removeAny();
        },
      ),
      ContextMenuButtonItem(
        label: 'Mono',
        onPressed: () {
          formatSelectedText(controller, '`');
          ContextMenuController.removeAny();
        },
      ),
    ];

    final List<ContextMenuButtonItem> totalButtons = [
      ...buttonItems,
      ...customButtons,
    ];

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: totalButtons,
    );
  }
}
