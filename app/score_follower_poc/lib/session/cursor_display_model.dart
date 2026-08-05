import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../config/tracking_mode.dart';
import '../score/score_document.dart';
import '../score/score_timeline_mapper.dart';

/// Visual health of the tracking cursor, derived from alignment confidence
/// and [TrackingMode].
enum CursorHealth {
  healthy,
  warning,
  critical,
  waitingStrict,
}

/// Vsync-driven cursor display state. Chases [targetFrameIndex] in
/// reference-frame space with an exponential time-constant, then remaps to a
/// [ScoreCursorPose]. In [TrackingMode.fixedTempo], advances the target by
/// wall-clock against the score's authored seconds-per-frame instead of
/// chasing DSP polls. Only the cursor overlay should listen to this model so
/// the static score page never rebuilds at 60 Hz.
final class CursorDisplayModel extends ChangeNotifier {
  CursorDisplayModel({
    required TickerProvider tickerProvider,
    this.mapper = const ScoreTimelineMapper(),
    this.chaseTimeConstantSeconds = 0.05,
    this.pageChangeSnapThresholdFrames = 0.5,
  }) {
    ticker = tickerProvider.createTicker(onTick);
  }

  final ScoreTimelineMapper mapper;

  /// Exponential chase time-constant (tau). ~50 ms yields one visual
  /// time-constant of smoothing between discrete DSP polls.
  final double chaseTimeConstantSeconds;

  /// Absolute frame-index delta beyond which the display snaps immediately
  /// (large jumps / page changes), rather than gliding across the wrong page.
  final double pageChangeSnapThresholdFrames;

  late final Ticker ticker;

  ScoreDocument? scoreDocument;
  TrackingMode trackingMode = TrackingMode.rubato;
  double referenceSecondsPerFrame = 512.0 / 22050.0;
  double strictConfidenceThreshold = 0.55;

  double targetFrameIndex = 0.0;
  double displayedFrameIndex = 0.0;
  ScoreCursorPose displayedPose = ScoreCursorPose.origin;
  CursorHealth cursorHealth = CursorHealth.healthy;

  /// When true, interpolation is frozen and the overlay should hide the
  /// cursor so page-relative coordinates of page N+1 are never drawn on top
  /// of page N during a PageView transition.
  bool isPageTransitionInProgress = false;

  bool isRunning = false;

  void attachScoreDocument(ScoreDocument document) {
    scoreDocument = document;
    // Explicit double division: hop/sampleRate is the authored seconds per
    // reference frame (e.g. 512/22050 ≈ 23.2 ms). Inverting this would race
    // the Fixed Tempo cursor by a factor of ~sampleRate.
    referenceSecondsPerFrame =
        document.hopLengthSamples.toDouble() / document.sampleRateHz;
    targetFrameIndex = 0.0;
    displayedFrameIndex = 0.0;
    displayedPose = mapper.mapFrameIndex(document, 0.0);
    cursorHealth = CursorHealth.healthy;
    notifyListeners();
  }

  void setTrackingMode(TrackingMode mode) {
    if (trackingMode == mode) {
      return;
    }
    trackingMode = mode;
    notifyListeners();
  }

  void setStrictConfidenceThreshold(double threshold) {
    strictConfidenceThreshold = threshold.clamp(0.0, 1.0);
  }

  /// Updates health from the latest alignment confidence. Called by the
  /// session poll so the overlay can recolor without rebuilding the SVG.
  void updateCursorHealth({
    required double alignmentConfidence,
    required bool sessionIsRunning,
  }) {
    const warningBandFloor = 0.35;
    final CursorHealth next;
    if (!sessionIsRunning) {
      next = CursorHealth.healthy;
    } else if (trackingMode == TrackingMode.strict &&
        alignmentConfidence < strictConfidenceThreshold) {
      next = CursorHealth.waitingStrict;
    } else if (alignmentConfidence < warningBandFloor) {
      next = CursorHealth.critical;
    } else if (alignmentConfidence < strictConfidenceThreshold) {
      next = CursorHealth.warning;
    } else {
      next = CursorHealth.healthy;
    }
    if (next == cursorHealth) {
      return;
    }
    cursorHealth = next;
    notifyListeners();
  }

  /// Applies a DSP poll target. Always ignored in Fixed Tempo: the wall-clock
  /// frame clock owns cursor motion regardless of whether the session ticker
  /// has started yet (avoids a race where an early poll could leap the cursor).
  void setTargetFrameIndex(double frameIndex) {
    if (trackingMode == TrackingMode.fixedTempo) {
      return;
    }
    targetFrameIndex = frameIndex;
    final document = scoreDocument;
    if (document == null) {
      return;
    }

    final targetPose = mapper.mapFrameIndex(document, frameIndex);
    final pageChanged = targetPose.pageIndex != displayedPose.pageIndex;
    final jumpMagnitude = (frameIndex - displayedFrameIndex).abs();
    // Snap on page changes or pathological jumps so the chase never glides
    // across the wrong page or teleports slowly across the whole score.
    if (pageChanged || jumpMagnitude >= pageChangeSnapThresholdFrames * 50.0) {
      displayedFrameIndex = frameIndex;
      displayedPose = targetPose;
      notifyListeners();
    }
  }

