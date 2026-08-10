import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:score_follower_bridge/score_follower_bridge.dart';

import '../config/tracking_mode.dart';
import '../config/tracking_session_config.dart';
import '../score/score_document.dart';
import '../score/score_document_loader.dart';
import '../score/score_timeline_mapper.dart';
import '../score/score_visual_document.dart';
import '../score/score_visual_document_loader.dart';
import 'alignment_snapshot.dart';
import 'cursor_display_model.dart';

/// Low-frequency session lifecycle: score load, Start/Stop, engine/mic/isolate
/// ownership, page navigation, and seek. High-frequency alignment updates go
/// through [alignmentSnapshot] and [cursorDisplayModel].
final class FollowingSessionController extends ChangeNotifier {
  FollowingSessionController({
    required this.cursorDisplayModel,
    required this.sessionConfig,
    required this.scoreVisualDocumentLoader,
    ScoreDocumentLoader? scoreDocumentLoader,
    AudioRecorder? audioRecorder,
    this.timelineMapper = const ScoreTimelineMapper(),
  })  : scoreDocumentLoader = scoreDocumentLoader ?? ScoreDocumentLoader(),
        audioRecorder = audioRecorder ?? AudioRecorder();

  final CursorDisplayModel cursorDisplayModel;
  final TrackingSessionConfig sessionConfig;
  final ScoreDocumentLoader scoreDocumentLoader;
  final ScoreVisualDocumentLoader scoreVisualDocumentLoader;
  final AudioRecorder audioRecorder;
  final ScoreTimelineMapper timelineMapper;

  /// High-frequency DSP poll channel (~30 Hz).
  final ValueNotifier<AlignmentSnapshot> alignmentSnapshot =
      ValueNotifier<AlignmentSnapshot>(AlignmentSnapshot.zero);

  ScoreDocument? scoreDocument;

  /// Practice PDF for [ScoreViewport]. Geometry/anchors live on [scoreDocument]
  /// (structural JSON or demo pack); the PDF supplies page rasters only.
  ScoreVisualDocument? scoreVisualDocument;

  bool isRunning = false;
  bool isCountingDown = false;
  bool isLoadingScore = false;
  bool isLoadingVisualDocument = false;
  bool isArmingCapturePipeline = false;
  int countdownSecondsRemaining = 0;
  int currentPageIndex = 0;
  String? lastErrorMessage;
  String? lastWarningMessage;

  /// Frame index captured when Start was pressed; re-applied at countdown 0
  /// so ambient audio during the pre-roll cannot leave the DTW mid-score.
  double resumeFrameIndex = 0.0;

  ScoreFollowerEngine? engine;
  StreamSubscription<Uint8List>? audioStreamSubscription;
  Isolate? audioPushIsolate;
  Timer? uiPollingTimer;
  Timer? countdownTimer;
  bool capturePipelineReady = false;

  static const int preRollCountdownSeconds = 2;

  TrackingMode get trackingMode => sessionConfig.trackingMode;

  /// True while counting down or actively tracking (mic owned, nav gated).
  bool get isSessionActive => isCountingDown || isRunning;

  bool get canNavigateManually =>
      !isSessionActive && scoreVisualDocument != null;

  bool get isLoadingSessionDocuments =>
      isLoadingScore || isLoadingVisualDocument;

  int get visualPageCount => scoreVisualDocument?.pageCount ?? 0;

  String get practiceDisplayTitle =>
      scoreVisualDocument?.displayTitle ??
      scoreDocument?.displayTitle ??
      'Score Follower';

  /// Loads tracking geometry/chromagram and practice PDF for the selected score.
  ///
  /// Reference chromagram floats are injected via the existing FFI
  /// [ScoreFollowerEngine.loadReferenceChromagram] path. Live microphone → CQT
  /// feature extraction is unchanged until D.3.
  Future<void> loadSessionDocuments() async {
    lastWarningMessage = null;
    await Future.wait<void>([
      loadScore(),
      loadScoreVisual(),
    ]);
    notePageCountMismatchIfNeeded();
  }

