import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/ui/markdown_editor.dart';

void main() {
  test('wraps selected text with inline markdown', () {
    const value = TextEditingValue(
      text: 'texto importante',
      selection: TextSelection(baseOffset: 6, extentOffset: 16),
    );

    final next = formatMarkdownText(value, MarkdownFormatAction.bold);

    expect(next.text, 'texto **importante**');
    expect(next.selection.textInside(next.text), 'importante');
  });

  test('creates markdown links with placeholder when selection is empty', () {
    const value = TextEditingValue(
      text: 'ver ',
      selection: TextSelection.collapsed(offset: 4),
    );

    final next = formatMarkdownText(value, MarkdownFormatAction.link);

    expect(next.text, 'ver [link](url)');
    expect(next.selection.textInside(next.text), 'link');
  });

  test('prefixes selected lines for markdown lists', () {
    const value = TextEditingValue(
      text: 'um\ndois',
      selection: TextSelection(baseOffset: 0, extentOffset: 7),
    );

    final next = formatMarkdownText(value, MarkdownFormatAction.checklist);

    expect(next.text, '- [ ] um\n- [ ] dois');
  });

  test('keyboard shortcuts cover every markdown action', () {
    final actions = markdownKeyboardShortcuts.values.toSet();

    expect(actions, containsAll(MarkdownFormatAction.values));
    expect(MarkdownFormatAction.bold.shortcutLabel, 'Ctrl+B');
    expect(
      MarkdownFormatAction.bulletList.tooltipWithShortcut,
      'Lista (Ctrl+Shift+8)',
    );
  });

  testWidgets('keyboard shortcuts format focused editor text', (tester) async {
    final controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'texto',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      ),
    );
    final focusNode = FocusNode();
    var changed = '';
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownShortcuts(
            enabled: true,
            controller: controller,
            onChanged: (value) => changed = value,
            child: TextField(controller: controller, focusNode: focusNode),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(controller.text, '**texto**');
    expect(changed, '**texto**');
  });

  testWidgets('keyboard shortcuts stay inert when editor is disabled', (
    tester,
  ) async {
    final controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'texto',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      ),
    );
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownShortcuts(
            enabled: false,
            controller: controller,
            onChanged: (_) {},
            child: TextField(controller: controller, focusNode: focusNode),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(controller.text, 'texto');
  });
}
