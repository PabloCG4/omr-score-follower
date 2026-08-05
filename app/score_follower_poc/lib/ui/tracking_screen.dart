import 'package:flutter/material.dart';

import '../config/tracking_mode.dart';
import '../config/tracking_session_config.dart';
import '../session/alignment_snapshot.dart';
import '../session/cursor_display_model.dart';
import '../session/following_session_controller.dart';
import 'confidence_bar.dart';
import 'score_viewport.dart';
import 'tracking_control_bar.dart';

/// Tracking shell: score viewport, confidence bar, and Start/Stop controls.
/// Receives an immutable [TrackingSessionConfig] from [InitialConfigScreen].
class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key, required this.config});

  final TrackingSessionConfig config;

  @override
  State<TrackingScreen> createState() => TrackingScreenState();
}

class TrackingScreenState extends State<TrackingScreen>
    with SingleTickerProviderStateMixin {
  late final CursorDisplayModel cursorDisplayModel;
  late final FollowingSessionController sessionController;
  bool showFrameScrubber = false;

  @override
  void initState() {
    super.initState();
    cursorDisplayModel = CursorDisplayModel(tickerProvider: this);
    sessionController = FollowingSessionController(
      cursorDisplayModel: cursorDisplayModel,
      sessionConfig: widget.config,
    );
    sessionController.loadScore();
  }

  @override
  void dispose() {
    sessionController.dispose();
    cursorDisplayModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sessionController,
      builder: (context, child) {
        final document = sessionController.scoreDocument;
        final maxFrame = document == null
            ? 0.0
            : document.anchors.last.frameIndex.toDouble();
        final pageCount = document?.pages.length ?? 0;
        final title = document?.displayTitle ?? 'Score Follower';
        final modeLabel = widget.config.trackingMode.displayLabel;

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Center(
                  child: Text(
                    modeLabel,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Toggle frame scrubber',
                onPressed: () {
                  setState(() {
                    showFrameScrubber = !showFrameScrubber;
                  });
                },
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ScoreViewport(
                    sessionController: sessionController,
                    cursorDisplayModel: cursorDisplayModel,
                  ),
                ),
              ),
              if (showFrameScrubber && document != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    children: [
                      const Text('Scrub'),
                      Expanded(
                        child: Slider(
                          min: 0.0,
                          max: maxFrame,
                          value: cursorDisplayModel.targetFrameIndex
                              .clamp(0.0, maxFrame)
                              .toDouble(),
                          onChanged: sessionController.canNavigateManually
                              ? (value) {
                                  sessionController.scrubToFrameIndex(value);
                                  setState(() {});
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 4.0),
                child: ConfidenceBar(
                  alignmentSnapshot: sessionController.alignmentSnapshot,
                  isRunning: sessionController.isRunning,
                  warningThreshold: widget.config.strictConfidenceThreshold,
                  criticalThreshold: 0.35,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24.0, 4.0, 24.0, 8.0),
                child: ValueListenableBuilder<AlignmentSnapshot>(
                  valueListenable: sessionController.alignmentSnapshot,
                  builder: (context, snapshot, child) {
                    return Text(
                      'frame=${snapshot.referenceFrameIndex.toStringAsFixed(2)}  '
                      'conf=${snapshot.alignmentConfidence.toStringAsFixed(3)}  '
                      'cost=${snapshot.cumulativeDistortionCost.toStringAsFixed(3)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    );
                  },
                ),
              ),
              if (sessionController.lastErrorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    sessionController.lastErrorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              TrackingControlBar(
                isRunning: sessionController.isRunning,
                canNavigateManually: sessionController.canNavigateManually,
                canGoPrevious: sessionController.currentPageIndex > 0,
                canGoNext: pageCount > 0 &&
                    sessionController.currentPageIndex < pageCount - 1,
                isLoading: sessionController.isLoadingScore,
                onStartStop: () {
                  if (sessionController.isRunning) {
                    sessionController.stop();
                  } else {
                    sessionController.start();
                  }
                },
                onPrevious: sessionController.goToPreviousPage,
                onNext: sessionController.goToNextPage,
              ),
            ],
          ),
        );
      },
    );
  }
}
