import 'package:flutter/material.dart';

abstract final class FlowTheme {
  static final appearance = ValueNotifier<ThemeMode>(ThemeMode.light);
  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: blue,
    );
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF09162E),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF09162E)),
      cardTheme: CardThemeData(
        color: const Color(0xFF142544),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: blue,
        foregroundColor: Colors.white,
      ),
    );
  }

  static const blue = Color(0xFF075BEE);
  static const aqua = Color(0xFF00CFE8);
  static const ink = Color(0xFF101B43);
  static const background = Color(0xFFF4F8FF);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: blue).copyWith(
      primary: blue,
      onPrimary: Colors.white,
      secondary: const Color(0xFF007D8D),
      surface: Colors.white,
      onSurface: ink,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme
          .apply(bodyColor: ink, displayColor: ink)
          .copyWith(
            headlineLarge: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: ink,
              letterSpacing: -1,
            ),
            headlineMedium: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: ink,
              letterSpacing: -.6,
            ),
            titleLarge: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xFFE0E8F5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD3DFF0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD3DFF0)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: shape,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 46),
          shape: shape,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: blue,
        foregroundColor: Colors.white,
        elevation: 3,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE1EDFF),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? blue : ink,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? blue : Colors.white,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? Colors.white : ink,
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: blue,
        linearTrackColor: Color(0xFFE2EAF7),
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
