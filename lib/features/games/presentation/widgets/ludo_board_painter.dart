import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../data/ludo_board.dart';

/// Paints the classic Ludo board onto a square canvas.
class LudoBoardPainter extends CustomPainter {
  const LudoBoardPainter();

  // Premium, clean Ludo colors
  static const Color _red = Color(0xFFFF4B4B); // Bright modern Red
  static const Color _blue = Color(0xFF0084FF); // Bright modern Blue
  static const Color _green = Color(0xFF00D084); // Bright modern Green
  static const Color _yellow = Color(0xFFFFB900); // Bright modern Yellow

  static const Color _redL = Color(0xFFFFD6D6);
  static const Color _blueL = Color(0xFFD6EBFF);
  static const Color _greenL = Color(0xFFD6F5E9);
  static const Color _yellowL = Color(0xFFFFF4D6);

  static const Color _path = Color(0xFFFFFFFF); // Pure white for path
  static const Color _bg = Color(0xFFFAFAFA); // Slightly off-white board base
  static const Color _border = Color(0xFFE0E0E0); // Soft grid lines
  static const Color _safe = Color(0xFFF0F0F0); // Safe cell subtle background

  @override
  void paint(Canvas canvas, Size size) {
    final cs = size.width / 15; // cell size

    // 1. Board background (rounded)
    final boardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(cs * 0.8),
    );
    canvas.drawRRect(boardRect, Paint()..color = _bg);

    // 2. Path cells (horizontal strip + vertical strip backgrounds) — painted
    //    BEFORE the corners so the corners always render on top and never
    //    need a second "restore" pass.
    _fillRect(canvas, 6, 0, 3, 15, cs, _path);
    _fillRect(canvas, 0, 6, 15, 3, cs, _path);

    // 3. Corner home zones (all 4, even if only 2 are active players)
    _fillRect(canvas, 0, 0, 6, 6, cs, _red);
    _fillRect(canvas, 0, 9, 6, 6, cs, _green);
    _fillRect(canvas, 9, 0, 6, 6, cs, _yellow);
    _fillRect(canvas, 9, 9, 6, 6, cs, _blue);

    // 4. Inner token yards (white rounded rect inside each home).
    //    Each corner's colored square is a 6x6 block starting at the
    //    corner's own origin (0,0 / 0,9 / 9,0 / 9,9). The yard card must be
    //    centered *within* that block, which means its own origin is the
    //    corner origin + 1 cell in both directions (not the corner origin
    //    itself) — otherwise only the top-left (red) corner centers correctly
    //    and the other three drift toward the board's outer edge.
    _drawYard(canvas, 1, 1, cs, _red);
    _drawYard(canvas, 1, 10, cs, _green);
    _drawYard(canvas, 10, 1, cs, _yellow);
    _drawYard(canvas, 10, 10, cs, _blue);

    // 5. Home columns (colored strips leading to center).
    //    Matches kRedHomeCol / kBlueHomeCol exactly: red spans col 1..6,
    //    blue spans col 8..13 (the cell touching center is included so a
    //    token sitting one step from home visibly looks "almost there").
    for (int c = 1; c <= 6; c++) _fillCell(canvas, 7, c, cs, _redL);
    for (int c = 8; c <= 13; c++) _fillCell(canvas, 7, c, cs, _blueL);
    for (int r = 1; r <= 5; r++) _fillCell(canvas, r, 7, cs, _greenL);
    for (int r = 9; r <= 13; r++) _fillCell(canvas, r, 7, cs, _yellowL);

    // Colored entry squares (starting spots)
    _fillCell(canvas, 6, 1, cs, _red);
    _fillCell(canvas, 8, 13, cs, _blue);
    _fillCell(canvas, 1, 8, cs, _green);
    _fillCell(canvas, 13, 6, cs, _yellow);

