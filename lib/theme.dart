import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'styles/tokens.dart';

/// Apple-inspired grouped surfaces, with native Material behavior on Android.
class BeeTheme {
  static const Color honeyGold = Color(0xFFF8C91C);
  static const Color hiveBrown = Color(0xFF8D6E63);
  static const Color energyOrange = Color(0xFFEF6C00);
  static const Color paperIvory = Color(0xFFF2F2F7);
  static const Color textDark = Color(0xFF1C1C1E);
  static const Color honeyGoldDark = honeyGold;
  static const Color hiveBrownDark = hiveBrown;
  static const Color energyOrangeDark = energyOrange;
  static const Color systemBlue = Color(0xFF0066CC);

  static ThemeData lightTheme({TargetPlatform? platform}) =>
      _build(Brightness.light, platform);
  static ThemeData darkTheme({TargetPlatform? platform}) =>
      _build(Brightness.dark, platform);

  static ThemeData _build(Brightness brightness, TargetPlatform? platform) {
    final dark = brightness == Brightness.dark;
    final pf = platform ?? defaultTargetPlatform;
    final surface = dark ? const Color(0xFF1C1C1E) : Colors.white;
    final foreground = dark ? Colors.white : textDark;
    final accent = dark ? const Color(0xFF64ACFF) : systemBlue;
    final secondaryText =
        dark ? const Color(0xFFAEAEB2) : const Color(0xFF636366);
    final separator = dark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
    final base = ThemeData(
      useMaterial3: true,
      platform: pf,
      brightness: brightness,
      colorScheme:
          ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
              .copyWith(
        primary: accent,
        onPrimary: dark ? Colors.black : Colors.white,
        secondary: accent,
        surface: surface,
        onSurface: foreground,
        onSurfaceVariant: secondaryText,
        outlineVariant: separator,
      ),
    );
    final typography = BeeTypography.buildBase(base.textTheme,
            isIOS: pf == TargetPlatform.iOS || pf == TargetPlatform.macOS)
        .apply(bodyColor: foreground, displayColor: foreground);
    return base.copyWith(
      primaryColor: accent,
      scaffoldBackgroundColor: dark ? Colors.black : paperIvory,
      textTheme: typography,
      dividerColor: separator,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? Colors.black : paperIvory,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: typography.titleLarge,
      ),
      cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: shape,
          clipBehavior: Clip.antiAlias),
      dividerTheme:
          DividerThemeData(color: separator, thickness: 0.5, space: 1),
      listTileTheme: ListTileThemeData(
          minTileHeight: 52,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          iconColor: accent,
          textColor: foreground),
      iconTheme: IconThemeData(color: foreground, size: 22),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
              minimumSize: const Size(48, 48), foregroundColor: accent)),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)))),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
              elevation: 0,
              minimumSize: const Size(48, 48),
              backgroundColor: accent,
              foregroundColor: dark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: accent, width: 2)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: surface,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)))),
      dialogTheme:
          DialogThemeData(backgroundColor: surface, elevation: 0, shape: shape),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
          elevation: 0,
          backgroundColor: accent,
          foregroundColor: dark ? Colors.black : Colors.white),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
          selectedItemColor: accent,
          unselectedItemColor: secondaryText,
          backgroundColor: surface,
          elevation: 0,
          showUnselectedLabels: true),
    );
  }
}
