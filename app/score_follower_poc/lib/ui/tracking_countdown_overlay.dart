import 'package:flutter/material.dart';

/// Full-bleed pre-roll overlay shown while [FollowingSessionController]
/// counts down before live tracking. Keeps the score visible underneath.
class TrackingCountdownOverlay extends StatelessWidget {
  const TrackingCountdownOverlay({
    super.key,
    required this.secondsRemaining,
    required this.isArmingPipeline,
  });

  final int secondsRemaining;
  final bool isArmingPipeline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayValue =
        secondsRemaining > 0 ? secondsRemaining.toString() : 'Go';

    return AbsorbPointer(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Get ready',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                displayValue,
                style: theme.textTheme.displayLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 96,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isArmingPipeline
                    ? 'Warming up microphone…'
                    : 'Tracking starts at zero',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
