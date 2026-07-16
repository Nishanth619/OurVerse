import 'package:flutter/material.dart';

/// Responsive layout utilities for the Closer app.
///
/// These helpers allow screens to gracefully scale between small Android
/// phones (320 – 360 px wide) and larger devices (414 px+) without
/// hardcoding breakpoints everywhere.
///
/// **Reference width**: 390 px (iPhone 14 / Pixel 7 — our design baseline).
///
/// Usage example:
/// ```dart
/// final r = Responsive.of(context);
/// Text('Hello', style: TextStyle(fontSize: r.sp(18)));
/// ```
class Responsive {
  const Responsive._(this._width, this._height);

  factory Responsive.of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Responsive._(size.width, size.height);
  }

  static const double _refWidth = 390.0;

  final double _width;
  final double _height;

  // ── Screen category helpers ───────────────────────────────────────────────

  bool get isSmall => _width < 360;
  bool get isMedium => _width >= 360 && _width < 414;
  bool get isLarge => _width >= 414;

  double get screenWidth => _width;
  double get screenHeight => _height;

  // ── Scaling factor ────────────────────────────────────────────────────────

  /// Raw scale factor relative to the 390 px reference width.
  double get _scale => (_width / _refWidth).clamp(0.78, 1.30);

  // ── Font size (sp — scalable pixels) ─────────────────────────────────────

  /// Returns a font size that scales proportionally to the screen width.
  ///
  /// The value is clamped so text is never unreadably tiny on small screens
  /// or excessively large on tablets.
  double sp(double size) => (size * _scale).roundToDouble();

  // ── Layout dimension (dp) ─────────────────────────────────────────────────

  /// Returns a dimension (width/height/padding) proportional to screen width.
  double dp(double size) => size * _scale;

  // ── Horizontal padding ────────────────────────────────────────────────────

  /// Standard horizontal page padding that shrinks on small screens.
  double get hPad => isSmall ? 16.0 : 24.0;

  /// Standard vertical spacing between sections.
  double get vSpace => isSmall ? 16.0 : 24.0;

  // ── Icon size ─────────────────────────────────────────────────────────────

  /// Icon size that scales with the screen width.
  double icon(double size) => (size * _scale).clamp(size * 0.8, size * 1.2);
}

// ─── BuildContext extension ───────────────────────────────────────────────────
// Syntactic sugar: `context.responsive.sp(18)` or `context.sp(18)`.

extension ResponsiveContext on BuildContext {
  Responsive get responsive => Responsive.of(this);

  /// Scaled font size shorthand: `context.sp(18)`.
  double sp(double size) => Responsive.of(this).sp(size);

  /// Scaled dp shorthand: `context.dp(12)`.
  double dp(double size) => Responsive.of(this).dp(size);

  /// True when the screen is narrower than 360 px.
  bool get isSmallScreen => Responsive.of(this).isSmall;
}
