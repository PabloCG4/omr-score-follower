// Phase 5.1 proof-of-concept: captures microphone audio, drives
// score_follower_core's Online DTW alignment engine through
// score_follower_bridge, and renders the raw tracked frame index and
// confidence as they update in real time. Deliberately not a score
// renderer or page-turn UI; see the Phase 5.1 architectural plan and
// TECHNICAL_CHANGELOG.md for the reasoning behind every design choice
// below (isolate split, buffer sizing, reference chromagram source, etc.).
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:score_follower_bridge/score_follower_bridge.dart';

void main() {
  runApp(const ScoreFollowerPocApp());
}

class ScoreFollowerPocApp extends StatelessWidget {
  const ScoreFollowerPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Score Follower PoC',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const ScoreFollowerHomePage(),
    );
  }
}

class ScoreFollowerHomePage extends StatefulWidget {
  const ScoreFollowerHomePage({super.key});

  @override
  State<ScoreFollowerHomePage> createState() => _ScoreFollowerHomePageState();
}

class _ScoreFollowerHomePageState extends State<ScoreFollowerHomePage> {
  // Matches FeatureExtractionConfiguration's own library defaults
  // (core-dsp/include/FeatureExtractor.hpp) exactly, so no resampling or
  // channel down-mix step is needed anywhere in this proof of concept's
  // capture-to-alignment path.
  static const double _sampleRateHz = 22050.0;
  static const int _hopLengthSamples = 512;

  ScoreFollowerEngine? _engine;
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  Isolate? _audioPushIsolate;
  Timer? _uiPollingTimer;

  bool _isRunning = false;
  ScoreFollowerAlignmentPosition _latestPosition = ScoreFollowerAlignmentPosition.zero;
  String? _lastErrorMessage;

