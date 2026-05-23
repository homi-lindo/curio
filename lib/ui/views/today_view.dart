import 'package:flutter/material.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';

import '../../services/notification_service.dart';
import '../task_view_helpers.dart';
import '../widgets/notification_record_tile.dart';
import '../widgets/page_frame.dart';
import '../widgets/section_header.dart';
import '../widgets/status_pill.dart';
import '../widgets/surface.dart';

final class TodayView extends StatelessWidget {
  const TodayView({
    super.key,
    required this.notes,
    required this.scheduledNotifications,
    required this.activity,
    required this.busy,
    required this.permissionState,
    required this.pendingCount,
    required this.onRequestPermissions,
    required this.onOpenNote,
    required this.onOpenNotification,
    required this.onCreateStandaloneNotification,
  });

  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> scheduledNotifications;
  final List<String> activity;
  final bool busy;
  final NotificationPermissionState permissionState;
  final int pendingCount;
  final VoidCallback onRequestPermissions;
  final ValueChanged<DateTime> onOpenNote;
  final ValueChanged<ScheduledNotificationRecord> onOpenNotification;
  final VoidCallback onCreateStandaloneNotification;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());

    return PageFrame(
      title: 'Hoje',
      subtitle: todayLabel(),
      trailing: StatusPill(
        icon: Icons.notifications_active_outlined,
        label: '$pendingCount pendente(s)',
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final children = <Widget>[
            _TodayDailyPanel(
              notes: notes,
              scheduledNotifications: scheduledNotifications,
              selectedDate: today,
              activity: activity,
              onOpenNote: onOpenNote,
              onOpenNotification: onOpenNotification,
            ),
            _UpcomingNotificationsPanel(
              notes: notes,
              scheduledNotifications: scheduledNotifications,
              busy: busy,
              permissionState: permissionState,
              pendingCount: pendingCount,
              onRequestPermissions: onRequestPermissions,
              onOpenNotification: onOpenNotification,
              onCreateStandaloneNotification: onCreateStandaloneNotification,
            ),
          ];

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 6, child: children[0]),
                const SizedBox(width: 18),
                Expanded(flex: 5, child: children[1]),
              ],
            );
          }

          return Column(
            children: <Widget>[
              children[0],
              const SizedBox(height: 16),
              children[1],
            ],
          );
        },
      ),
    );
  }
}

final class _TodayDailyPanel extends StatelessWidget {
  const _TodayDailyPanel({
    required this.notes,
    required this.scheduledNotifications,
    required this.selectedDate,
    required this.activity,
    required this.onOpenNote,
    required this.onOpenNotification,
  });

  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> scheduledNotifications;
  final DateTime selectedDate;
  final List<String> activity;
  final ValueChanged<DateTime> onOpenNote;
  final ValueChanged<ScheduledNotificationRecord> onOpenNotification;

  @override
  Widget build(BuildContext context) {
    final todaysNotes = dailyNotesForDate(notes, selectedDate);
    final todaysNotifications = notificationsForDate(
      scheduledNotifications,
      selectedDate,
    );

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(
            icon: Icons.today_outlined,
            title: 'Notas e notificações do dia',
          ),
          const SizedBox(height: 14),
          Text(
            formatLocalDate(selectedDate),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          SectionHeader(
            icon: Icons.article_outlined,
            title: 'Notas do dia',
            action: TextButton.icon(
              onPressed: () => onOpenNote(selectedDate),
              icon: const Icon(Icons.open_in_new_outlined),
              label: const Text('Abrir em Notas'),
            ),
          ),
          const SizedBox(height: 8),
          if (todaysNotes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Nenhuma nota do dia ainda.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (final note in todaysNotes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.article_outlined),
                title: Text(note.title),
                subtitle: Text(
                  note.body.trim().isEmpty
                      ? formatLocalDateTime(note.updatedAtUtc)
                      : note.body.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onOpenNote(selectedDate),
              ),
          const Divider(height: 28),
          const SectionHeader(
            icon: Icons.notifications_none_outlined,
            title: 'Notificações do dia',
          ),
          const SizedBox(height: 8),
          if (todaysNotifications.isEmpty)
            Text(
              'Nenhuma notificação neste dia.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final record in todaysNotifications.take(8))
              NotificationRecordTile(
                record: record,
                title: notificationRecordTitle(record, notes),
                onTap: () => onOpenNotification(record),
              ),
          if (activity.isNotEmpty) ...<Widget>[
            const Divider(height: 28),
            const SectionHeader(icon: Icons.history_outlined, title: 'Log'),
            const SizedBox(height: 8),
            for (final item in activity.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(item, style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ],
      ),
    );
  }
}

final class _UpcomingNotificationsPanel extends StatelessWidget {
  const _UpcomingNotificationsPanel({
    required this.notes,
    required this.scheduledNotifications,
    required this.busy,
    required this.permissionState,
    required this.pendingCount,
    required this.onRequestPermissions,
    required this.onOpenNotification,
    required this.onCreateStandaloneNotification,
  });

  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> scheduledNotifications;
  final bool busy;
  final NotificationPermissionState permissionState;
  final int pendingCount;
  final VoidCallback onRequestPermissions;
  final ValueChanged<ScheduledNotificationRecord> onOpenNotification;
  final VoidCallback onCreateStandaloneNotification;

  @override
  Widget build(BuildContext context) {
    final upcoming = upcomingNotifications(scheduledNotifications);

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            icon: Icons.bolt_outlined,
            title: 'Próximas notificações',
            action: StatusPill(
              icon: Icons.notifications_active_outlined,
              label: '$pendingCount pendente(s)',
            ),
          ),
          const SizedBox(height: 14),
          Text(
            permissionState.label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: busy ? null : onRequestPermissions,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Permissões'),
              ),
              FilledButton.tonalIcon(
                onPressed: busy ? null : onCreateStandaloneNotification,
                icon: const Icon(Icons.notification_add_outlined),
                label: const Text('Nova notificação'),
              ),
            ],
          ),
          if (upcoming.isEmpty) ...<Widget>[
            const SizedBox(height: 18),
            Text(
              'Nenhuma notificação futura gravada.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...<Widget>[
            const Divider(height: 28),
            for (final record in upcoming.take(10))
              NotificationRecordTile(
                record: record,
                title: notificationRecordTitle(record, notes),
                onTap: () => onOpenNotification(record),
              ),
          ],
        ],
      ),
    );
  }
}
