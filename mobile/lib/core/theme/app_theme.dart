import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const navy = Color(0xFF0B1B3F);
  static const primary = Color(0xFF0A5BD3);
  static const primarySoft = Color(0xFFE8F0FC);
  static const background = Color(0xFFF6F8FC);
  static const border = Color(0xFFE3E8F0);
  static const muted = Color(0xFF5B6478);

  static const success = Color(0xFF12A150);
  static const warning = Color(0xFFE08A00);
  static const danger = Color(0xFFD92D20);
  static const info = Color(0xFF0A5BD3);
  static const neutral = Color(0xFF667085);
  static const ai = Color(0xFF7A5AF8);
  static const teal = Color(0xFF0E9384);

  // Dark theme surfaces.
  static const darkBackground = Color(0xFF0A1022);
  static const darkSurface = Color(0xFF121A30);
  static const darkBorder = Color(0xFF243052);
}

class AppTheme {
  AppTheme._();

  static const radius = 16.0;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primarySoft,
      onPrimaryContainer: AppColors.navy,
      surface: Colors.white,
      onSurface: AppColors.navy,
      onSurfaceVariant: AppColors.muted,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
      error: AppColors.danger,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF9FAFD),
      surfaceContainer: const Color(0xFFF2F5FA),
      surfaceContainerHigh: const Color(0xFFEDF1F7),
      surfaceContainerHighest: const Color(0xFFE6EBF3),
    );
    return _base(scheme, AppColors.background, AppColors.border);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.dark).copyWith(
      primary: const Color(0xFF6EA2FF),
      onPrimary: AppColors.navy,
      surface: AppColors.darkSurface,
      onSurface: const Color(0xFFE7ECF7),
      onSurfaceVariant: const Color(0xFFA3AEC6),
      outline: AppColors.darkBorder,
      outlineVariant: AppColors.darkBorder,
      error: const Color(0xFFFF6B5E),
      surfaceContainerLowest: AppColors.darkBackground,
      surfaceContainerLow: const Color(0xFF0F172B),
      surfaceContainer: const Color(0xFF162039),
      surfaceContainerHigh: const Color(0xFF1B2644),
      surfaceContainerHighest: const Color(0xFF212D4F),
    );
    return _base(scheme, AppColors.darkBackground, AppColors.darkBorder);
  }

  static ThemeData _base(ColorScheme scheme, Color background, Color border) {
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: scheme.brightness);
    final text = base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 48), shape: rounded),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: rounded,
          side: BorderSide(color: border),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: rounded)),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: border),
        labelStyle: text.labelMedium,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        iconColor: scheme.onSurfaceVariant,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        dividerColor: border,
        labelStyle: text.labelLarge,
      ),
    );
  }
}