  @override
  void dispose() {
    unawaited(_stop());
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _lastErrorMessage = null;
    });

    ScoreFollowerEngine? engine;
    Isolate? audioPushIsolate;
    StreamSubscription<Uint8List>? audioStreamSubscription;
    Timer? uiPollingTimer;

    try {
      if (!await _audioRecorder.hasPermission()) {
        throw StateError('Microphone permission was denied.');
      }

      engine = ScoreFollowerEngine.create(
        sampleRateHz: _sampleRateHz,
        hopLengthSamples: _hopLengthSamples,
      );
      engine.loadReferenceChromagram(
        pitchClassEnergiesRowMajor: buildSyntheticReferenceChromagram(),
        frameCount: syntheticReferenceFrameCount,
        sampleRateHz: _sampleRateHz,
        hopLengthSamples: _hopLengthSamples,
      );

      // The background isolate becomes the sole writer of audio data
      // (never the UI isolate: the DSP work behind pushAudioFrame, while
      // designed to be fast, is not free). Its own ReceivePort's SendPort
      // is handed back through pushIsolateReadyPort before any audio is
      // pushed.
      final pushIsolateReadyPort = ReceivePort();
      audioPushIsolate = await Isolate.spawn(
        _audioPushIsolateEntryPoint,
        _AudioPushIsolateStartupMessage(
          readyPort: pushIsolateReadyPort.sendPort,
          channelDescriptor: engine.audioPushChannel,
        ),
      );
      final audioPushSendPort = await pushIsolateReadyPort.first as SendPort;
      pushIsolateReadyPort.close();

      final audioStream = await _audioRecorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRateHz.toInt(),
          numChannels: 1,
        ),
      );
      audioStreamSubscription = audioStream.listen(audioPushSendPort.send);

      // The UI isolate independently polls on its own timer, at roughly
      // 30 Hz (comfortably above human-perceptible UI update thresholds,
      // below the DTW engine's own ~43 Hz internal frame rate at the
      // default hop length/sample rate above); no SendPort round-trip is
      // needed for the read path, since it is already lock-free by
      // construction (see score_follower_bridge's own top-level docs).
      uiPollingTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        if (!mounted || engine == null) {
          return;
        }
        setState(() {
          _latestPosition = engine!.getCurrentAlignmentPosition();
        });
      });

      setState(() {
        _engine = engine;
        _audioStreamSubscription = audioStreamSubscription;
        _audioPushIsolate = audioPushIsolate;
        _uiPollingTimer = uiPollingTimer;
        _isRunning = true;
      });
    } catch (error) {
      uiPollingTimer?.cancel();
      await audioStreamSubscription?.cancel();
      audioPushIsolate?.kill(priority: Isolate.immediate);
      engine?.dispose();
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }
      setState(() {
        _lastErrorMessage = error.toString();
        _isRunning = false;
      });
    }
  }

  Future<void> _stop() async {
    _uiPollingTimer?.cancel();
    _uiPollingTimer = null;

    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;

    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
    }

    _audioPushIsolate?.kill(priority: Isolate.immediate);
    _audioPushIsolate = null;

    _engine?.dispose();
    _engine = null;

    if (mounted) {
      setState(() {
        _isRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Score Follower PoC')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _isRunning ? _stop : _start,
                child: Text(_isRunning ? 'Stop' : 'Start'),
              ),
              const SizedBox(height: 32),
              Text(
                'referenceFrameIndex: ${_latestPosition.referenceFrameIndex.toStringAsFixed(3)}\n'
                'alignmentConfidence: ${_latestPosition.alignmentConfidence.toStringAsFixed(3)}\n'
                'cumulativeDistortionCost: ${_latestPosition.cumulativeDistortionCost.toStringAsFixed(3)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
              ),
              if (_lastErrorMessage != null) ...[
                const SizedBox(height: 24),
                Text(
                  _lastErrorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Message sent from the UI isolate to the background audio-push isolate's
/// entry point at spawn time. Every field is plain data (a [SendPort] and a
/// [ScoreFollowerAudioPushChannelDescriptor] of plain integers), safe to
/// cross the isolate boundary.
class _AudioPushIsolateStartupMessage {
  const _AudioPushIsolateStartupMessage({
    required this.readyPort,
    required this.channelDescriptor,
  });

  final SendPort readyPort;
  final ScoreFollowerAudioPushChannelDescriptor channelDescriptor;
}

/// Entry point for the background isolate that becomes the sole writer of
/// audio data into the native engine. Reconstructs a
/// [ScoreFollowerAudioPushChannel] from the address-only descriptor it was
/// handed, then forwards every raw PCM16 chunk it receives on its own
/// [ReceivePort] straight into [ScoreFollowerAudioPushChannel.pushPcm16Frame].
void _audioPushIsolateEntryPoint(_AudioPushIsolateStartupMessage startupMessage) {
  final audioPushChannel = ScoreFollowerAudioPushChannel(startupMessage.channelDescriptor);
  final audioChunkReceivePort = ReceivePort();
  startupMessage.readyPort.send(audioChunkReceivePort.sendPort);

  audioChunkReceivePort.listen((message) {
    if (message is Uint8List) {
      audioPushChannel.pushPcm16Frame(message);
    }
  });
}

/// Number of chroma frames in [buildSyntheticReferenceChromagram]'s output;
/// must be passed alongside it to
/// [ScoreFollowerEngine.loadReferenceChromagram].
final int syntheticReferenceFrameCount = _syntheticChordProgression.length * _framesPerChord;

/// Frames each chord in [_syntheticChordProgression] is held for.
const int _framesPerChord = 50;

/// The same deterministic four-chord progression (C major, G major, A
/// minor, F major) already validated end-to-end by
/// core-dsp/tests/dtw_validator.cpp, reused here as a stand-in reference
/// score: generating a real score-derived reference chromagram from a
/// MusicXML/PDF source is an explicitly separate, later concern, out of
/// scope for this proof of concept (see the Phase 5.1 architectural plan).
const List<List<int>> _syntheticChordProgression = [
  [0, 4, 7], // C major.
  [7, 11, 2], // G major.
  [9, 0, 4], // A minor.
  [5, 9, 0], // F major.
];

/// Builds the flat, row-major [pitchClassEnergiesRowMajor] array expected
/// by [ScoreFollowerEngine.loadReferenceChromagram]: each chord in
/// [_syntheticChordProgression] held for [_framesPerChord] frames, back to
/// back, with every active pitch class given unit energy.
List<double> buildSyntheticReferenceChromagram() {
  final energies = List<double>.filled(syntheticReferenceFrameCount * scoreFollowerPitchClassCount, 0.0);
  var frameIndex = 0;
  for (final chordPitchClasses in _syntheticChordProgression) {
    for (var frameWithinChord = 0; frameWithinChord < _framesPerChord; frameWithinChord++) {
      final rowOffset = frameIndex * scoreFollowerPitchClassCount;
      for (final pitchClass in chordPitchClasses) {
        energies[rowOffset + pitchClass] = 1.0;
      }
      frameIndex++;
    }
  }
  return energies;
}
