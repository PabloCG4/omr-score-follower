import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../session/alignment_snapshot.dart';

/// Linear confidence meter driven solely by [alignmentSnapshot] so the score
/// SVG never rebuilds when confidence changes.
class ConfidenceBar extends StatelessWidget {
  const ConfidenceBar({
    super.key,
    required this.alignmentSnapshot,
    required this.isRunning,
    this.warningThreshold = 0.55,
    this.criticalThreshold = 0.35,
  });

  final ValueListenable<AlignmentSnapshot> alignmentSnapshot;
  final bool isRunning;
  final double warningThreshold;
  final double criticalThreshold;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AlignmentSnapshot>(
      valueListenable: alignmentSnapshot,
      builder: (context, snapshot, child) {
        final confidence =
            isRunning ? snapshot.alignmentConfidence.clamp(0.0, 1.0) : 0.0;
        final color = colorForConfidence(confidence);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Confidence',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const Spacer(),
                Text(
                  isRunning ? confidence.toStringAsFixed(2) : '--',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: confidence,
                minHeight: 8,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                color: color,
              ),
            ),
          ],
        );
      },
    );
  }

  Color colorForConfidence(double confidence) {
    if (confidence >= warningThreshold) {
      return const Color(0xFF2E7D32); // green
    }
    if (confidence >= criticalThreshold) {
      return const Color(0xFFF9A825); // amber
    }
    return const Color(0xFFC62828); // red
  }
}
