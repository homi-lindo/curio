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
}
