import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';
import 'package:timezone/timezone.dart' as tz;

enum TaskFilter { open, today, scheduled, done, all }

const agendaThroughYear = 2035;

enum GlobalSearchResultKind { note, notification }

final class GlobalSearchResult {
  const GlobalSearchResult({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.updatedAtUtc,
    this.task,
    this.note,
    this.notification,
    this.rank = 1,
  });

  final GlobalSearchResultKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String preview;
  final DateTime updatedAtUtc;
  final TaskItem? task;
  final NoteItem? note;
  final ScheduledNotificationRecord? notification;
  final int rank;
}

List<TaskItem> filterTasks(
  List<TaskItem> tasks,
  String query,
  TaskFilter filter,
) {
  final normalizedQuery = query.trim().toLowerCase();
  return tasks.where((task) {
    if (!matchesTaskFilter(task, filter)) {
      return false;
    }
    if (normalizedQuery.isEmpty) {
      return true;
    }
    return task.title.toLowerCase().contains(normalizedQuery) ||
        task.description.toLowerCase().contains(normalizedQuery) ||
        (task.sourceNoteId?.toLowerCase().contains(normalizedQuery) ?? false);
  }).toList();
}

List<GlobalSearchResult> searchSnapshotText(
  AppSnapshot snapshot,
  String query, {
  int limit = 40,
}) {
  final normalizedQuery = normalizeSearchText(query.trim());
  if (normalizedQuery.isEmpty) {
    return const <GlobalSearchResult>[];
  }

  final results = <GlobalSearchResult>[];

  for (final note in snapshot.notes) {
    final title = note.title.trim();
    final body = note.body.trim();
    final haystack = normalizeSearchText('$title\n$body');
    if (!haystack.contains(normalizedQuery)) {
      continue;
    }

    results.add(
      GlobalSearchResult(
        kind: GlobalSearchResultKind.note,
        id: note.id,
        title: title,
        subtitle: 'Nota · ${formatLocalDateTime(note.updatedAtUtc)}',
        preview: _searchPreview(body.isEmpty ? title : body, normalizedQuery),
        updatedAtUtc: note.updatedAtUtc,
        note: note,
        rank: normalizeSearchText(title).contains(normalizedQuery) ? 0 : 1,
      ),
    );
  }

  for (final notification in snapshot.scheduledNotifications) {
    final title = notification.title.trim().isEmpty
        ? 'Notificação'
        : notification.title.trim();
    final body = notification.body.trim();
    final meta =
        'Notificação · ${formatLocalDateTime(notification.scheduledForUtc)}';
    final haystack = normalizeSearchText('$title\n$body\n$meta');
    if (!haystack.contains(normalizedQuery)) {
      continue;
    }

    results.add(
      GlobalSearchResult(
        kind: GlobalSearchResultKind.notification,
        id: notification.id.toString(),
        title: title,
        subtitle: meta,
        preview: _searchPreview(body.isEmpty ? meta : body, normalizedQuery),
        updatedAtUtc: notification.scheduledForUtc,
        notification: notification,
        rank: normalizeSearchText(title).contains(normalizedQuery) ? 0 : 1,
      ),
    );
  }

  results.sort((left, right) {
    final rank = left.rank.compareTo(right.rank);
    if (rank != 0) {
      return rank;
    }
    return right.updatedAtUtc.compareTo(left.updatedAtUtc);
  });

  return results.take(limit).toList();
}

bool matchesTaskFilter(TaskItem task, TaskFilter filter, {DateTime? now}) {
  return switch (filter) {
    TaskFilter.open => !task.isDone,
    TaskFilter.today =>
      task.dueAtUtc != null && isToday(task.dueAtUtc!.toLocal(), now: now),
    TaskFilter.scheduled => task.dueAtUtc != null,
    TaskFilter.done => task.isDone,
    TaskFilter.all => true,
  };
}

String normalizeSearchText(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    buffer.write(_searchDiacritics[character] ?? character);
  }
  return buffer.toString();
}

int compareTasksByAgenda(TaskItem a, TaskItem b) {
  final aDue = a.dueAtUtc;
  final bDue = b.dueAtUtc;
  if (aDue == null && bDue == null) {
    return b.updatedAtUtc.compareTo(a.updatedAtUtc);
  }
  if (aDue == null) {
    return 1;
  }
  if (bDue == null) {
    return -1;
  }
  return aDue.compareTo(bDue);
}

String taskFilterLabel(TaskFilter filter) {
  return switch (filter) {
    TaskFilter.open => 'Abertas',
    TaskFilter.today => 'Hoje',
    TaskFilter.scheduled => 'Com hora',
    TaskFilter.done => 'Feitas',
    TaskFilter.all => 'Todas',
  };
}

String timelineLabel(TaskItem task) {
  final dueAtUtc = task.dueAtUtc;
  if (dueAtUtc == null) {
    return 'Solto';
  }
  return formatLocalTime(dueAtUtc);
}

String noteTaskDescription(NoteItem note) {
  final trimmed = note.body.trim();
  if (trimmed.isEmpty) {
    return 'Criada a partir da nota "${note.title}".';
  }

  final compact = trimmed.split(RegExp(r'\s+')).take(42).join(' ');
  return 'Criada a partir da nota "${note.title}".\n\n$compact';
}

String todayLabel({DateTime? now}) {
  final current = now ?? DateTime.now();
  final day = current.day.toString().padLeft(2, '0');
  final month = current.month.toString().padLeft(2, '0');
  return '$day/$month/${current.year}';
}

