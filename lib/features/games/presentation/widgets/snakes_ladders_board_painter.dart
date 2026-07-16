import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../data/snakes_ladders_board.dart';

/// Snakes & Ladders board painter.
///
/// The boustrophedon layout:
///   row=9 (bottom): cells 1-10  left→right  (even row-from-bottom index=0)
///   row=8:          cells 11-20 right→left
///   row=7:          cells 21-30 left→right
///   etc.
///   row=0 (top):    cells 91-100 right→left
///
/// positionToCell(pos) already handles all this. We mirror it here for drawing.
class SnakesLaddersBoardPainter extends CustomPainter {
  final Map<int, int> snakes;
  final Map<int, int> ladders;

  const SnakesLaddersBoardPainter({
    required this.snakes,
    required this.ladders,
  });

  static const List<Color> _pastelColors = [
    Color(0xffffadad), // red-ish
    Color(0xffffd6a5), // orange
    Color(0xfffdffb6), // yellow
    Color(0xffcaffbf), // green
    Color(0xff9bf6ff), // cyan
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cs = size.width / 10; // cell size

    // ── White base ─────────────────────────────────────────────────────────
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white);

    // ── Grid cells + collect centres ──────────────────────────────────────
    final Map<int, Offset> centre = {};
    final tp = TextPainter(textDirection: TextDirection.ltr);

