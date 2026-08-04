import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:score_follower_bridge/score_follower_bridge.dart';

import '../score/score_document.dart';
import '../score/score_document_loader.dart';
import 'alignment_snapshot.dart';
import 'cursor_display_model.dart';

/// Low-frequency session lifecycle: score load, Start/Stop, engine/mic/isolate
/// ownership, and the current page index. High-frequency alignment updates go
/// through [alignmentSnapshot] and [cursorDisplayModel] so the scaffold only
/// rebuilds on rare session events.
final class FollowingSessionController extends ChangeNotifier {
  FollowingSessionController({
    required this.cursorDisplayModel,
    ScoreDocumentLoader? scoreDocumentLoader,
    AudioRecorder? audioRecorder,
    this.defaultScoreId = 'demo_four_chords',
  })  : scoreDocumentLoader = scoreDocumentLoader ?? ScoreDocumentLoader(),
        audioRecorder = audioRecorder ?? AudioRecorder();

  final CursorDisplayModel cursorDisplayModel;
  final ScoreDocumentLoader scoreDocumentLoader;
  final AudioRecorder audioRecorder;
  final String defaultScoreId;

  /// High-frequency DSP poll channel (~30 Hz). Diagnostics may listen;
  /// the cursor path consumes it via [setTargetFrameIndex] without rebuilding
  /// the scaffold.
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

  /// Loads [defaultScoreId] (or [scoreId]) from assets. Safe to call before
  /// Start; Start will load the default if none is loaded yet.
  Future<void> loadScore({String? scoreId}) async {
    isLoadingScore = true;
    lastErrorMessage = null;
    notifyListeners();
    try {
      final document = await scoreDocumentLoader.loadFromAssets(scoreId ?? defaultScoreId);
      scoreDocument = document;
      currentPageIndex = 0;
      cursorDisplayModel.attachScoreDocument(document);
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

    ScoreFollowerEngine? createdEngine;
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

      createdEngine = ScoreFollowerEngine.create(
        sampleRateHz: document.sampleRateHz,
        hopLengthSamples: document.hopLengthSamples,
      );
      createdEngine.loadReferenceChromagram(
        pitchClassEnergiesRowMajor: document.referenceChromagramAsDoubles,
        frameCount: document.referenceFrameCount,
        sampleRateHz: document.sampleRateHz,
        hopLengthSamples: document.hopLengthSamples,
      );

      final pushIsolateReadyPort = ReceivePort();
      createdIsolate = await Isolate.spawn(
        audioPushIsolateEntryPoint,
        AudioPushIsolateStartupMessage(
          readyPort: pushIsolateReadyPort.sendPort,
          channelDescriptor: createdEngine.audioPushChannel,
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
        final liveEngine = engine;
        if (liveEngine == null) {
          return;
        }
        final position = liveEngine.getCurrentAlignmentPosition();
        alignmentSnapshot.value = AlignmentSnapshot(
          position: position,
          polledAt: DateTime.now(),
        );
        cursorDisplayModel.setTargetFrameIndex(position.referenceFrameIndex);

        final mappedPage =
            cursorDisplayModel.mapper.mapFrameIndex(document, position.referenceFrameIndex).pageIndex;
        if (mappedPage != currentPageIndex) {
          currentPageIndex = mappedPage;
          notifyListeners();
        }
      });

      engine = createdEngine;
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
      createdEngine?.dispose();
      if (await audioRecorder.isRecording()) {
        await audioRecorder.stop();
      }
      lastErrorMessage = error.toString();
      isRunning = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    uiPollingTimer?.cancel();
    uiPollingTimer = null;

    await audioStreamSubscription?.cancel();
    audioStreamSubscription = null;

    if (await audioRecorder.isRecording()) {
      await audioRecorder.stop();
    }

    audioPushIsolate?.kill(priority: Isolate.immediate);
    audioPushIsolate = null;

    engine?.dispose();
    engine = null;

    cursorDisplayModel.stop();
    isRunning = false;
    alignmentSnapshot.value = AlignmentSnapshot.zero;
    notifyListeners();
  }

  /// Dev-only: scrub the cursor target without mic input, to validate the
  /// timeline mapper and interpolation path.
  void scrubToFrameIndex(double frameIndex) {
    cursorDisplayModel.snapToFrameIndex(frameIndex);
    final document = scoreDocument;
    if (document == null) {
      return;
    }
    final mappedPage = cursorDisplayModel.mapper.mapFrameIndex(document, frameIndex).pageIndex;
    if (mappedPage != currentPageIndex) {
      currentPageIndex = mappedPage;
      notifyListeners();
    }
  }

  void onPageTransitionChanged(bool inProgress) {
    cursorDisplayModel.setPageTransitionInProgress(inProgress);
  }

  @override
  void dispose() {
    uiPollingTimer?.cancel();
    uiPollingTimer = null;
    audioStreamSubscription?.cancel();
    audioStreamSubscription = null;
    audioPushIsolate?.kill(priority: Isolate.immediate);
    audioPushIsolate = null;
    engine?.dispose();
    engine = null;
    cursorDisplayModel.stop();
    isRunning = false;
    // Best-effort async mic teardown; dispose itself cannot await.
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