List<int> agendaYears({DateTime? now, int throughYear = agendaThroughYear}) {
  final currentYear = (now ?? DateTime.now()).year;
  final firstYear = currentYear <= throughYear ? currentYear : throughYear;
  return <int>[for (var year = firstYear; year <= throughYear; year++) year];
}

DateTime dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool isSameDate(DateTime left, DateTime right) {
  final a = dateOnly(left);
  final b = dateOnly(right);
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

int daysInMonth(int year, int month) {
  return DateTime(year, month + 1, 0).day;
}

DateTime sameDayOrLastValidDate({
  required int year,
  required int month,
  required int preferredDay,
}) {
  final day = preferredDay.clamp(1, daysInMonth(year, month)).toInt();
  return DateTime(year, month, day);
}

Map<DateTime, int> taskCountsByDate(Iterable<TaskItem> tasks) {
  final counts = <DateTime, int>{};
  for (final task in tasks) {
    final dueAtUtc = task.dueAtUtc;
    if (dueAtUtc == null) {
      continue;
    }
    final date = dateOnly(dueAtUtc);
    counts[date] = (counts[date] ?? 0) + 1;
  }
  return counts;
}

List<TaskItem> tasksDueOnDate(Iterable<TaskItem> tasks, DateTime date) {
  return tasks.where((task) {
    final dueAtUtc = task.dueAtUtc;
    return dueAtUtc != null && isSameDate(dueAtUtc, date);
  }).toList()..sort(compareTasksByAgenda);
}

String dailyNoteTitle(DateTime dateTime) {
  return 'Diário - ${formatLocalDate(dateTime)}';
}

DateTime? dailyNoteDate(NoteItem note) {
  final match = RegExp(
    r'^Diário - (\d{2})/(\d{2})/(\d{4})$',
  ).firstMatch(note.title.trim());
  if (match == null) {
    return null;
  }

  final day = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final year = int.tryParse(match.group(3)!);
  if (day == null || month == null || year == null) {
    return null;
  }
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) {
    return null;
  }
  return DateTime(year, month, day);
}

Map<DateTime, int> noteCountsByDate(Iterable<NoteItem> notes) {
  final counts = <DateTime, int>{};
  for (final note in notes) {
    final date = dailyNoteDate(note);
    if (date == null) {
      continue;
    }
    counts[date] = (counts[date] ?? 0) + 1;
  }
  return counts;
}

List<NoteItem> dailyNotesForDate(Iterable<NoteItem> notes, DateTime date) {
  return notes.where((note) {
      final noteDate = dailyNoteDate(note);
      return noteDate != null && isSameDate(noteDate, date);
    }).toList()
    ..sort((left, right) => right.updatedAtUtc.compareTo(left.updatedAtUtc));
}

List<ScheduledNotificationRecord> notificationsForDate(
  Iterable<ScheduledNotificationRecord> notifications,
  DateTime date,
) {
  return notifications
      .where((record) => isSameDate(record.scheduledForUtc, date))
      .toList()
    ..sort(
      (left, right) => left.scheduledForUtc.compareTo(right.scheduledForUtc),
    );
}

List<ScheduledNotificationRecord> upcomingNotifications(
  Iterable<ScheduledNotificationRecord> notifications, {
  DateTime? nowUtc,
}) {
  final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
  return notifications
      .where((record) => record.scheduledForUtc.toUtc().isAfter(now))
      .toList()
    ..sort(
      (left, right) => left.scheduledForUtc.compareTo(right.scheduledForUtc),
    );
}

String formatLocal(tz.TZDateTime dateTime) {
  final day = dateTime.day.toString().padLeft(2, '0');
  final month = dateTime.month.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$day/$month/${dateTime.year} $hour:$minute';
}

String formatLocalTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String formatLocalDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${formatLocalDate(local)} ${formatLocalTime(local)}';
}

String formatLocalDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}

String taskMeta(TaskItem task, {DateTime? now}) {
  if (task.isDone) {
    return 'Concluída';
  }
  final source = task.sourceNoteId == null ? '' : ' • nota';
  final dueAtUtc = task.dueAtUtc;
  if (dueAtUtc == null) {
    return 'Sem vínculo com calendário$source';
  }
  final prefix = isToday(dueAtUtc.toLocal(), now: now)
      ? 'Hoje'
      : formatLocalDate(dueAtUtc);
  final reminder = task.reminderEnabled ? ' • alerta' : '';
  return '$prefix, ${formatLocalTime(dueAtUtc)}$reminder$source';
}

String _searchPreview(String value, String normalizedQuery) {
  final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.isEmpty) {
    return '';
  }

  final normalized = normalizeSearchText(compact);
  final matchIndex = normalized.indexOf(normalizedQuery);
  if (matchIndex < 0) {
    return compact.length <= 96 ? compact : '${compact.substring(0, 96)}...';
  }

  final start = max(0, matchIndex - 32);
  final end = min(compact.length, matchIndex + normalizedQuery.length + 56);
  final prefix = start == 0 ? '' : '...';
  final suffix = end == compact.length ? '' : '...';
  return '$prefix${compact.substring(start, end)}$suffix';
}

const _searchDiacritics = <String, String>{
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

Color entryTone(int index) {
  const tones = <Color>[
    Color(0xFF4D6B5F),
    Color(0xFF396D86),
    Color(0xFF9A5B4B),
    Color(0xFF6F5D8D),
    Color(0xFF7A6B3F),
  ];
  return tones[index % tones.length];
}

bool isToday(DateTime localDateTime, {DateTime? now}) {
  final current = now ?? DateTime.now();
  return localDateTime.year == current.year &&
      localDateTime.month == current.month &&
      localDateTime.day == current.day;
}
