import 'package:flutter/material.dart';

final class TimelineRow extends StatelessWidget {
  const TimelineRow({
    super.key,
    required this.time,
    required this.title,
    this.subtitle,
    required this.tone,
    this.onTap,
    this.actionTooltip = 'Editar',
  });

  final String time;
  final String title;
  final String? subtitle;
  final Color tone;
  final VoidCallback? onTap;
  final String actionTooltip;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: <Widget>[
        SizedBox(
          width: 64,
          child: Text(
            time,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (onTap != null) ...<Widget>[
          const SizedBox(width: 8),
          IconButton(
            onPressed: onTap,
            icon: const Icon(Icons.edit_outlined),
            tooltip: actionTooltip,
          ),
        ],
      ],
    );

    final tap = onTap;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: tap == null
          ? row
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: tap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: row,
                ),
              ),
            ),
    );
  }
}
