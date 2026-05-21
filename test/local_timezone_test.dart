import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/local_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('maps Windows Brasilia time zone to Sao Paulo IANA id', () {
    final id = const LocalTimeZoneResolver().resolve(
      systemName: 'E. South America Standard Time',
      systemOffset: const Duration(hours: -3),
    );

    expect(id, 'America/Sao_Paulo');
  });

  test('keeps an existing IANA id', () {
    final id = const LocalTimeZoneResolver().resolve(
      systemName: 'America/Sao_Paulo',
      systemOffset: const Duration(hours: -3),
    );

    expect(id, 'America/Sao_Paulo');
  });

  test('falls back from raw offset to preferred location', () {
    final id = const LocalTimeZoneResolver().resolve(
      systemName: 'GMT-03:00',
      systemOffset: const Duration(hours: -3),
    );

    expect(id, 'America/Sao_Paulo');
  });
}
