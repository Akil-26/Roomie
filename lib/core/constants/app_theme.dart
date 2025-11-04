import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Modern App Colors with excellent contrast and accessibility
/// Follows Material Design 3 principles with custom Roomie branding
class AppColors {
  // Light Theme Colors (Samsung Blue Accent for consistency)
  static const Color lightPrimary = Color(0xFF1976D2); // Samsung-style Blue
  static const Color lightPrimaryContainer = Color(
    0xFFE3F2FD,
  ); // Light Blue Container
  static const Color lightSecondary = Color(0xFF1976D2); // Samsung-style Blue
  static const Color lightSecondaryContainer = Color(
    0xFFF3F8FF,
  ); // Very Light Blue

  static const Color lightSurface = Color(0xFFFFFFFF); // White Background
  static const Color lightSurfaceVariant = Color(
    0xFFF9FAFB,
  ); // Light Gray Surface
  static const Color lightBackground = Color(0xFFFFFFFF); // White Background
  static const Color lightOnBackground = Color(
    0xFF000000,
  ); // Black Primary Text

  static const Color lightOnSurface = Color(0xFF000000); // Black Primary Text
  static const Color lightOnSurfaceVariant = Color(
    0xFF6B7280,
  ); // Gray-500 Secondary Text
  static const Color lightOutline = Color(0xFFE5E7EB); // Gray-200 Border
  static const Color lightOutlineVariant = Color(
    0xFFF3F4F6,
  ); // Gray-100 Light Border

  // Dark Theme Colors (Exact Samsung One UI - Settings Style)
  static const Color darkPrimary = Color(0xFF8AB4F8); // Samsung Blue Accent
  static const Color darkPrimaryContainer = Color(
    0xFF303030,
  ); // Samsung Container Gray (Settings cards)
  static const Color darkSecondary = Color(0xFF8AB4F8); // Samsung Blue Accent
  static const Color darkSecondaryContainer = Color(
    0xFF383838,
  ); // Samsung Elevated Container

  static const Color darkSurface = Color(
    0xFF000000,
  ); // Samsung Pure Black Background
  static const Color darkSurfaceVariant = Color(
    0xFF303030,
  ); // Samsung Card Gray (exact Settings match)
  static const Color darkBackground = Color(
    0xFF000000,
  ); // Samsung Pure Black Background
  static const Color darkOnBackground = Color(
    0xFFE1E1E1,
  ); // Samsung Primary Text (Settings style)

  static const Color darkOnSurface = Color(
    0xFFE1E1E1,
  ); // Samsung Primary Text (Settings style)
  static const Color darkOnSurfaceVariant = Color(
    0xFF9E9E9E,
  ); // Samsung Secondary Text (exact Settings)
  static const Color darkOutline = Color(
    0xFF404040,
  ); // Samsung Border (Settings dividers)
  static const Color darkOutlineVariant = Color(
    0xFF2A2A2A,
  ); // Samsung Subtle Border

  // Status Colors (Samsung Theme)
  static const Color success = Color(0xFF4CAF50); // Samsung Green
  static const Color successDark = Color(0xFF66BB6A); // Samsung Light Green
  static const Color error = Color(0xFFEF4444); // Red-500
  static const Color errorDark = Color(0xFFF87171); // Red-400
  static const Color warning = Color(0xFFF59E0B); // Amber-500
  static const Color warningDark = Color(0xFFFBBF24); // Amber-400

  // Chat Colors (Samsung Theme)
  static const Color lightChatSent = Color(
    0xFF1976D2,
  ); // Samsung Blue for sent messages
  static const Color lightChatReceived = Color(
    0xFFE5E7EB,
  ); // Gray-200 for received
  static const Color darkChatSent = Color(
    0xFF8AB4F8,
  ); // Samsung Blue for sent messages
  static const Color darkChatReceived = Color(
    0xFF303030,
  ); // Samsung Container Gray for received (Settings match)

  // Special Colors (Emerald Theme)
  static const Color accent = Color(0xFF1976D2); // Samsung Blue Accent
  static const Color accentDark = Color(0xFF8AB4F8); // Samsung Light Blue

  // Expense Colors (Samsung Theme)
  static const Color expenseIncome = Color(
    0xFF4CAF50,
  ); // Samsung Green for income
  static const Color expenseExpense = Color(0xFFEF4444); // Red-500 for expenses
  static const Color expenseNeutral = Color(0xFF6B7280); // Gray-500 for neutral

  // Gradient Colors (Samsung Theme)
  static const List<Color> lightGradient = [
    Color(0xFF1976D2), // Samsung Blue
    Color(0xFF42A5F5), // Samsung Light Blue
  ];

  static const List<Color> darkGradient = [
    Color(0xFF1565C0), // Samsung Blue-700 (darker)
    Color(0xFF8AB4F8), // Samsung Blue for dark mode
  ];
}

