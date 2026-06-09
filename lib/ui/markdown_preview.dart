import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

/// Visualização do subset de Markdown que o editor produz — títulos, ênfase,
/// listas (inclusive checklist GFM), citação, código e links — renderizada a
/// partir da AST do `package:markdown` (pacote Dart de primeira parte; o
/// flutter_markdown foi descontinuado). Construções fora do subset caem para
/// o texto bruto do nó, então nada some do preview.
///
/// Links são estilizados mas não abrem URL: o preview nunca dispara navegação
/// por conta própria.
final class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    if (data.trim().isEmpty) {
      return Text(
        'Nada para visualizar ainda.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );
    final nodes = document.parseLines(data.split('\n'));

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _blocks(context, nodes),
      ),
    );
  }
}

List<Widget> _blocks(BuildContext context, List<md.Node> nodes) {
  final theme = Theme.of(context);
  final widgets = <Widget>[];

  for (final node in nodes) {
    if (node is md.Text) {
      final text = node.text.trim();
      if (text.isNotEmpty) {
        widgets.add(_paragraph(context, TextSpan(text: text)));
      }
      continue;
    }
    if (node is! md.Element) {
      continue;
    }

    switch (node.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final style = switch (node.tag) {
          'h1' => theme.textTheme.headlineSmall,
          'h2' => theme.textTheme.titleLarge,
          'h3' => theme.textTheme.titleMedium,
          _ => theme.textTheme.titleSmall,
        }?.copyWith(fontWeight: FontWeight.w800);
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text.rich(
              _inline(context, node.children ?? const <md.Node>[]),
              style: style,
            ),
          ),
        );
      case 'p':
        widgets.add(
          _paragraph(
            context,
            _inline(context, node.children ?? const <md.Node>[]),
          ),
        );
      case 'ul' || 'ol':
        widgets.add(_list(context, node));
      case 'blockquote':
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: theme.colorScheme.primary, width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _blocks(context, node.children ?? const <md.Node>[]),
              ),
            ),
          ),
        );
      case 'pre':
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                node.textContent.trimRight(),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
          ),
        );
      case 'hr':
        widgets.add(const Divider(height: 20));
      default:
        widgets.add(_paragraph(context, TextSpan(text: node.textContent)));
    }
  }

  return widgets;
}

Widget _paragraph(BuildContext context, InlineSpan span) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Text.rich(
      span is TextSpan ? span : TextSpan(children: <InlineSpan>[span]),
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(height: 1.45, fontSize: 15),
    ),
  );
}

Widget _list(BuildContext context, md.Element list) {
  final ordered = list.tag == 'ol';
  final items = (list.children ?? const <md.Node>[])
      .whereType<md.Element>()
      .where((child) => child.tag == 'li')
      .toList();

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var index = 0; index < items.length; index++)
          _listItem(context, items[index], ordered ? index + 1 : null),
      ],
    ),
  );
}

Widget _listItem(BuildContext context, md.Element item, int? ordinal) {
  final children = item.children ?? const <md.Node>[];
  // Checklist GFM: o primeiro filho do li é um <input type="checkbox">.
  final checkbox = children.whereType<md.Element>().firstOrNull;
  final isTask = checkbox != null && checkbox.tag == 'input';
  final checked = isTask && checkbox.attributes['checked'] != null;
  final contentNodes = isTask ? children.skip(1).toList() : children;

  final inlineRun = <md.Node>[];
  final blockWidgets = <Widget>[];
  for (final node in contentNodes) {
    if (node is md.Element && _blockTags.contains(node.tag)) {
      if (inlineRun.isNotEmpty) {
        blockWidgets.add(
          _paragraph(context, _inline(context, List.of(inlineRun))),
        );
        inlineRun.clear();
      }
      blockWidgets.addAll(_blocks(context, <md.Node>[node]));
    } else {
      inlineRun.add(node);
    }
  }
  if (inlineRun.isNotEmpty) {
    blockWidgets.add(_paragraph(context, _inline(context, inlineRun)));
  }

  final theme = Theme.of(context);
  final marker = isTask
      ? Padding(
          padding: const EdgeInsets.only(top: 5, right: 6),
          child: Icon(
            checked
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank,
            size: 17,
            color: theme.colorScheme.primary,
          ),
        )
      : Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(
            ordinal == null ? '•' : '$ordinal.',
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.45,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

  return Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        marker,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: blockWidgets,
          ),
        ),
      ],
    ),
  );
}

const Set<String> _blockTags = <String>{
  'p',
  'ul',
  'ol',
  'blockquote',
  'pre',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
};

TextSpan _inline(BuildContext context, List<md.Node> nodes) {
  final theme = Theme.of(context);
  final spans = <InlineSpan>[];

  void walk(md.Node node, TextStyle style) {
    if (node is md.Text) {
      spans.add(TextSpan(text: node.text, style: style));
      return;
    }
    if (node is! md.Element) {
      return;
    }
    switch (node.tag) {
      case 'strong':
        for (final child in node.children ?? const <md.Node>[]) {
          walk(child, style.copyWith(fontWeight: FontWeight.w700));
        }
      case 'em':
        for (final child in node.children ?? const <md.Node>[]) {
          walk(child, style.copyWith(fontStyle: FontStyle.italic));
        }
      case 'del':
        for (final child in node.children ?? const <md.Node>[]) {
          walk(child, style.copyWith(decoration: TextDecoration.lineThrough));
        }
      case 'code':
        spans.add(
          TextSpan(
            text: node.textContent,
            style: style.copyWith(
              fontFamily: 'monospace',
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        );
      case 'a':
        final linkStyle = style.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        );
        for (final child in node.children ?? const <md.Node>[]) {
          walk(child, linkStyle);
        }
      case 'br':
        spans.add(TextSpan(text: '\n', style: style));
      case 'input':
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(
              node.attributes['checked'] != null
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          ),
        );
      default:
        for (final child in node.children ?? const <md.Node>[]) {
          walk(child, style);
        }
    }
  }

  final base = DefaultTextStyle.of(context).style;
  for (final node in nodes) {
    walk(node, base);
  }
  return TextSpan(children: spans);
}
