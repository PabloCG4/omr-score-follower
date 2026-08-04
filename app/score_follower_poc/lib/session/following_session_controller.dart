import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:score_follower_bridge/score_follower_bridge.dart';

import '../score/score_document.dart';
import '../score/score_document_loader.dart';
import '../score/score_timeline_mapper.dart';
import 'alignment_snapshot.dart';
import 'cursor_display_model.dart';

/// Low-frequency session lifecycle: score load, Start/Stop, engine/mic/isolate
/// ownership, page navigation, and seek. High-frequency alignment updates go
/// through [alignmentSnapshot] and [cursorDisplayModel].
final class FollowingSessionController extends ChangeNotifier {
  FollowingSessionController({
    required this.cursorDisplayModel,
    ScoreDocumentLoader? scoreDocumentLoader,
    AudioRecorder? audioRecorder,
    this.defaultScoreId = 'demo_four_chords',
    this.timelineMapper = const ScoreTimelineMapper(),
  })  : scoreDocumentLoader = scoreDocumentLoader ?? ScoreDocumentLoader(),
        audioRecorder = audioRecorder ?? AudioRecorder();

  final CursorDisplayModel cursorDisplayModel;
  final ScoreDocumentLoader scoreDocumentLoader;
  final AudioRecorder audioRecorder;
  final String defaultScoreId;
  final ScoreTimelineMapper timelineMapper;

  /// High-frequency DSP poll channel (~30 Hz).
  final ValueNotifier<AlignmentSnapshot> alignmentSnapshot =
      ValueNotifier<AlignmentSnapshot>(AlignmentSnapshot.zero);

  ScoreDocument? scoreDocument;
  bool isRunning = false;
  bool isLoadingScore = false;
  int currentPageIndex = 0;
  String? lastErrorMessage;

  ScoreFollowerEngine? engine;
  StreamSubscription<Uint8List>? audioStreamSubscription;
  Isolate? audioPushIsolate;
  Timer? uiPollingTimer;

  bool get canNavigateManually => !isRunning && scoreDocument != null;

  /// Loads [defaultScoreId] (or [scoreId]) from assets, creates/recreates the
  /// native engine, and loads the reference chromagram. The engine survives
  /// subsequent Stop calls so click-to-seek can call FFI while idle.
  Future<void> loadScore({String? scoreId}) async {
    isLoadingScore = true;
    lastErrorMessage = null;
    notifyListeners();
    try {
      await tearDownCapturePipeline();
      destroyEngine();

      final document = await scoreDocumentLoader.loadFromAssets(scoreId ?? defaultScoreId);
      scoreDocument = document;
      currentPageIndex = 0;
      cursorDisplayModel.attachScoreDocument(document);
      ensureEngineLoaded(document);
      seekNativeAndUi(0.0, notifyPage: true);
    } catch (error) {
      lastErrorMessage = error.toString();
    } finally {
      isLoadingScore = false;
      notifyListeners();
    }
  }

  Future<void> start() async {
    if (isRunning) {
      return;
    }
    lastErrorMessage = null;
    notifyListeners();

    Isolate? createdIsolate;
    StreamSubscription<Uint8List>? createdSubscription;
    Timer? createdPollingTimer;

    try {
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
      final liveEngine = engine!;
      // Resume from the UI's authoritative cursor frame (tap/scrub/stop position).
      liveEngine.seekToReferenceFrame(cursorDisplayModel.displayedFrameIndex);

      final pushIsolateReadyPort = ReceivePort();
      createdIsolate = await Isolate.spawn(
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
        ),
      );
      createdSubscription = audioStream.listen(audioPushSendPort.send);

      createdPollingTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        final pollingEngine = engine;
        if (pollingEngine == null) {
          return;
        }
        final position = pollingEngine.getCurrentAlignmentPosition();
        alignmentSnapshot.value = AlignmentSnapshot(
          position: position,
          polledAt: DateTime.now(),
        );
        cursorDisplayModel.setTargetFrameIndex(position.referenceFrameIndex);

        final mappedPage =
            timelineMapper.mapFrameIndex(document, position.referenceFrameIndex).pageIndex;
        if (mappedPage != currentPageIndex) {
          currentPageIndex = mappedPage;
          notifyListeners();
        }
      });

      audioPushIsolate = createdIsolate;
      audioStreamSubscription = createdSubscription;
      uiPollingTimer = createdPollingTimer;
      isRunning = true;
      cursorDisplayModel.start();
      notifyListeners();
    } catch (error) {
      createdPollingTimer?.cancel();
      await createdSubscription?.cancel();
      createdIsolate?.kill(priority: Isolate.immediate);
      if (await audioRecorder.isRecording()) {
        await audioRecorder.stop();
      }
      lastErrorMessage = error.toString();
      isRunning = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await tearDownCapturePipeline();
    cursorDisplayModel.stop();
    isRunning = false;
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
    final document = scoreDocument;
    if (document == null) {
      return;
    }
    final clamped = pageIndex.clamp(0, document.pages.length - 1);
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
    if (currentPageIndex == pageIndex) {
      return;
    }
    currentPageIndex = pageIndex;
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
    seekToFrameIndex(frameIndex);
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
    engine = created;
  }

  void seekNativeAndUi(double frameIndex, {required bool notifyPage}) {
    final document = scoreDocument;
    cursorDisplayModel.snapToFrameIndex(frameIndex);

    if (document != null && notifyPage) {
      final mappedPage = timelineMapper.mapFrameIndex(document, frameIndex).pageIndex;
      if (mappedPage != currentPageIndex) {
        currentPageIndex = mappedPage;
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
    unawaited(tearDownCapturePipeline());
    destroyEngine();
    cursorDisplayModel.stop();
    isRunning = false;
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
void audioPushIsolateEntryPoint(AudioPushIsolateStartupMessage startupMessage) {
  final audioPushChannel = ScoreFollowerAudioPushChannel(startupMessage.channelDescriptor);
  final audioChunkReceivePort = ReceivePort();
  startupMessage.readyPort.send(audioChunkReceivePort.sendPort);

  audioChunkReceivePort.listen((message) {
    if (message is Uint8List) {
      audioPushChannel.pushPcm16Frame(message);
    }
  });
}
