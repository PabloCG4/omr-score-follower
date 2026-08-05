import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../score/score_document.dart';
import '../session/cursor_display_model.dart';

/// Draws the tracking cursor on top of a score page. Rebuilds only when its
/// owning [ListenableBuilder] fires (i.e. when [CursorDisplayModel] notifies).
class CursorOverlay extends StatelessWidget {
  const CursorOverlay({
    super.key,
    required this.pose,
    required this.cursorHealth,
    this.isHidden = false,
    this.pulsePhase = 0.0,
  });

  final ScoreCursorPose pose;
  final CursorHealth cursorHealth;
  final bool isHidden;

  /// 0..1 phase for waitingStrict opacity pulse (derived from ticker time).
  final double pulsePhase;

  @override
  Widget build(BuildContext context) {
    if (isHidden) {
      return const SizedBox.expand();
    }
    return CustomPaint(
      painter: CursorOverlayPainter(
        pose: pose,
        cursorHealth: cursorHealth,
        pulsePhase: pulsePhase,
      ),
      child: const SizedBox.expand(),
    );
  }
}

final class CursorOverlayPainter extends CustomPainter {
  CursorOverlayPainter({
    required this.pose,
    required this.cursorHealth,
    required this.pulsePhase,
  });

  final ScoreCursorPose pose;
  final CursorHealth cursorHealth;
  final double pulsePhase;

  @override
  void paint(Canvas canvas, Size size) {
    final x = pose.xNorm.clamp(0.0, 1.0) * size.width;
    final y = pose.yNorm.clamp(0.0, 1.0) * size.height;

    final baseColor = colorForHealth(cursorHealth);
    final opacity = opacityForHealth(cursorHealth, pulsePhase);
    final strokeWidth = cursorHealth == CursorHealth.waitingStrict ? 4.0 : 2.5;

    final barPaint = Paint()
      ..color = baseColor.withValues(alpha: opacity)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Vertical tracking bar spanning most of the staff height around yNorm.
    final barTop = (y - size.height * 0.12).clamp(0.0, size.height);
    final barBottom = (y + size.height * 0.12).clamp(0.0, size.height);
    canvas.drawLine(Offset(x, barTop), Offset(x, barBottom), barPaint);

    final tickPaint = Paint()
      ..color = baseColor.withValues(alpha: opacity)
      ..strokeWidth = strokeWidth * 0.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x - 10.0, y), Offset(x + 10.0, y), tickPaint);

    final headPaint = Paint()
      ..color = baseColor.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, barTop), cursorHealth == CursorHealth.waitingStrict ? 5.5 : 4.0, headPaint);
  }

  Color colorForHealth(CursorHealth health) {
    switch (health) {
      case CursorHealth.healthy:
        return const Color(0xFFC62828);
      case CursorHealth.warning:
        return const Color(0xFFF9A825);
      case CursorHealth.critical:
        return const Color(0xFFC62828);
      case CursorHealth.waitingStrict:
        return const Color(0xFFC62828);
    }
  }

  double opacityForHealth(CursorHealth health, double phase) {
    if (health != CursorHealth.waitingStrict) {
      return 0.88;
    }
    // Pulse between ~0.35 and ~0.95 while Strict is waiting.
    return 0.35 + 0.60 * (0.5 + 0.5 * math.sin(phase * math.pi * 2.0));
  }

  @override
  bool shouldRepaint(covariant CursorOverlayPainter oldDelegate) {
    return oldDelegate.pose != pose ||
        oldDelegate.cursorHealth != cursorHealth ||
        oldDelegate.pulsePhase != pulsePhase;
  }
}
