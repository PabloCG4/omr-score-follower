import 'package:flutter/material.dart';

import '../score/score_document.dart';

/// Draws the tracking cursor on top of a score page. Rebuilds only when its
/// owning [ListenableBuilder] fires (i.e. when [CursorDisplayModel] notifies).
class CursorOverlay extends StatelessWidget {
  const CursorOverlay({
    super.key,
    required this.pose,
    this.isHidden = false,
  });

  final ScoreCursorPose pose;
  final bool isHidden;

  @override
  Widget build(BuildContext context) {
    if (isHidden) {
      return const SizedBox.expand();
    }
    return CustomPaint(
      painter: CursorOverlayPainter(pose: pose),
      child: const SizedBox.expand(),
    );
  }
}

final class CursorOverlayPainter extends CustomPainter {
  CursorOverlayPainter({required this.pose});

  final ScoreCursorPose pose;

  @override
  void paint(Canvas canvas, Size size) {
    final x = pose.xNorm.clamp(0.0, 1.0) * size.width;
    final y = pose.yNorm.clamp(0.0, 1.0) * size.height;

    final barPaint = Paint()
      ..color = const Color(0xE0C62828)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Vertical tracking bar spanning most of the staff height around yNorm.
    final barTop = (y - size.height * 0.12).clamp(0.0, size.height);
    final barBottom = (y + size.height * 0.12).clamp(0.0, size.height);
    canvas.drawLine(Offset(x, barTop), Offset(x, barBottom), barPaint);

    final tickPaint = Paint()
      ..color = const Color(0xE0C62828)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x - 10.0, y), Offset(x + 10.0, y), tickPaint);

    final headPaint = Paint()
      ..color = const Color(0xE0C62828)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, barTop), 4.0, headPaint);
  }

  @override
  bool shouldRepaint(covariant CursorOverlayPainter oldDelegate) {
    return oldDelegate.pose != pose;
  }
}
