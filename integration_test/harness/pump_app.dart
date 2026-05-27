// pump_app.dart — boots CurioApp with in-memory stores for hermetic tests.
//
// NotificationService is a final class and FlutterLocalNotificationsPlugin
// also has a private constructor, so subclassing/mocking is not possible from
// outside the library. Instead we use the real NotificationService: on the
// Windows test runner the platform channel calls are no-ops (zonedSchedule,
// initialize, etc.) because the Windows platform plugin is not registered in
// the test environment. Effects can still be observed via the app's _activity
// log and snapshot state.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/app_database.dart';
import 'package:lume/main.dart';
import 'package:lume/services/appearance_settings_store.dart';
import 'package:lume/services/device_identity.dart';
import 'package:lume/services/local_store.dart';
import 'package:lume/services/note_edit_history_store.dart';
import 'package:lume/services/notification_service.dart';
import 'package:lume/services/sync_settings_store.dart';

/// Boots a hermetic [CurioApp] inside [tester].
///
/// All store dependencies write to a temporary directory that is deleted on
/// [TestHarness.dispose]. The real [NotificationService] is used; platform
/// channel calls are silently no-ops in the test runner environment.
Future<TestHarness> pumpApp(WidgetTester tester) async {
  final tmpDir = await Directory.systemTemp.createTemp('lume_e2e_');

  Future<Directory> tmpProvider() async => tmpDir;

  final db = AppDatabase(NativeDatabase.memory());
  final store = LocalStore.withDatabase(db, directoryProvider: tmpProvider);

  final notifications = NotificationService();
  final app = CurioApp(
    notifications: notifications,
    store: store,
    deviceIdentity: DeviceIdentityStore(directoryProvider: tmpProvider),
    syncSettings: SyncSettingsStore(directoryProvider: tmpProvider),
    appearanceSettings: AppearanceSettingsStore(directoryProvider: tmpProvider),
    noteHistory: NoteEditHistoryStore(directoryProvider: tmpProvider),
  );

  await tester.pumpWidget(app);
  // Wait for _startup future (initialize + load snapshot).
  await tester.pumpAndSettle(const Duration(seconds: 3));

  return TestHarness(
    notifications: notifications,
    store: store,
    tmpDir: tmpDir,
  );
}

final class TestHarness {
  const TestHarness({
    required this.notifications,
    required this.store,
    required this.tmpDir,
  });

  final NotificationService notifications;
  final LocalStore store;
  final Directory tmpDir;

  Future<void> dispose() async {
    await store.close();
    await tmpDir.delete(recursive: true);
  }
}