  /// Loads [sessionConfig.scoreId] into [scoreDocument] and the native engine.
  Future<void> loadScore({String? scoreId}) async {
    isLoadingScore = true;
    lastErrorMessage = null;
    notifyListeners();
    try {
      await tearDownCapturePipeline();
      destroyEngine();

      final document = await scoreDocumentLoader.loadForScoreId(
        scoreId ?? sessionConfig.scoreId,
      );
      scoreDocument = document;
      currentPageIndex = clampPageIndexToVisualBounds(0);
      cursorDisplayModel.attachScoreDocument(document);
      ensureEngineLoaded(document);
      applyTrackingModeToEngineAndCursor();
      seekNativeAndUi(0.0, notifyPage: true);
    } catch (error) {
      final message = error is ScoreDocumentLoadException
          ? error.message
          : error.toString();
      lastErrorMessage = message;
    } finally {
      isLoadingScore = false;
      notifyListeners();
    }
  }

  /// Opens the practice PDF for [sessionConfig.scoreId] (demo asset or
  /// persisted `original.pdf`).
  Future<void> loadScoreVisual({String? scoreId}) async {
    isLoadingVisualDocument = true;
    notifyListeners();
    try {
      final previous = scoreVisualDocument;
      scoreVisualDocument = null;
      if (previous != null) {
        await previous.dispose();
      }

      final document = await scoreVisualDocumentLoader.load(
        scoreId ?? sessionConfig.scoreId,
      );
      scoreVisualDocument = document;
      currentPageIndex = clampPageIndexToVisualBounds(0);
    } catch (error) {
      final message = error is ScoreVisualDocumentException
          ? error.message
          : error.toString();
      lastErrorMessage = message;
    } finally {
      isLoadingVisualDocument = false;
      notifyListeners();
    }
  }

  /// Surfaces a non-fatal note when PDF page count and structural pages differ.
  void notePageCountMismatchIfNeeded() {
    final tracking = scoreDocument;
    final visual = scoreVisualDocument;
    if (tracking == null || visual == null) {
      return;
    }
    if (tracking.pages.length == visual.pageCount) {
      return;
    }
    lastWarningMessage =
        'PDF has ${visual.pageCount} page(s) but structural data has '
        '${tracking.pages.length} page(s). Cursor mapping follows structural '
        'anchors; re-import if pages look wrong.';
    notifyListeners();
  }

  /// Clamps [pageIndex] to the practice PDF page range when a visual document
  /// is loaded, preventing PageView jumps to invalid indices.
  int clampPageIndexToVisualBounds(int pageIndex) {
    final visualCount = visualPageCount;
    if (visualCount <= 0) {
      return pageIndex < 0 ? 0 : pageIndex;
    }
    return pageIndex.clamp(0, visualCount - 1);
  }

  /// Pushes [sessionConfig] into the native engine and [cursorDisplayModel].
  void applyTrackingModeToEngineAndCursor() {
    cursorDisplayModel.setTrackingMode(sessionConfig.trackingMode);
    cursorDisplayModel.setStrictConfidenceThreshold(
      sessionConfig.strictConfidenceThreshold,
    );
    final liveEngine = engine;
    if (liveEngine == null) {
      return;
    }
    // Explicit enum map onto C ABI integers (rubato=0, strict=1, fixedTempo=2).
    final ScoreFollowerTrackingMode nativeMode;
    switch (sessionConfig.trackingMode) {
      case TrackingMode.rubato:
        nativeMode = ScoreFollowerTrackingMode.rubato;
        break;
      case TrackingMode.strict:
        nativeMode = ScoreFollowerTrackingMode.strict;
        break;
      case TrackingMode.fixedTempo:
        // Native alignment stays Rubato-equivalent; Dart owns the cursor.
        nativeMode = ScoreFollowerTrackingMode.fixedTempo;
        break;
    }
    liveEngine.setTrackingMode(nativeMode);
    liveEngine.setStrictConfidenceThreshold(sessionConfig.strictConfidenceThreshold);
  }

