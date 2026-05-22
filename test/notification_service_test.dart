import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/notification_service.dart';

void main() {
  test('uses exact Android scheduling when exact alarms are available', () {
    expect(
      androidScheduleModeForExactPermission(true),
      AndroidScheduleMode.exactAllowWhileIdle,
    );
    expect(
      androidScheduleModeForExactPermission(null),
      AndroidScheduleMode.exactAllowWhileIdle,
    );
  });

  test(
    'falls back to inexact Android scheduling when exact alarms are denied',
    () {
      expect(
        androidScheduleModeForExactPermission(false),
        AndroidScheduleMode.inexactAllowWhileIdle,
      );
    },
  );

  test('permission label exposes Android delivery precision', () {
    const denied = NotificationPermissionState(
      notificationsGranted: true,
      exactAlarmsGranted: false,
    );
    const granted = NotificationPermissionState(
      notificationsGranted: true,
      exactAlarmsGranted: true,
    );

    expect(denied.deliveryLabel, 'alarme aproximado');
    expect(granted.deliveryLabel, 'alarme exato');
  });

  test('permission state gates exact reminder creation', () {
    const ready = NotificationPermissionState(
      notificationsGranted: true,
      exactAlarmsGranted: true,
    );
    const notificationDenied = NotificationPermissionState(
      notificationsGranted: false,
      exactAlarmsGranted: true,
    );
    const exactDenied = NotificationPermissionState(
      notificationsGranted: true,
      exactAlarmsGranted: false,
    );

    expect(ready.canCreateExactReminders, isTrue);
    expect(ready.needsSystemAuthorization, isFalse);
    expect(notificationDenied.canCreateExactReminders, isFalse);
    expect(notificationDenied.needsSystemAuthorization, isTrue);
    expect(exactDenied.canCreateExactReminders, isFalse);
    expect(exactDenied.authorizationBlockerLabel, contains('alarmes exatos'));
  });
}
