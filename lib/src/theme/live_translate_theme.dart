import 'package:flutter/material.dart';

import '../ui/live_translate_models.dart';

abstract final class AppColors {
  static const background = Color(0xFF041421);
  static const surface = Color(0xFF0A2134);
  static const surfaceRaised = Color(0xFF0D2A41);
  static const surfacePressed = Color(0xFF123650);
  static const border = Color(0xFF244057);
  static const divider = Color(0xFF37556D);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB3C2D3);
  static const textTertiary = Color(0xFF7F96AA);

  static const teal = Color(0xFF20D6C9);
  static const blue = Color(0xFF1B8FEF);
  static const amber = Color(0xFFFF9E2C);
  static const red = Color(0xFFFF5353);

  static Color forAccent(LiveAccent accent) {
    return switch (accent) {
      LiveAccent.teal => teal,
      LiveAccent.blue => blue,
      LiveAccent.amber => amber,
      LiveAccent.red => red,
      LiveAccent.neutral => textSecondary,
    };
  }

  static Color forSessionMode(LiveSessionMode mode) {
    return switch (mode) {
      LiveSessionMode.listening => teal,
      LiveSessionMode.speaking => amber,
      LiveSessionMode.readAloudPaused => amber,
    };
  }
}

abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const screen = 24.0;
  static const bottomControlsHeight = 148.0;
}

abstract final class AppRadii {
  static const chip = 16.0;
  static const control = 22.0;
  static const card = 12.0;
  static const sheet = 24.0;
  static const circle = 999.0;
}

abstract final class AppElevation {
  static List<BoxShadow> raised(Color color) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.18),
        blurRadius: 22,
        offset: const Offset(0, 10),
      ),
    ];
  }
}

abstract final class AppTextStyles {
  static TextStyle display(TextTheme textTheme) {
    return textTheme.displaySmall!.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
      height: 1.05,
    );
  }

  static TextStyle title(TextTheme textTheme) {
    return textTheme.titleLarge!.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
  }

  static TextStyle label(TextTheme textTheme) {
    return textTheme.labelLarge!.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
      height: 1.1,
    );
  }

  static TextStyle body(TextTheme textTheme) {
    return textTheme.bodyMedium!.copyWith(
      color: AppColors.textSecondary,
      height: 1.35,
    );
  }

  static TextStyle compact(TextTheme textTheme) {
    return textTheme.labelMedium!.copyWith(
      color: AppColors.textSecondary,
      height: 1.15,
    );
  }
}

abstract final class LiveTranslateTheme {
  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.teal,
        secondary: AppColors.blue,
        error: AppColors.red,
        surface: AppColors.surface,
      ),
      textTheme: Typography.whiteMountainView,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}