    // 6. Safe cells (subtle highlight + star)
    for (final key in kSafeCells) {
      final parts = key.split(',');
      final r = int.parse(parts[0]);
      final c = int.parse(parts[1]);
      // Don't override the solid color of the entry squares.
      if (!(r == 6 && c == 1) && !(r == 8 && c == 13)) {
        _fillCell(canvas, r, c, cs, _safe);
      }
      _drawStar(canvas, r, c, cs, Colors.amber.shade500);
    }

    // 7. Center home triangles
    _drawCenterTriangles(canvas, cs);

    // 8. Grid lines over everything
    _drawGrid(canvas, size, cs);
  }

  void _fillRect(Canvas canvas, int row, int col, int rows, int cols, double cs, Color color) {
    canvas.drawRect(
      Rect.fromLTWH(col * cs, row * cs, cols * cs, rows * cs),
      Paint()..color = color,
    );
  }

  void _fillCell(Canvas canvas, int row, int col, double cs, Color color) {
    canvas.drawRect(
      Rect.fromLTWH(col * cs, row * cs, cs, cs),
      Paint()..color = color,
    );
  }

  void _drawYard(Canvas canvas, int row, int col, double cs, Color zoneColor) {
    // 4×4 white rounded rectangle yard inside home zone
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(col * cs + cs * 0.15, row * cs + cs * 0.15, cs * 3.7, cs * 3.7),
      Radius.circular(cs * 0.6),
    );
    canvas.drawRRect(rect, Paint()..color = Colors.white);

    // 4 token-base circles, aligned with kRedBaseSlots / kBlueBaseSlots in
    // ludo_board.dart (row+0.65/2.35, col+0.65/2.35).
    final positions = [
      [row + 1.15, col + 1.15],
      [row + 1.15, col + 2.85],
      [row + 2.85, col + 1.15],
      [row + 2.85, col + 2.85],
    ];
    for (final p in positions) {
      final cx = p[1] * cs;
      final cy = p[0] * cs;
      canvas.drawCircle(
        Offset(cx, cy),
        cs * 0.5,
        Paint()..color = zoneColor.withValues(alpha: 0.15),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        cs * 0.5,
        Paint()
          ..color = zoneColor.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _drawGrid(Canvas canvas, Size size, double cs) {
    final paint = Paint()
      ..color = _border
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw grid lines only in the cross path area to keep home zones clean.
    for (int i = 0; i <= 15; i++) {
      if (i >= 6 && i <= 9) {
        canvas.drawLine(Offset(0, i * cs), Offset(size.width, i * cs), paint);
      } else {
        canvas.drawLine(Offset(6 * cs, i * cs), Offset(9 * cs, i * cs), paint);
      }
      if (i >= 6 && i <= 9) {
        canvas.drawLine(Offset(i * cs, 0), Offset(i * cs, size.height), paint);
      } else {
        canvas.drawLine(Offset(i * cs, 6 * cs), Offset(i * cs, 9 * cs), paint);
      }
    }

    // Outer border of the whole board.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), Radius.circular(cs * 0.8)),
      Paint()
        ..color = _border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawStar(Canvas canvas, int row, int col, double cs, Color color) {
    final cx = (col + 0.5) * cs;
    final cy = (row + 0.5) * cs;
    final r = cs * 0.3;
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final angle = (i * 4 * math.pi / 5) - math.pi / 2;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
  }

  void _drawCenterTriangles(Canvas canvas, double cs) {
    final cx = 7.5 * cs;
    final cy = 7.5 * cs;

    void tri(Offset a, Offset b, Color c) {
      final p = Path()
        ..moveTo(cx, cy)
        ..lineTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..close();
      canvas.drawPath(p, Paint()..color = c);
      canvas.drawPath(p, Paint()..color = _border..style = PaintingStyle.stroke..strokeWidth = 1);
    }

    tri(Offset(6 * cs, 6 * cs), Offset(9 * cs, 6 * cs), _green);
    tri(Offset(6 * cs, 9 * cs), Offset(9 * cs, 9 * cs), _blue);
    tri(Offset(6 * cs, 6 * cs), Offset(6 * cs, 9 * cs), _red);
    tri(Offset(9 * cs, 6 * cs), Offset(9 * cs, 9 * cs), _yellow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
