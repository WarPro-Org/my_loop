import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Duolingo-inspired color palette
class AppColors {
  static const green = Color(0xFF58CC02); // main green
  static const greenDark = Color(0xFF46A302); // pressed green
  static const blue = Color(0xFF1CB0F6); // info blue
  static const red = Color(0xFFFF4B4B); // error red
  static const orange = Color(0xFFFF9600); // warning orange
  static const purple = Color(0xFFA560E8); // special purple
  static const yellow = Color(0xFFFFC800); // gold/star
  static const white = Color(0xFFFFFFFF);
  static const snow = Color(0xFFF7F7F7); // background
  static const grey = Color(0xFFAFAFAF); // disabled
  static const greyLight = Color(0xFFE5E5E5); // borders
  static const dark = Color(0xFF4B4B4B); // text
  static const darkHard = Color(0xFF3C3C3C); // heading
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.snow,
      colorScheme: const ColorScheme.light(
        primary: AppColors.green,
        onPrimary: AppColors.white,
        secondary: AppColors.blue,
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
          backgroundColor: AppColors.green,
          foregroundColor: AppColors.white,
          elevation: 4,
          shadowColor: AppColors.greenDark,
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
        selectedItemColor: AppColors.green,
        unselectedItemColor: AppColors.grey,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}
