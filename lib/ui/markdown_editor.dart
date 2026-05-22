import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum MarkdownFormatAction {
  heading,
  bold,
  italic,
  bulletList,
  checklist,
  quote,
  code,
  link,
}

extension MarkdownFormatActionLabel on MarkdownFormatAction {
  String get tooltip {
    return switch (this) {
      MarkdownFormatAction.heading => 'Título',
      MarkdownFormatAction.bold => 'Negrito',
      MarkdownFormatAction.italic => 'Itálico',
      MarkdownFormatAction.bulletList => 'Lista',
      MarkdownFormatAction.checklist => 'Checklist',
      MarkdownFormatAction.quote => 'Citação',
      MarkdownFormatAction.code => 'Código',
      MarkdownFormatAction.link => 'Link',
    };
  }

  String get shortcutLabel {
    return switch (this) {
      MarkdownFormatAction.heading => 'Ctrl+Alt+1',
      MarkdownFormatAction.bold => 'Ctrl+B',
      MarkdownFormatAction.italic => 'Ctrl+I',
      MarkdownFormatAction.bulletList => 'Ctrl+Shift+8',
      MarkdownFormatAction.checklist => 'Ctrl+Shift+9',
      MarkdownFormatAction.quote => 'Ctrl+Shift+>',
      MarkdownFormatAction.code => 'Ctrl+`',
      MarkdownFormatAction.link => 'Ctrl+K',
    };
  }

  String get tooltipWithShortcut => '$tooltip ($shortcutLabel)';

  IconData get icon {
    return switch (this) {
      MarkdownFormatAction.heading => Icons.title_outlined,
      MarkdownFormatAction.bold => Icons.format_bold,
      MarkdownFormatAction.italic => Icons.format_italic,
      MarkdownFormatAction.bulletList => Icons.format_list_bulleted,
      MarkdownFormatAction.checklist => Icons.check_box_outlined,
      MarkdownFormatAction.quote => Icons.format_quote,
      MarkdownFormatAction.code => Icons.code_outlined,
      MarkdownFormatAction.link => Icons.link_outlined,
    };
  }
}

@visibleForTesting
const Map<ShortcutActivator, MarkdownFormatAction> markdownKeyboardShortcuts =
    <ShortcutActivator, MarkdownFormatAction>{
      SingleActivator(LogicalKeyboardKey.digit1, control: true, alt: true):
          MarkdownFormatAction.heading,
      SingleActivator(LogicalKeyboardKey.keyB, control: true):
          MarkdownFormatAction.bold,
      SingleActivator(LogicalKeyboardKey.keyI, control: true):
          MarkdownFormatAction.italic,
      SingleActivator(LogicalKeyboardKey.digit8, control: true, shift: true):
          MarkdownFormatAction.bulletList,
      SingleActivator(LogicalKeyboardKey.digit9, control: true, shift: true):
          MarkdownFormatAction.checklist,
      SingleActivator(LogicalKeyboardKey.period, control: true, shift: true):
          MarkdownFormatAction.quote,
      SingleActivator(LogicalKeyboardKey.backquote, control: true):
          MarkdownFormatAction.code,
      SingleActivator(LogicalKeyboardKey.keyK, control: true):
          MarkdownFormatAction.link,
    };

final class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({
    super.key,
    required this.enabled,
    required this.onAction,
  });

  final bool enabled;
  final ValueChanged<MarkdownFormatAction> onAction;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final action in MarkdownFormatAction.values)
          IconButton(
            onPressed: enabled ? () => onAction(action) : null,
            icon: Icon(action.icon),
            tooltip: action.tooltipWithShortcut,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

final class MarkdownShortcuts extends StatelessWidget {
  const MarkdownShortcuts({
    super.key,
    required this.enabled,
    required this.controller,
    required this.onChanged,
    required this.child,
  });

  final bool enabled;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: enabled
          ? <ShortcutActivator, VoidCallback>{
              for (final entry in markdownKeyboardShortcuts.entries)
                entry.key: () => applyMarkdownFormat(
                  controller: controller,
                  onChanged: onChanged,
                  action: entry.value,
                ),
            }
          : const <ShortcutActivator, VoidCallback>{},
      child: child,
    );
  }
}

void applyMarkdownFormat({
  required TextEditingController controller,
  required ValueChanged<String> onChanged,
  required MarkdownFormatAction action,
}) {
  final next = formatMarkdownText(controller.value, action);
  controller.value = next;
  onChanged(next.text);
}

@visibleForTesting
TextEditingValue formatMarkdownText(
  TextEditingValue value,
  MarkdownFormatAction action,
) {
  return switch (action) {
    MarkdownFormatAction.heading => _prefixSelectedLines(value, '## '),
    MarkdownFormatAction.bulletList => _prefixSelectedLines(value, '- '),
    MarkdownFormatAction.checklist => _prefixSelectedLines(value, '- [ ] '),
    MarkdownFormatAction.quote => _prefixSelectedLines(value, '> '),
    MarkdownFormatAction.bold => _wrapSelection(value, '**', '**', 'texto'),
    MarkdownFormatAction.italic => _wrapSelection(value, '_', '_', 'texto'),
    MarkdownFormatAction.code => _wrapSelection(value, '`', '`', 'codigo'),
    MarkdownFormatAction.link => _wrapSelection(value, '[', '](url)', 'link'),
  };
}

TextEditingValue _wrapSelection(
  TextEditingValue value,
  String before,
  String after,
  String placeholder,
) {
  final text = value.text;
  final selection = _normalizedSelection(value);
  final selected = text.substring(selection.start, selection.end);
  final content = selected.isEmpty ? placeholder : selected;
  final replacement = '$before$content$after';
  final nextText = text.replaceRange(
    selection.start,
    selection.end,
    replacement,
  );
  final innerStart = selection.start + before.length;
  final innerEnd = innerStart + content.length;

  return value.copyWith(
    text: nextText,
    selection: TextSelection(baseOffset: innerStart, extentOffset: innerEnd),
    composing: TextRange.empty,
  );
}

TextEditingValue _prefixSelectedLines(TextEditingValue value, String prefix) {
  final text = value.text;
  final selection = _normalizedSelection(value);
  final lineStart = text.lastIndexOf('\n', max(0, selection.start - 1)) + 1;
  final nextLineBreak = text.indexOf('\n', selection.end);
  final lineEnd = nextLineBreak == -1 ? text.length : nextLineBreak;
  final block = text.substring(lineStart, lineEnd);
  final prefixed = block
      .split('\n')
      .map((line) => line.startsWith(prefix) ? line : '$prefix$line')
      .join('\n');
  final nextText = text.replaceRange(lineStart, lineEnd, prefixed);
  final delta = prefixed.length - block.length;

  return value.copyWith(
    text: nextText,
    selection: TextSelection(
      baseOffset: selection.start + prefix.length,
      extentOffset: selection.end + delta,
    ),
    composing: TextRange.empty,
  );
}

TextSelection _normalizedSelection(TextEditingValue value) {
  final textLength = value.text.length;
  final selection = value.selection;
  if (!selection.isValid) {
    return TextSelection.collapsed(offset: textLength);
  }

  final start = min(selection.start, selection.end).clamp(0, textLength);
  final end = max(selection.start, selection.end).clamp(0, textLength);
  return TextSelection(baseOffset: start, extentOffset: end);
}
