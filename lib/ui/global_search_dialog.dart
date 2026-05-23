import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lume_core/domain/app_snapshot.dart';

import 'task_view_helpers.dart';

final class GlobalSearchDialog extends StatefulWidget {
  const GlobalSearchDialog({super.key, required this.snapshot});

  final AppSnapshot snapshot;

  @override
  State<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

final class _GlobalSearchDialogState extends State<GlobalSearchDialog> {
  late final TextEditingController _controller;
  List<GlobalSearchResult> _results = const <GlobalSearchResult>[];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = searchSnapshotText(widget.snapshot, value);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Row(
        children: <Widget>[
          Icon(Icons.search_outlined),
          SizedBox(width: 10),
          Text('Pesquisa global'),
        ],
      ),
      content: SizedBox(
        width: min(MediaQuery.of(context).size.width * 0.86, 680),
        height: min(MediaQuery.of(context).size.height * 0.70, 560),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.manage_search_outlined),
                labelText: 'Buscar',
                hintText: 'Notas e notificações',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                query.isEmpty
                    ? 'Notas e notificações'
                    : '${_results.length} resultado(s)',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _SearchResultsBody(query: query, results: _results),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

final class _SearchResultsBody extends StatelessWidget {
  const _SearchResultsBody({required this.query, required this.results});

  final String query;
  final List<GlobalSearchResult> results;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return const Center(child: Text('Digite para pesquisar.'));
    }

    if (results.isEmpty) {
      return const Center(child: Text('Nada encontrado.'));
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final result = results[index];
        final isNotification =
            result.kind == GlobalSearchResultKind.notification;
        final preview = result.preview;

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            isNotification
                ? Icons.notifications_none_outlined
                : Icons.sticky_note_2_outlined,
          ),
          title: Text(
            result.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            preview.isEmpty ? result.subtitle : '${result.subtitle}\n$preview',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.of(context).pop(result),
        );
      },
    );
  }
}