  /// Arms the capture pipeline and begins a [preRollCountdownSeconds]
  /// countdown so the performer can prepare. Live cursor tracking starts
  /// only when the countdown reaches zero and the mic/isolate are ready.
  Future<void> start() async {
    if (isSessionActive || isArmingCapturePipeline) {
      return;
    }
    lastErrorMessage = null;
    resumeFrameIndex = cursorDisplayModel.displayedFrameIndex;
    capturePipelineReady = false;
    isCountingDown = true;
    countdownSecondsRemaining = preRollCountdownSeconds;
    isArmingCapturePipeline = true;
    notifyListeners();

    countdownTimer?.cancel();
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (countdownSecondsRemaining <= 1) {
        countdownTimer?.cancel();
        countdownTimer = null;
        countdownSecondsRemaining = 0;
        notifyListeners();
        tryBeginLiveTracking();
        return;
      }
      countdownSecondsRemaining -= 1;
      notifyListeners();
    });

    try {
      await armCapturePipeline();
      capturePipelineReady = true;
      isArmingCapturePipeline = false;
      notifyListeners();
      tryBeginLiveTracking();
    } catch (error) {
      isArmingCapturePipeline = false;
      await cancelPreRollAndPipeline();
      lastErrorMessage = error.toString();
      notifyListeners();
    }
  }

  /// Opens mic + push isolate + poll timer, but does not start the cursor
  /// clock or treat DSP frames as live tracking targets yet. Starting the
  /// OS audio device during the countdown removes device-open latency from
  /// the critical path at countdown zero.
  Future<void> armCapturePipeline() async {
    if (scoreDocument == null) {
      await loadScore();
    }
    final document = scoreDocument;
    if (document == null) {
      throw StateError('No score document loaded.');
    }

    if (!await audioRecorder.hasPermission()) {
      throw StateError('Microphone permission was denied.');
    }

    ensureEngineLoaded(document);
    applyTrackingModeToEngineAndCursor();
    final liveEngine = engine!;
    liveEngine.seekToReferenceFrame(resumeFrameIndex);
    cursorDisplayModel.snapToFrameIndex(resumeFrameIndex);

    final pushIsolateReadyPort = ReceivePort();
    final createdIsolate = await Isolate.spawn(
      audioPushIsolateEntryPoint,
      AudioPushIsolateStartupMessage(
        readyPort: pushIsolateReadyPort.sendPort,
        channelDescriptor: liveEngine.audioPushChannel,
      ),
    );
    final audioPushSendPort = await pushIsolateReadyPort.first as SendPort;
    pushIsolateReadyPort.close();

    final audioStream = await audioRecorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: document.sampleRateHz.toInt(),
        numChannels: 1,
        // Prefer the lowest practical buffer so the first post-countdown
        // chroma arrives promptly once the hop-primed CQT emits.
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
    final createdSubscription = audioStream.listen(audioPushSendPort.send);

    final createdPollingTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      onAlignmentPollTick(document);
    });

    audioPushIsolate = createdIsolate;
    audioStreamSubscription = createdSubscription;
    uiPollingTimer = createdPollingTimer;
  }

  void onAlignmentPollTick(ScoreDocument document) {
    final pollingEngine = engine;
    if (pollingEngine == null) {
      return;
    }
    final position = pollingEngine.getCurrentAlignmentPosition();
    alignmentSnapshot.value = AlignmentSnapshot(
      position: position,
      polledAt: DateTime.now(),
    );

    // During the pre-roll countdown the mic is already feeding the DSP so
    // the CQT history and OS capture path are warm, but the cursor must not
    // follow ambient noise or Fixed Tempo wall-clock yet.
    if (!isRunning) {
      return;
    }

    cursorDisplayModel.updateCursorHealth(
      alignmentConfidence: position.alignmentConfidence,
      sessionIsRunning: true,
    );

    if (sessionConfig.trackingMode != TrackingMode.fixedTempo) {
      cursorDisplayModel.setTargetFrameIndex(position.referenceFrameIndex);
      final mappedPage = clampPageIndexToVisualBounds(
        timelineMapper
            .mapFrameIndex(document, position.referenceFrameIndex)
            .pageIndex,
      );
      if (mappedPage != currentPageIndex) {
        currentPageIndex = mappedPage;
        notifyListeners();
      }
    } else {
      final mappedPage = clampPageIndexToVisualBounds(
        timelineMapper
            .mapFrameIndex(document, cursorDisplayModel.targetFrameIndex)
            .pageIndex,
      );
      if (mappedPage != currentPageIndex) {
        currentPageIndex = mappedPage;
        notifyListeners();
      }
    }
  }

  /// Transitions from pre-roll to live tracking once both the countdown has
  /// elapsed and the capture pipeline is armed.
  void tryBeginLiveTracking() {
    if (isRunning) {
      return;
    }
    if (countdownSecondsRemaining > 0) {
      return;
    }
    if (!capturePipelineReady) {
      return;
    }

    final liveEngine = engine;
    if (liveEngine == null) {
      return;
    }

    // Clear any DTW path formed by ambient audio during the countdown and
    // re-seed the feature extractor; with hop-timed zero-padded CQT the
    // first live chroma arrives within one hop (~23 ms), not seconds.
    liveEngine.seekToReferenceFrame(resumeFrameIndex);
    cursorDisplayModel.snapToFrameIndex(resumeFrameIndex);
    alignmentSnapshot.value = AlignmentSnapshot(
      position: ScoreFollowerAlignmentPosition(
        referenceFrameIndex: resumeFrameIndex,
        alignmentConfidence: 0.0,
        cumulativeDistortionCost: 0.0,
      ),
      polledAt: DateTime.now(),
    );

    isCountingDown = false;
    isRunning = true;
    cursorDisplayModel.start();
    notifyListeners();
  }

  Future<void> cancelPreRollAndPipeline() async {
    countdownTimer?.cancel();
    countdownTimer = null;
    isCountingDown = false;
    countdownSecondsRemaining = 0;
    capturePipelineReady = false;
    isArmingCapturePipeline = false;
    await tearDownCapturePipeline();
    cursorDisplayModel.stop();
    isRunning = false;
  }

  Future<void> stop() async {
    await cancelPreRollAndPipeline();
    cursorDisplayModel.updateCursorHealth(
      alignmentConfidence: alignmentSnapshot.value.alignmentConfidence,
      sessionIsRunning: false,
    );
    // Keep engine and cursor/seek position; do not zero the diagnostics strip
    // to the zero frame — leave the last known / sought position visible.
    notifyListeners();
  }

  /// Manual page browse. Enabled only when [canNavigateManually]. Does not
  /// seek the native engine; visual browsing only.
  void goToPage(int pageIndex) {
    if (!canNavigateManually) {
      return;
    }
    final visual = scoreVisualDocument;
    if (visual == null || visual.pageCount == 0) {
      return;
    }
    final clamped = clampPageIndexToVisualBounds(pageIndex);
    if (clamped == currentPageIndex) {
      return;
    }
    currentPageIndex = clamped;
    notifyListeners();
  }

  /// Called by [ScoreViewport] when the user finishes a manual swipe so the
  /// session's page index stays in sync without re-triggering animation.
  void adoptPageIndexFromViewport(int pageIndex) {
    if (!canNavigateManually) {
      return;
    }
    final clamped = clampPageIndexToVisualBounds(pageIndex);
    if (currentPageIndex == clamped) {
      return;
    }
    currentPageIndex = clamped;
    notifyListeners();
  }

  void goToPreviousPage() => goToPage(currentPageIndex - 1);

  void goToNextPage() => goToPage(currentPageIndex + 1);

  /// Snap UI cursor and native ODTW window to [frameIndex]. Rejected while
  /// tracking so live audio cannot fight a mid-performance teleport.
  void seekToFrameIndex(double frameIndex) {
    if (!canNavigateManually) {
      return;
    }
    seekNativeAndUi(frameIndex, notifyPage: true);
  }

  /// Dev scrubber and tap-to-seek share this path.
  void scrubToFrameIndex(double frameIndex) {
    seekToFrameIndex(frameIndex);
  }

  void onPageTransitionChanged(bool inProgress) {
    cursorDisplayModel.setPageTransitionInProgress(inProgress);
  }

  /// Handles a tap in page-local pixels on the letterboxed page of size
  /// [pageSize], converting to normalized coordinates then seeking.
  void onScorePageTapped({
    required int pageIndex,
    required Offset localPosition,
    required Size pageSize,
  }) {
    if (!canNavigateManually || pageSize.width <= 0 || pageSize.height <= 0) {
      return;
    }
    final document = scoreDocument;
    if (document == null) {
      return;
    }
    final xNorm = (localPosition.dx / pageSize.width).clamp(0.0, 1.0);
    final yNorm = (localPosition.dy / pageSize.height).clamp(0.0, 1.0);
    final frameIndex = timelineMapper.mapTapToFrameIndex(
      document: document,
      pageIndex: pageIndex,
      xNorm: xNorm,
      yNorm: yNorm,
    );
    seekNativeAndUi(
      frameIndex,
      notifyPage: true,
      preferredPageIndex: pageIndex,
    );
  }

  void ensureEngineLoaded(ScoreDocument document) {
    if (engine != null) {
      return;
    }
    final created = ScoreFollowerEngine.create(
      sampleRateHz: document.sampleRateHz,
      hopLengthSamples: document.hopLengthSamples,
    );
    created.loadReferenceChromagram(
      pitchClassEnergiesRowMajor: document.referenceChromagramAsDoubles,
      frameCount: document.referenceFrameCount,
      sampleRateHz: document.sampleRateHz,
      hopLengthSamples: document.hopLengthSamples,
    );
    // Apply instrument A4 + transposition once at prepare time. Seek/reset
    // must preserve CQT kernels and the latched chroma rotation; do not
    // call setTuning again after seekToReferenceFrame.
    created.setTuning(
      a4FrequencyHz: sessionConfig.baseFrequencyHz,
      transpositionSemitones: sessionConfig.transpositionSemitones,
    );
    engine = created;
  }

  void seekNativeAndUi(
    double frameIndex, {
    required bool notifyPage,
    int? preferredPageIndex,
  }) {
    final document = scoreDocument;
    cursorDisplayModel.snapToFrameIndex(frameIndex);

    if (notifyPage) {
      if (preferredPageIndex != null) {
        currentPageIndex = clampPageIndexToVisualBounds(preferredPageIndex);
      } else if (document != null) {
        final mappedPage = clampPageIndexToVisualBounds(
          timelineMapper.mapFrameIndex(document, frameIndex).pageIndex,
        );
        if (mappedPage != currentPageIndex) {
          currentPageIndex = mappedPage;
        }
      }
    }

    alignmentSnapshot.value = AlignmentSnapshot(
      position: ScoreFollowerAlignmentPosition(
        referenceFrameIndex: frameIndex,
        alignmentConfidence: 0.0,
        cumulativeDistortionCost: 0.0,
      ),
      polledAt: DateTime.now(),
    );
    cursorDisplayModel.updateCursorHealth(
      alignmentConfidence: 0.0,
      sessionIsRunning: isRunning,
    );

    final liveEngine = engine;
    if (liveEngine != null) {
      liveEngine.seekToReferenceFrame(frameIndex);
    }
    notifyListeners();
  }

  Future<void> tearDownCapturePipeline() async {
    uiPollingTimer?.cancel();
    uiPollingTimer = null;

    await audioStreamSubscription?.cancel();
    audioStreamSubscription = null;

    if (await audioRecorder.isRecording()) {
      await audioRecorder.stop();
    }

    audioPushIsolate?.kill(priority: Isolate.immediate);
    audioPushIsolate = null;
  }

  void destroyEngine() {
    engine?.dispose();
    engine = null;
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    countdownTimer = null;
    unawaited(tearDownCapturePipeline());
    destroyEngine();
    final visual = scoreVisualDocument;
    scoreVisualDocument = null;
    if (visual != null) {
      unawaited(visual.dispose());
    }
    cursorDisplayModel.stop();
    isRunning = false;
    isCountingDown = false;
    unawaited(() async {
      if (await audioRecorder.isRecording()) {
        await audioRecorder.stop();
      }
      audioRecorder.dispose();
    }());
    alignmentSnapshot.dispose();
    super.dispose();
  }
}