    for (int pos = 1; pos <= 100; pos++) {
      final rc = positionToCell(pos);
      final row = rc[0]; // 0=top … 9=bottom
      final col = rc[1];

      final x = col * cs;
      final y = row * cs;
      final rect = Rect.fromLTWH(x, y, cs, cs);

      // Colour index based on the logical "row from bottom" and column
      final rowFromBottom = 9 - row;
      final colorIdx = (rowFromBottom + col) % _pastelColors.length;

      canvas.drawRect(rect,
          Paint()..color = _pastelColors[colorIdx]..style = PaintingStyle.fill);
      canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.12)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);

      // Number colour
      Color numColor = const Color(0xff1f2937);
      if (snakes.containsKey(pos)) numColor = const Color(0xffdc2626);
      else if (ladders.containsKey(pos)) numColor = const Color(0xff16a34a);

      tp.text = TextSpan(
        text: '$pos',
        style: TextStyle(
          color: numColor,
          fontSize: cs * 0.30,
          fontWeight: FontWeight.w900,
          shadows: const [
            Shadow(color: Color(0x99ffffff), offset: Offset(1, 1))
          ],
        ),
      );
      tp.layout();
      // Numbers sit near top-left of each cell (like the reference image)
      tp.paint(canvas, Offset(x + cs * 0.06, y + cs * 0.04));

      centre[pos] = Offset(x + cs / 2, y + cs / 2);
    }

    // ── Outer border ───────────────────────────────────────────────────────
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()
          ..color = const Color(0xff166534)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);

    // ── Ladders (drawn first, under snakes) ────────────────────────────────
    for (final e in ladders.entries) {
      final s = centre[e.key];
      final en = centre[e.value];
      if (s != null && en != null) _drawLadder(canvas, s, en, cs);
    }

    // ── Snakes ─────────────────────────────────────────────────────────────
    int si = 0;
    for (final e in snakes.entries) {
      final s = centre[e.key];
      final en = centre[e.value];
      if (s != null && en != null) {
        _drawSnake(canvas, s, en, si, cs);
        si++;
      }
    }
  }

  // ── Ladder ─────────────────────────────────────────────────────────────
  void _drawLadder(Canvas canvas, Offset start, Offset end, double cs) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final angle = math.atan2(dy, dx);

    // Scale ladder width relative to cell size
    final halfW = cs * 0.11; // ~11% of cell
    final railW = cs * 0.045;

    canvas.save();
    canvas.translate(start.dx, start.dy);
    canvas.rotate(angle);

    // Shadow
    canvas.save();
    canvas.translate(2, 3);
    _ladderShape(canvas, dist, halfW, railW,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.restore();

    // Wood fill
    final fill = Paint()..color = const Color(0xffb45309)..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xff78350f)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    _ladderShape(canvas, dist, halfW, railW, fill, stroke: stroke);

    canvas.restore();
  }

  void _ladderShape(Canvas canvas, double dist, double halfW, double railW,
      Paint fill, {Paint? stroke}) {
    // Two rails
    for (final yOff in [-halfW, halfW]) {
      final rr = RRect.fromRectAndRadius(
          Rect.fromLTWH(0, yOff - railW / 2, dist, railW),
          const Radius.circular(2));
      canvas.drawRRect(rr, fill);
      if (stroke != null) canvas.drawRRect(rr, stroke);
    }
    // Rungs
    final rungCount = math.max(3, (dist / (halfW * 2.8)).floor());
    final spacing = dist / rungCount;
    final rungW = railW * 0.95;
    for (int i = 1; i < rungCount; i++) {
      final rx = i * spacing;
      final rr = RRect.fromRectAndRadius(
          Rect.fromLTWH(rx - rungW / 2, -halfW, rungW, halfW * 2),
          const Radius.circular(1.5));
      canvas.drawRRect(rr, fill);
      if (stroke != null) canvas.drawRRect(rr, stroke);
    }
  }

  // ── Snake ──────────────────────────────────────────────────────────────
  void _drawSnake(Canvas canvas, Offset head, Offset tail, int idx, double cs) {
    final dx = tail.dx - head.dx;
    final dy = tail.dy - head.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final angle = math.atan2(dy, dx);

    // Scale body radius relative to cell size
    final maxR = cs * 0.155; // head radius
    final minR = cs * 0.065; // tail radius
    // Amplitude of the wave — keep it small so it stays inside the board
    final amp = cs * 0.22;
    final waves = 2 + (idx % 3);
    final segs = (dist / 2.5).floor().clamp(20, 400);

    // Stripe colours cycle per snake
    final colorA = [
      const Color(0xff10b981),
      const Color(0xff3b82f6),
      const Color(0xffec4899),
    ][idx % 3];
    final colorB = [
      const Color(0xfffbbf24),
      const Color(0xff34d399),
      const Color(0xfffbcfe8),
    ][idx % 3];

    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.rotate(angle);

    // ① Shadow pass
    canvas.save();
    canvas.translate(2.5, 3.5);
    for (int i = segs; i >= 0; i--) {
      final t = i / segs;
      final xp = t * dist;
      final yp = math.sin(t * math.pi) * math.sin(t * math.pi * waves) * amp;
      final r = maxR * (1 - t) + minR * t;
      canvas.drawCircle(Offset(xp, yp), r + 1.5,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    }
    canvas.restore();

    // ② Dark outline
    for (int i = segs; i >= 0; i--) {
      final t = i / segs;
      final xp = t * dist;
      final yp = math.sin(t * math.pi) * math.sin(t * math.pi * waves) * amp;
      final r = maxR * (1 - t) + minR * t;
      canvas.drawCircle(Offset(xp, yp), r + 1.5,
          Paint()..color = const Color(0xff064e3b));
    }

    // ③ Striped body
    for (int i = segs; i >= 0; i--) {
      final t = i / segs;
      final xp = t * dist;
      final yp = math.sin(t * math.pi) * math.sin(t * math.pi * waves) * amp;
      final r = maxR * (1 - t) + minR * t;
      canvas.drawCircle(Offset(xp, yp), r,
          Paint()..color = (i % 6) < 3 ? colorA : colorB);
    }

    // ④ Head oval (at t=0, xp=0)
    final headW = maxR * 2.4;
    final headH = maxR * 1.9;
    // Shadow
    canvas.drawOval(
        Rect.fromCenter(center: Offset(-maxR * 0.4, 2.5), width: headW, height: headH),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    // Head fill
    final headRect = Rect.fromCenter(center: Offset(-maxR * 0.35, 0), width: headW, height: headH);
    canvas.drawOval(headRect, Paint()..color = colorA);
    canvas.drawOval(headRect,
        Paint()
          ..color = const Color(0xff064e3b)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // ⑤ Eyes
    final eyeR = maxR * 0.38;
    final eyeX = -maxR * 0.7;
    final eyeYOff = maxR * 0.5;
    canvas.drawCircle(Offset(eyeX, -eyeYOff), eyeR, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(eyeX, eyeYOff), eyeR, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(eyeX - eyeR * 0.2, -eyeYOff), eyeR * 0.55, Paint()..color = Colors.black);
    canvas.drawCircle(Offset(eyeX - eyeR * 0.2, eyeYOff), eyeR * 0.55, Paint()..color = Colors.black);
    // Shine
    canvas.drawCircle(Offset(eyeX + eyeR * 0.1, -eyeYOff - eyeR * 0.2), eyeR * 0.22, Paint()..color = Colors.white70);
    canvas.drawCircle(Offset(eyeX + eyeR * 0.1, eyeYOff - eyeR * 0.2), eyeR * 0.22, Paint()..color = Colors.white70);

    // ⑥ Forked tongue
    final tongueStart = -maxR * 1.5;
    final tongueEnd = -maxR * 2.3;
    final tongueFork = maxR * 0.4;
    final tongue = Path()
      ..moveTo(tongueStart, 0)
      ..lineTo(tongueEnd, 0)
      ..lineTo(tongueEnd - tongueFork * 0.5, -tongueFork)
      ..moveTo(tongueEnd, 0)
      ..lineTo(tongueEnd - tongueFork * 0.5, tongueFork);
    canvas.drawPath(
        tongue,
        Paint()
          ..color = const Color(0xffef4444)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SnakesLaddersBoardPainter oldDelegate) {
    // We should repaint if the board configuration changes.
    // A quick check is whether the maps are identical. 
    // Since they are generated once per game, checking length or just returning true is safest.
    return true; 
  }
}
