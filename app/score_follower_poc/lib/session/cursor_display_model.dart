import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../score/score_document.dart';
import '../score/score_timeline_mapper.dart';

/// Vsync-driven cursor display state. Chases [targetFrameIndex] in
/// reference-frame space with an exponential time-constant, then remaps to a
/// [ScoreCursorPose]. Only the cursor overlay should listen to this model so
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
  double targetFrameIndex = 0.0;
  double displayedFrameIndex = 0.0;
  ScoreCursorPose displayedPose = ScoreCursorPose.origin;

  /// When true, interpolation is frozen and the overlay should hide the
  /// cursor so page-relative coordinates of page N+1 are never drawn on top
  /// of page N during a PageView transition.
  bool isPageTransitionInProgress = false;

  bool isRunning = false;

  void attachScoreDocument(ScoreDocument document) {
    scoreDocument = document;
    targetFrameIndex = 0.0;
    displayedFrameIndex = 0.0;
    displayedPose = mapper.mapFrameIndex(document, 0.0);
    notifyListeners();
  }

  void setTargetFrameIndex(double frameIndex) {
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

  /// Immediately aligns display and target (used by the offline frame scrubber).
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
    ticker.start();
  }

  void stop() {
    if (!isRunning) {
      return;
    }
    isRunning = false;
    ticker.stop();
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
  }

  Duration? lastElapsed;

  @override
  void dispose() {
    ticker.dispose();
    super.dispose();
  }
}
