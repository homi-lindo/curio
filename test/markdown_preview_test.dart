import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/ui/markdown_preview.dart';

Future<void> _pump(WidgetTester tester, String data) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: MarkdownPreview(data: data)),
      ),
    ),
  );
}

void main() {
  testWidgets('renderiza títulos, parágrafos e ênfase', (tester) async {
    await _pump(
      tester,
      '# Título principal\n\nUm parágrafo com **negrito** e *itálico*.',
    );

    expect(find.text('Título principal', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('negrito', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('renderiza checklist GFM com ícones de caixa', (tester) async {
    await _pump(tester, '- [x] feito\n- [ ] pendente\n');

    expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    expect(find.textContaining('feito', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('pendente', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('renderiza listas ordenadas com numeração', (tester) async {
    await _pump(tester, '1. primeiro\n2. segundo\n');

    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
  });

  testWidgets('renderiza bloco de código e citação', (tester) async {
    await _pump(
      tester,
      '> citação importante\n\n```\nconst codigo = 1;\n```\n',
    );

    expect(
      find.textContaining('citação importante', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('const codigo = 1;'), findsOneWidget);
  });

  testWidgets('conteúdo vazio mostra aviso discreto', (tester) async {
    await _pump(tester, '   ');

    expect(find.text('Nada para visualizar ainda.'), findsOneWidget);
  });

  testWidgets('link é estilizado mas não navega', (tester) async {
    await _pump(tester, 'Veja [o site](https://example.com).');

    expect(find.textContaining('o site', findRichText: true), findsOneWidget);
    // Sem GestureRecognizer de navegação: nada para tocar além do texto.
  });
}
