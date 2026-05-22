import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lume/app_brand.dart';
import 'package:lume_core/domain/reminder.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/occurrence_calculator.dart';
import 'local_timezone.dart';

final class NotificationPermissionState {
  const NotificationPermissionState({
    this.notificationsGranted,
    this.exactAlarmsGranted,
  });

  final bool? notificationsGranted;
  final bool? exactAlarmsGranted;

  bool get usesInexactAndroidScheduling => exactAlarmsGranted == false;

  bool get canCreateExactReminders =>
      notificationsGranted != false && exactAlarmsGranted != false;

  bool get needsSystemAuthorization =>
      notificationsGranted == false || exactAlarmsGranted == false;

  String get authorizationBlockerLabel {
    if (notificationsGranted == false && exactAlarmsGranted == false) {
      return 'ative notificações e alarmes exatos nas autorizações do sistema';
    }
    if (notificationsGranted == false) {
      return 'ative notificações nas autorizações do sistema';
    }
    if (exactAlarmsGranted == false) {
      return 'ative alarmes exatos nas autorizações do sistema';
    }
    return 'autorizações prontas';
  }

  String get label {
    final notification = notificationsGranted == null
        ? 'nativo'
        : notificationsGranted!
        ? 'permitida'
        : 'bloqueada';
    final exact = exactAlarmsGranted == null
        ? 'nativo'
        : exactAlarmsGranted!
        ? 'permitido'
        : 'bloqueado';
    return 'notificações: $notification | alarme exato: $exact';
  }

  String get deliveryLabel {
    if (usesInexactAndroidScheduling) {
      return 'alarme aproximado';
    }
    return 'alarme exato';
  }
}

final class ScheduleResult {
  const ScheduleResult({
    required this.plan,
    required this.record,
    required this.matchDateTimeComponents,
    required this.permissionState,
    required this.androidScheduleMode,
  });

  final OccurrencePlan plan;
  final ScheduledNotificationRecord record;
  final DateTimeComponents? matchDateTimeComponents;
  final NotificationPermissionState permissionState;
  final AndroidScheduleMode androidScheduleMode;

  String get deliveryLabel => permissionState.deliveryLabel;
}

