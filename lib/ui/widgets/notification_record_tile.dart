import 'package:flutter/material.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';

import '../task_view_helpers.dart';

String notificationRecordTitle(
  ScheduledNotificationRecord record,
  List<NoteItem> notes,
) {
  if (record.title.trim().isNotEmpty) {
    return record.title.trim();
  }

  if (record.ownerType == ReminderOwnerType.note) {
    final note = notes
        .where((candidate) => candidate.id == record.ownerId)
        .firstOrNull;
    return note?.title ?? 'Notificação';
  }

  return 'Notificação';
}

final class NotificationRecordTile extends StatelessWidget {
  const NotificationRecordTile({
    super.key,
    required this.record,
    required this.title,
    required this.onTap,
  });

  final ScheduledNotificationRecord record;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ownerLabel = switch (record.ownerType) {
      ReminderOwnerType.task => 'Notificação',
      ReminderOwnerType.note => 'Nota',
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.alarm_on_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$ownerLabel · ${formatLocalDateTime(record.scheduledForUtc)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new_outlined, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