/// Modern App Themes with excellent accessibility and visual hierarchy
/// Supports both light and dark modes with proper contrast ratios
class AppThemes {
  /// Light Theme - Clean, bright, and accessible
  static ThemeData get lightTheme {
    const colorScheme = ColorScheme.light(
      primary: AppColors.lightPrimary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.lightPrimaryContainer,
      onPrimaryContainer: AppColors.lightPrimary,
      secondary: AppColors.lightSecondary,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.lightSecondaryContainer,
      onSecondaryContainer: AppColors.lightSecondary,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightOnSurface,
      surfaceContainerHighest: AppColors.lightSurfaceVariant,
      onSurfaceVariant: AppColors.lightOnSurfaceVariant,
      error: AppColors.error,
      onError: Colors.white,
      outline: AppColors.lightOutline,
      outlineVariant: AppColors.lightOutlineVariant,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.lightBackground,

      // App Bar Theme
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightSurface,
        foregroundColor: AppColors.lightOnSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.lightOnSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Button Themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.lightPrimary,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 2,
          shadowColor: AppColors.lightPrimary.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.lightPrimary,
          side: const BorderSide(color: AppColors.lightPrimary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.lightPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // Input Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.lightOutline.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: TextStyle(
          color: AppColors.lightOnSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        selectedItemColor: AppColors.lightPrimary,
        unselectedItemColor: AppColors.lightOnSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: 12,
        ),
      ),

      // Floating Action Button
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.lightPrimary,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: CircleBorder(),
      ),

      // Snackbar Theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.lightOnSurface,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Dark Theme - Easy on the eyes with proper contrast
  static ThemeData get darkTheme {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.darkBackground,
      primaryContainer: AppColors.darkPrimaryContainer,
      onPrimaryContainer: AppColors.darkPrimary,
      secondary: AppColors.darkSecondary,
      onSecondary: AppColors.darkBackground,
      secondaryContainer: AppColors.darkSecondaryContainer,
      onSecondaryContainer: AppColors.darkSecondary,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkOnSurface,
      surfaceContainerHighest: AppColors.darkSurfaceVariant,
      onSurfaceVariant: AppColors.darkOnSurfaceVariant,
      error: AppColors.errorDark,
      onError: AppColors.darkBackground,
      outline: AppColors.darkOutline,
      outlineVariant: AppColors.darkOutlineVariant,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.darkBackground,

      // App Bar Theme (Samsung One UI Style)
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkSurface, // Keep pure black for app bar
        foregroundColor: AppColors.darkOnSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.darkOnSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      // Card Theme (Samsung One UI Style)
      cardTheme: CardThemeData(
        color: AppColors.darkSurfaceVariant, // Use dark gray for cards
        surfaceTintColor: Colors.transparent,
        elevation: 2, // Reduced elevation for One UI style
        shadowColor: Colors.black.withValues(alpha: 0.4),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Button Themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkPrimary,
          foregroundColor: AppColors.darkBackground,
          surfaceTintColor: Colors.transparent,
          elevation: 4,
          shadowColor: AppColors.darkPrimary.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkPrimary,
          side: const BorderSide(color: AppColors.darkPrimary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.darkPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // Input Theme (Samsung One UI Style)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceVariant, // Dark gray fill
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.darkOutline.withValues(alpha: 0.3),
          ), // Subtle border
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.errorDark, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: TextStyle(
          color: AppColors.darkOnSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),

      // Bottom Navigation (Samsung One UI Style)
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkSurface, // Keep pure black
        selectedItemColor: AppColors.darkPrimary,
        unselectedItemColor: AppColors.darkOnSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0, // Reduced elevation for One UI style
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: 12,
        ),
      ),

      // Floating Action Button
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.darkPrimary,
        foregroundColor: AppColors.darkBackground,
        elevation: 6,
        shape: CircleBorder(),
      ),

      // Snackbar Theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkOnSurface,
        contentTextStyle: const TextStyle(color: AppColors.darkBackground),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Helper method to get text style with proper contrast
  static TextStyle getTextStyle(
    BuildContext context, {
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: fontSize ?? 14,
      fontWeight: fontWeight ?? FontWeight.normal,
      color:
          color ??
          (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
    );
  }

  /// Helper method to get surface color for current theme
  static Color getSurfaceColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppColors.darkSurface : AppColors.lightSurface;
  }

  /// Helper method to get chat bubble colors
  static Color getChatBubbleColor(BuildContext context, bool isSent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isSent) {
      return isDark ? AppColors.darkChatSent : AppColors.lightChatSent;
    } else {
      return isDark ? AppColors.darkChatReceived : AppColors.lightChatReceived;
    }
  }
}
