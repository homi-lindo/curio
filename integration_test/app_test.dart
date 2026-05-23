// Entry point: runs all integration test groups.
import 'package:integration_test/integration_test.dart';

import 'flows/agenda_test.dart';
import 'flows/board_test.dart';
import 'flows/boot_navigation_test.dart';
import 'flows/keyboard_zoom_test.dart';
import 'flows/notes_test.dart';
import 'flows/sync_test.dart';
import 'flows/today_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  bootNavigationTests();
  todayTests();
  agendaTests();
  boardTests();
  notesTests();
  syncTests();
  keyboardZoomTests();
}
