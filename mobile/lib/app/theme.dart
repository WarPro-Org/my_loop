import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// APP COLOR PALETTE
/// MyLoop brand colors — electric cyan/turquoise primary.
/// Energetic and modern, distinct from Duolingo's green.
/// ─────────────────────────────────────────────────────────────────────────────
class AppColors {
  // Primary brand colors
  static const primary = Color(0xFF00D4AA);      // electric turquoise — main CTA
  static const primaryDark = Color(0xFF00B894);  // pressed/shadow state
  static const primaryLight = Color(0xFFE0FFF7); // subtle highlight backgrounds

  // Accent colors
  static const accent = Color(0xFF6C5CE7);       // vivid purple — achievements, special
  static const blue = Color(0xFF0984E3);         // info/links
  static const red = Color(0xFFFF6B6B);          // errors/warnings
  static const orange = Color(0xFFFFA502);       // streaks, fire
  static const yellow = Color(0xFFFFD93D);       // stars, gold, rewards
  static const pink = Color(0xFFFF6B81);         // hearts, social

  // Neutrals
  static const white = Color(0xFFFFFFFF);
  static const snow = Color(0xFFF8F9FA);         // page background
  static const grey = Color(0xFF9BA4B5);         // muted text
  static const greyLight = Color(0xFFE8ECF0);    // borders, dividers
  static const dark = Color(0xFF2D3436);         // body text
  static const darkHard = Color(0xFF1A1A2E);     // headings
}

/// ─────────────────────────────────────────────────────────────────────────────
/// APP THEME
/// Material 3 theme configuration using Nunito font.
/// ─────────────────────────────────────────────────────────────────────────────
class AppTheme {
  // Cache the theme to avoid rebuilding TextTheme objects on every access.
  // GoogleFonts.nunitoTextTheme() creates new TextStyle objects each call.
  static final ThemeData _lightTheme = _buildLight();

  /// Returns the cached light theme. Use this in MaterialApp.
  static ThemeData get light => _lightTheme;

  /// Builds the light theme once. Called only at app startup.
  static ThemeData _buildLight() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.snow,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.white,
        secondary: AppColors.accent,
        onSecondary: AppColors.white,
        error: AppColors.red,
        surface: AppColors.white,
        onSurface: AppColors.dark,
      ),
      textTheme: GoogleFonts.nunitoTextTheme().copyWith(
        headlineLarge: GoogleFonts.nunito(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: AppColors.darkHard,
        ),
        headlineMedium: GoogleFonts.nunito(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.darkHard,
        ),
        titleLarge: GoogleFonts.nunito(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.dark,
        ),
        bodyLarge: GoogleFonts.nunito(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.dark,
        ),
        bodyMedium: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.dark,
        ),
        labelLarge: GoogleFonts.nunito(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 4,
          shadowColor: AppColors.primaryDark,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: AppColors.greyLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: AppColors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.grey,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}
