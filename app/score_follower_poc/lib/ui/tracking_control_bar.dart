import 'package:flutter/material.dart';

/// Bottom control bar: Previous | Start/Stop | Next.
/// Prev/Next are enabled only when [canNavigateManually] is true.
class TrackingControlBar extends StatelessWidget {
  const TrackingControlBar({
    super.key,
    required this.isRunning,
    required this.isCountingDown,
    required this.canNavigateManually,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.isLoading,
    required this.onStartStop,
    required this.onPrevious,
    required this.onNext,
  });

  final bool isRunning;
  final bool isCountingDown;
  final bool canNavigateManually;
  final bool canGoPrevious;
  final bool canGoNext;
  final bool isLoading;
  final VoidCallback onStartStop;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final startStopLabel = isCountingDown
        ? 'Cancel'
        : (isRunning ? 'Stop' : (isLoading ? 'Loading…' : 'Start'));
    final startStopIcon = isCountingDown
        ? Icons.close
        : (isRunning ? Icons.stop : Icons.play_arrow);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton.filledTonal(
              onPressed: canNavigateManually && canGoPrevious ? onPrevious : null,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous page',
            ),
            FilledButton.icon(
              onPressed: isLoading ? null : onStartStop,
              icon: Icon(startStopIcon),
              label: Text(startStopLabel),
            ),
            IconButton.filledTonal(
              onPressed: canNavigateManually && canGoNext ? onNext : null,
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next page',
            ),
          ],
        ),
      ),
    );
  }
}