final class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final OccurrenceCalculator _calculator = const OccurrenceCalculator();

  late final String localTimeZoneId;

  tz.Location get localLocation => tz.local;

  Future<void> initialize({
    void Function(String? payload)? onNotificationSelected,
  }) async {
    localTimeZoneId = await _configureLocalTimeZone();

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      windows: WindowsInitializationSettings(
        appName: appDisplayName,
        appUserModelId: appWindowsAppUserModelId,
        guid: '1dc8ef7e-5bb7-4e32-9c35-8787785a88a7',
      ),
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        onNotificationSelected?.call(response.payload);
      },
    );
  }

  Future<NotificationAppLaunchDetails?> getLaunchDetails() {
    return _plugin.getNotificationAppLaunchDetails();
  }

  Future<NotificationPermissionState> requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (android == null) {
      return const NotificationPermissionState();
    }

    final notificationsGranted = await android.requestNotificationsPermission();
    final exactAlarmsGranted = await android.requestExactAlarmsPermission();
    final current = await currentPermissionState();

    return NotificationPermissionState(
      notificationsGranted:
          current.notificationsGranted ?? notificationsGranted,
      exactAlarmsGranted: current.exactAlarmsGranted ?? exactAlarmsGranted,
    );
  }

  Future<NotificationPermissionState> currentPermissionState() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (android == null) {
      return const NotificationPermissionState();
    }

    return NotificationPermissionState(
      notificationsGranted: await android.areNotificationsEnabled(),
      exactAlarmsGranted: await android.canScheduleExactNotifications(),
    );
  }

  Future<NotificationPermissionState> requestMissingSchedulePermissions({
    NotificationPermissionState? current,
  }) async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (android == null) {
      return const NotificationPermissionState();
    }

    final before = current ?? await currentPermissionState();
    var notificationsGranted = before.notificationsGranted;
    var exactAlarmsGranted = before.exactAlarmsGranted;

    if (notificationsGranted == false) {
      notificationsGranted = await android.requestNotificationsPermission();
    }
    if (exactAlarmsGranted == false) {
      exactAlarmsGranted = await android.requestExactAlarmsPermission();
    }

    final after = await currentPermissionState();
    return NotificationPermissionState(
      notificationsGranted: after.notificationsGranted ?? notificationsGranted,
      exactAlarmsGranted: after.exactAlarmsGranted ?? exactAlarmsGranted,
    );
  }

  Future<ScheduleResult?> scheduleReminder({
    required ReminderIntent intent,
    required String deviceId,
    required String title,
    required String body,
    tz.TZDateTime? now,
  }) async {
    final plan = _calculator.nextOccurrence(
      intent,
      location: localLocation,
      from: now ?? tz.TZDateTime.now(localLocation),
    );
    if (plan == null) {
      return null;
    }

    final notificationId = OccurrenceCalculator.stableNotificationId(
      deviceId: deviceId,
      reminderIntentId: intent.id,
      occurrenceKey: plan.occurrenceKey,
    );
    final payload = Uri(
      scheme: appUriScheme,
      host: 'reminder',
      pathSegments: <String>[intent.id],
      queryParameters: <String, String>{
        'owner': intent.ownerId,
        'occurrence': plan.occurrenceKey,
      },
    ).toString();
    final matchComponents = switch (intent.kind) {
      ScheduleKind.oneShot => null,
      ScheduleKind.daily => DateTimeComponents.time,
      ScheduleKind.weekly => DateTimeComponents.dayOfWeekAndTime,
    };
    final permissionState = await currentPermissionState();
    final androidScheduleMode = androidScheduleModeForExactPermission(
      permissionState.exactAlarmsGranted,
    );

    await _plugin.zonedSchedule(
      id: notificationId,
      title: title,
      body: body,
      scheduledDate: plan.scheduledLocal,
      notificationDetails: _details,
      androidScheduleMode: androidScheduleMode,
      matchDateTimeComponents: matchComponents,
      payload: payload,
    );

    return ScheduleResult(
      plan: plan,
      record: ScheduledNotificationRecord(
        id: notificationId,
        deviceId: deviceId,
        reminderIntentId: intent.id,
        ownerId: intent.ownerId,
        ownerType: intent.ownerType,
        occurrenceKey: plan.occurrenceKey,
        scheduledForUtc: plan.scheduledUtc,
        payload: payload,
        title: title,
        body: body,
        scheduledTimeZone: localTimeZoneId,
      ),
      matchDateTimeComponents: matchComponents,
      permissionState: permissionState,
      androidScheduleMode: androidScheduleMode,
    );
  }

  Future<void> cancel(int notificationId) {
    return _plugin.cancel(id: notificationId);
  }

  Future<List<PendingNotificationRequest>> pending() {
    return _plugin.pendingNotificationRequests();
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'lume_reminders',
      '$appDisplayName reminders',
      channelDescription: 'Lembretes de notas e agenda do $appDisplayName',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
    windows: WindowsNotificationDetails(
      scenario: WindowsNotificationScenario.reminder,
      duration: WindowsNotificationDuration.long,
    ),
  );

  Future<String> _configureLocalTimeZone() async {
    tzdata.initializeTimeZones();

    try {
      final timeZoneId = const LocalTimeZoneResolver().resolve();
      tz.setLocalLocation(tz.getLocation(timeZoneId));
      return timeZoneId;
    } catch (_) {
      debugPrint('$appDisplayName timezone fallback: UTC');
      tz.setLocalLocation(tz.UTC);
      return 'UTC';
    }
  }
}

@visibleForTesting
AndroidScheduleMode androidScheduleModeForExactPermission(
  bool? exactAlarmsGranted,
) {
  if (exactAlarmsGranted == false) {
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }
  return AndroidScheduleMode.exactAllowWhileIdle;
}