/// Isolate-entry message: plain data only (SendPort + integer addresses).
final class AudioPushIsolateStartupMessage {
  const AudioPushIsolateStartupMessage({
    required this.readyPort,
    required this.channelDescriptor,
  });

  final SendPort readyPort;
  final ScoreFollowerAudioPushChannelDescriptor channelDescriptor;
}

/// Background-isolate entry: sole writer of PCM16 audio into the native engine.
///
/// Coalesces capture chunks onto a short timer so a slow native CQT hop cannot
/// leave an unbounded `ReceivePort` backlog (the failure mode behind Windows
/// "Not Responding" freezes under Fixed Tempo / sustained mic load). Only the
/// newest chunk present at each tick is pushed; intermediate audio is shed.
void audioPushIsolateEntryPoint(AudioPushIsolateStartupMessage startupMessage) {
  final audioPushChannel = ScoreFollowerAudioPushChannel(startupMessage.channelDescriptor);
  final audioChunkReceivePort = ReceivePort();
  startupMessage.readyPort.send(audioChunkReceivePort.sendPort);

  Uint8List? latestPcm16Chunk;
  var isPushInFlight = false;

  audioChunkReceivePort.listen((message) {
    if (message is Uint8List) {
      latestPcm16Chunk = message;
    }
  });

  Timer.periodic(const Duration(milliseconds: 20), (_) {
    if (isPushInFlight) {
      return;
    }
    final chunk = latestPcm16Chunk;
    if (chunk == null) {
      return;
    }
    latestPcm16Chunk = null;
    isPushInFlight = true;
    try {
      audioPushChannel.pushPcm16Frame(chunk);
    } finally {
      isPushInFlight = false;
    }
  });
}
