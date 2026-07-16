import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animated_emoji/animated_emoji.dart';

class AppTheme {
  // Palette: warm rose-blush with deep plum accents + soft off-white
  static const Color primary = Color(0xFFE8647A); // rose
  static const Color primaryDark = Color(0xFF3D1A2B); // deep plum
  static const Color accent = Color(0xFF7C4DFF); // warm amber (streak/games)
  static const Color surface = Color(0xFFFFF8F8); // blush white
  static const Color surfaceAlt = Color(0xFFF5E6EA); // pale rose
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF2A1020); // near-black plum
  static const Color onSurfaceMuted = Color(0xFF8B5E6A); // muted rose-brown
  static const Color divider = Color(0xFFEDD5DB);
  
  // Game colors
  static const Color background = Color(0xFF1A1A2E);
  static const Color red = Color(0xFFE53935);
  static const Color blue = Color(0xFF1E88E5);

  // Mood emoji set
  static const List<String> moodEmojis = [
    '😊',
    '😐',
    '😢',
    '😡',
    '🥰',
    '😴',
    '🤩'
  ];

  static final Map<String, AnimatedEmojiData> animatedMoods = {
    '😊': AnimatedEmojis.smile,
    '😐': AnimatedEmojis.neutralFace,
    '😢': AnimatedEmojis.cry,
    '😡': AnimatedEmojis.rage,
    '🥰': AnimatedEmojis.heartEyes,
    '😴': AnimatedEmojis.sleep,
    '🤩': AnimatedEmojis.starStruck,
  };

  static final ThemeData light = _buildLight();

  static ThemeData _buildLight() {
    // Base Nunito text theme wired into the color palette.
    // Built ONCE at startup — never called again.
    final base = GoogleFonts.nunitoTextTheme().copyWith(
      displayLarge: GoogleFonts.nunito(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        color: onSurface,
        height: 1.2,
      ),
      headlineMedium: GoogleFonts.nunito(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: onSurface,
        height: 1.3,
      ),
      titleLarge: GoogleFonts.nunito(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      bodyLarge: GoogleFonts.nunito(
        fontSize: 16,
        color: onSurface,
        height: 1.5,
      ),
      bodyMedium: GoogleFonts.nunito(
        fontSize: 14,
        color: onSurfaceMuted,
        height: 1.5,
      ),
      labelSmall: GoogleFonts.nunito(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: onSurfaceMuted,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      textTheme: base,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
        primary: primary,
        onPrimary: onPrimary,
        surface: surface,
        onSurface: onSurface,
        secondary: accent,
      ),
      scaffoldBackgroundColor: surface,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.nunito(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: onSurface,
        ),
        iconTheme: const IconThemeData(color: onSurface),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: divider, width: 1.5),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.5),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        hintStyle: GoogleFonts.nunito(color: onSurfaceMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: primary.withValues(alpha: 0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 24);
          }
          return const IconThemeData(color: onSurfaceMuted, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: primary,
            );
          }
          return GoogleFonts.nunito(fontSize: 12, color: onSurfaceMuted);
        }),
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      dividerTheme: const DividerThemeData(color: divider, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: primaryDark,
        contentTextStyle: GoogleFonts.nunito(color: Colors.white, fontSize: 14),
      ),
    );
  }
}