  /// Immediately aligns display and target (used by seek / scrub / Fixed Tempo seed).
  void snapToFrameIndex(double frameIndex) {
    targetFrameIndex = frameIndex;
    displayedFrameIndex = frameIndex;
    final document = scoreDocument;
    if (document != null) {
      displayedPose = mapper.mapFrameIndex(document, frameIndex);
    }
    notifyListeners();
  }

  /// Called by the session when the PageView begins or ends a page animation.
  void setPageTransitionInProgress(bool inProgress) {
    if (isPageTransitionInProgress == inProgress) {
      return;
    }
    isPageTransitionInProgress = inProgress;
    if (!inProgress) {
      // Snap onto the latest target once the destination page is fully visible.
      displayedFrameIndex = targetFrameIndex;
      final document = scoreDocument;
      if (document != null) {
        displayedPose = mapper.mapFrameIndex(document, displayedFrameIndex);
      }
    }
    notifyListeners();
  }

  void start() {
    if (isRunning) {
      return;
    }
    isRunning = true;
    lastElapsed = null;
    ticker.start();
  }

  void stop() {
    if (!isRunning) {
      return;
    }
    isRunning = false;
    ticker.stop();
    lastElapsed = null;
  }

  void onTick(Duration elapsed) {
    // Ticker does not hand us dt directly across callbacks without tracking
    // the previous elapsed time; derive a clamped dt from successive ticks.
    final previousElapsed = lastElapsed;
    lastElapsed = elapsed;
    if (previousElapsed == null) {
      return;
    }

    var deltaSeconds = (elapsed - previousElapsed).inMicroseconds / 1e6;
    if (deltaSeconds <= 0.0) {
      return;
    }
    // Clamp pathological frame spikes (app resume, debugger pauses).
    deltaSeconds = math.min(deltaSeconds, 0.05);

    if (isPageTransitionInProgress || scoreDocument == null) {
      return;
    }

    final document = scoreDocument!;
    final maxFrameIndex = (document.referenceFrameCount > 0)
        ? (document.referenceFrameCount - 1).toDouble()
        : document.anchors.last.frameIndex.toDouble();

    if (trackingMode == TrackingMode.fixedTempo && isRunning) {
      // framesAdvanced = dtSeconds / secondsPerFrame.
      // Example: dt=1/60, spf=512/22050 → ~0.72 frames per vsync ≈ 43 fps.
      final secondsPerFrame = referenceSecondsPerFrame > 1e-9
          ? referenceSecondsPerFrame
          : (document.hopLengthSamples.toDouble() / document.sampleRateHz);
      final framesAdvanced = deltaSeconds / secondsPerFrame;
      targetFrameIndex =
          (targetFrameIndex + framesAdvanced).clamp(0.0, maxFrameIndex);
    }

    final targetPose = mapper.mapFrameIndex(document, targetFrameIndex);
    if (targetPose.pageIndex != displayedPose.pageIndex) {
      // Page change detected mid-tick: snap; the session controller is
      // responsible for driving the PageView and suspending via
      // setPageTransitionInProgress during the animation.
      displayedFrameIndex = targetFrameIndex;
      displayedPose = targetPose;
      notifyListeners();
      return;
    }

    final alpha = 1.0 - math.exp(-deltaSeconds / chaseTimeConstantSeconds);
    displayedFrameIndex += (targetFrameIndex - displayedFrameIndex) * alpha;
    final newPose = mapper.mapFrameIndex(document, displayedFrameIndex);
    if (newPose != displayedPose) {
      displayedPose = newPose;
      notifyListeners();
    }

    // Pulse waitingStrict by notifying each tick so opacity can animate.
    if (cursorHealth == CursorHealth.waitingStrict) {
      notifyListeners();
    }
  }

  Duration? lastElapsed;

  /// 0..1 phase for waitingStrict opacity pulse, driven by the vsync ticker.
  double get pulsePhase {
    final elapsed = lastElapsed;
    if (elapsed == null) {
      return 0.0;
    }
    const periodSeconds = 0.9;
    final seconds = elapsed.inMicroseconds / 1e6;
    return (seconds % periodSeconds) / periodSeconds;
  }

  @override
  void dispose() {
    ticker.dispose();
    super.dispose();
  }
}
