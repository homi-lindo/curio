import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/theme/curio_theme.dart';

void main() {
  test('Curió themes expose light and dark variants for every profile', () {
    for (final profile in CurioThemeProfile.values) {
      final light = curioThemeData(profile, Brightness.light);
      final dark = curioThemeData(profile, Brightness.dark);

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
      expect(light.scaffoldBackgroundColor, light.colorScheme.surface);
      expect(dark.scaffoldBackgroundColor, dark.colorScheme.surface);
    }
  });

  testWidgets('system mode follows platform brightness', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    late ThemeData capturedTheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: curioThemeData(CurioThemeProfile.lumen, Brightness.light),
        darkTheme: curioThemeData(CurioThemeProfile.lumen, Brightness.dark),
        themeMode: ThemeMode.system,
        home: Builder(
          builder: (context) {
            capturedTheme = Theme.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(capturedTheme.brightness, Brightness.dark);
    expect(capturedTheme.colorScheme.primary, const Color(0xFFCDBDFF));
  });
}
