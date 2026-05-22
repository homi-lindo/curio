import 'package:flutter/material.dart';

enum CurioThemeProfile { aurora, slate, lumen }

extension CurioThemeProfileLabel on CurioThemeProfile {
  String get label {
    return switch (this) {
      CurioThemeProfile.aurora => 'Aurora',
      CurioThemeProfile.slate => 'Slate',
      CurioThemeProfile.lumen => 'Lumen',
    };
  }
}

extension ThemeModeLabel on ThemeMode {
  String get label {
    return switch (this) {
      ThemeMode.system => 'Sistema',
      ThemeMode.light => 'Claro',
      ThemeMode.dark => 'Escuro',
    };
  }
}

ThemeData curioThemeData(CurioThemeProfile profile, Brightness brightness) {
  final palette = switch (profile) {
    CurioThemeProfile.aurora => _auroraPalette(brightness),
    CurioThemeProfile.slate => _slatePalette(brightness),
    CurioThemeProfile.lumen => _lumenPalette(brightness),
  };
  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.primary,
        brightness: brightness,
      ).copyWith(
        primary: palette.primary,
        secondary: palette.secondary,
        tertiary: palette.tertiary,
        surface: palette.surface,
        surfaceContainerLowest: palette.panel,
        surfaceContainerLow: palette.surfaceAlt,
        surfaceContainer: palette.surfaceAlt,
        surfaceContainerHighest: palette.control,
        onSurface: palette.ink,
        onSurfaceVariant: palette.muted,
        outline: palette.border,
        outlineVariant: palette.border,
      );
  final textBase = brightness == Brightness.dark
      ? Typography.whiteMountainView
      : Typography.blackMountainView;
  final dense = profile == CurioThemeProfile.slate;
  final radius = BorderRadius.circular(dense ? 6 : 8);
  final border = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: scheme.outlineVariant),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
    textTheme: textBase.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      selectedIconTheme: IconThemeData(color: scheme.primary),
      selectedLabelTextStyle: TextStyle(color: scheme.primary),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final color = states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.onSurfaceVariant;
        return TextStyle(color: color, fontWeight: FontWeight.w700);
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: scheme.onSurface),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
      ),
    ),
    chipTheme: ChipThemeData(
      selectedColor: scheme.primaryContainer,
      backgroundColor: scheme.surfaceContainerHighest,
      labelStyle: TextStyle(color: scheme.onSurface),
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
  );
}

_CurioPalette _auroraPalette(Brightness brightness) {
  if (brightness == Brightness.dark) {
    return const _CurioPalette(
      surface: Color(0xFF16161A),
      surfaceAlt: Color(0xFF202027),
      panel: Color(0xFF1B1B20),
      control: Color(0xFF282830),
      ink: Color(0xFFE8E6E1),
      muted: Color(0xFFB7B1A7),
      border: Color(0xFF34323A),
      primary: Color(0xFFE8915A),
      secondary: Color(0xFF9F7662),
      tertiary: Color(0xFF7CA6B8),
    );
  }

  return const _CurioPalette(
    surface: Color(0xFFFAFAF7),
    surfaceAlt: Color(0xFFF3F0E9),
    panel: Color(0xFFFFFFFF),
    control: Color(0xFFF1EDE4),
    ink: Color(0xFF1A1A1A),
    muted: Color(0xFF6C665E),
    border: Color(0xFFEEEAE2),
    primary: Color(0xFFD97757),
    secondary: Color(0xFF8F6A52),
    tertiary: Color(0xFF4A7181),
  );
}

_CurioPalette _slatePalette(Brightness brightness) {
  if (brightness == Brightness.dark) {
    return const _CurioPalette(
      surface: Color(0xFF0E1117),
      surfaceAlt: Color(0xFF161B22),
      panel: Color(0xFF161B22),
      control: Color(0xFF202734),
      ink: Color(0xFFE6EDF3),
      muted: Color(0xFF9AA7B7),
      border: Color(0xFF2A2F3A),
      primary: Color(0xFF7C8CFF),
      secondary: Color(0xFF6FB6D5),
      tertiary: Color(0xFFE39B78),
    );
  }

  return const _CurioPalette(
    surface: Color(0xFFFBFBFD),
    surfaceAlt: Color(0xFFF1F3F7),
    panel: Color(0xFFFFFFFF),
    control: Color(0xFFF4F6FA),
    ink: Color(0xFF0E1117),
    muted: Color(0xFF576071),
    border: Color(0xFFE4E7EC),
    primary: Color(0xFF5660D8),
    secondary: Color(0xFF327AA2),
    tertiary: Color(0xFFA15A42),
  );
}

_CurioPalette _lumenPalette(Brightness brightness) {
  if (brightness == Brightness.dark) {
    return const _CurioPalette(
      surface: Color(0xFF141218),
      surfaceAlt: Color(0xFF211D27),
      panel: Color(0xFF1D1A22),
      control: Color(0xFF2B2730),
      ink: Color(0xFFECE6F0),
      muted: Color(0xFFC9BECF),
      border: Color(0xFF3B3542),
      primary: Color(0xFFCDBDFF),
      secondary: Color(0xFFB6C9A7),
      tertiary: Color(0xFFE9B39D),
    );
  }

  return const _CurioPalette(
    surface: Color(0xFFFEF7FF),
    surfaceAlt: Color(0xFFF4EFF8),
    panel: Color(0xFFFFFFFF),
    control: Color(0xFFF2ECF6),
    ink: Color(0xFF1D1B20),
    muted: Color(0xFF655E69),
    border: Color(0xFFE7DFF0),
    primary: Color(0xFF7C5BCA),
    secondary: Color(0xFF5D7550),
    tertiary: Color(0xFF8E4F39),
  );
}

final class _CurioPalette {
  const _CurioPalette({
    required this.surface,
    required this.surfaceAlt,
    required this.panel,
    required this.control,
    required this.ink,
    required this.muted,
    required this.border,
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  final Color surface;
  final Color surfaceAlt;
  final Color panel;
  final Color control;
  final Color ink;
  final Color muted;
  final Color border;
  final Color primary;
  final Color secondary;
  final Color tertiary;
}
