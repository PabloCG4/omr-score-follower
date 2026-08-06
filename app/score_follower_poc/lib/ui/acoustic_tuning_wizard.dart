import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:score_follower_bridge/score_follower_bridge.dart';

import '../domain/tuning_pitch_math.dart';

/// Values returned when the user finishes the acoustic tuning wizard.
final class AcousticTuningWizardResult {
  const AcousticTuningWizardResult({
    required this.baseFrequencyHz,
    required this.transpositionSemitones,
  });

  final double baseFrequencyHz;
  final int transpositionSemitones;
}

/// Wizard lifecycle. [latched] means listening stopped and the measurement is frozen.
enum AcousticTuningWizardStatus {
  idle,
  listening,
  latched,
  failed,
}

/// Modal wizard: ask the user to strike a selected note three times, then map
/// the median F0 to A4 Hz + integer transposition.
///
/// Strike counting, noise gate, and auto-latch live entirely in Dart so the
/// production CQT / tracking path is unchanged. Designed for decaying
/// instruments (piano, guitar) where a continuous hold never stays above gate.
class AcousticTuningWizard extends StatefulWidget {
  const AcousticTuningWizard({super.key});

  /// Opens the wizard as a modal dialog. Returns `null` on cancel.
  static Future<AcousticTuningWizardResult?> show(BuildContext context) {
    return showDialog<AcousticTuningWizardResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return const Dialog(
          insetPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: SizedBox(
            width: 440,
            child: AcousticTuningWizard(),
          ),
        );
      },
    );
  }

  @override
  State<AcousticTuningWizard> createState() => AcousticTuningWizardState();
}

class AcousticTuningWizardState extends State<AcousticTuningWizard> {
  static const double wizardSampleRateHz = 22050.0;
  static const int wizardHopLengthSamples = 512;

  /// Native CQT peak-to-mean confidence below this is treated as silence/noise.
  static const double minimumConfidenceForDetection = 0.23;

  /// Normalized PCM RMS below this is treated as background (squelch).
  /// Slightly permissive so piano/guitar attacks register before decay.
  static const double minimumPcmRmsForDetection = 0.015;

  /// Max cents drift between strikes (and within one attack) to count as matching.
  static const double maximumStrikeMatchCents = 40.0;

  /// Gated polls needed inside one attack before a strike is eligible.
  static const int minimumFramesPerStrike = 3;

  /// Confirmed strikes required before auto-latch.
  static const int requiredStrikeCount = 3;

  /// Quiet polls required after a strike before the next attack can start.
  static const int quietPollsBetweenStrikes = 4;

  static const Duration pitchPollInterval = Duration(milliseconds: 50);
  static const List<int> availableOctaves = <int>[2, 3, 4, 5, 6];

  final AudioRecorder audioRecorder = AudioRecorder();

  ScoreFollowerEngine? pitchEngine;
  StreamSubscription<Uint8List>? audioStreamSubscription;
  Timer? pitchPollTimer;

  int selectedPitchClass = 0; // C
  int selectedOctave = 4;
  AcousticTuningWizardStatus status = AcousticTuningWizardStatus.idle;
  String? statusDetail;

  /// Frozen after auto-latch; also used when remapping note/octave.
  AcousticTuningMeasurement? latchedMeasurement;
  double? latchedFrequencyHz;

  /// Confirmed strike frequencies (one median F0 per strike).
  final List<double> confirmedStrikeFrequenciesHz = <double>[];

  /// Frames collected during the current attack (before gate closes).
  final List<double> currentAttackFrequenciesHz = <double>[];

  /// True after a strike is committed until enough quiet frames elapse.
  bool waitingForQuietBetweenStrikes = false;
  int consecutiveQuietPolls = 0;

  double latestPcmRms = 0.0;
  bool isLatchingInProgress = false;

  bool get isActivelyListening => status == AcousticTuningWizardStatus.listening;

  bool get canSave =>
      status == AcousticTuningWizardStatus.latched && latchedMeasurement != null;

  String get selectedNoteLabel =>
      '${chromaticNoteNames[selectedPitchClass]}$selectedOctave';

  Future<void> tearDownCapture() async {
    pitchPollTimer?.cancel();
    pitchPollTimer = null;

    await audioStreamSubscription?.cancel();
    audioStreamSubscription = null;

    if (await audioRecorder.isRecording()) {
      await audioRecorder.stop();
    }

    pitchEngine?.dispose();
    pitchEngine = null;
    latestPcmRms = 0.0;
  }

  @override
  void dispose() {
    pitchPollTimer?.cancel();
    pitchPollTimer = null;
    unawaited(audioStreamSubscription?.cancel());
    audioStreamSubscription = null;
    pitchEngine?.dispose();
    pitchEngine = null;
    unawaited(() async {
      if (await audioRecorder.isRecording()) {
        await audioRecorder.stop();
      }
      audioRecorder.dispose();
    }());
    super.dispose();
  }

  void resetListeningBuffers() {
    confirmedStrikeFrequenciesHz.clear();
    currentAttackFrequenciesHz.clear();
    waitingForQuietBetweenStrikes = false;
    consecutiveQuietPolls = 0;
    latestPcmRms = 0.0;
    isLatchingInProgress = false;
  }

  String listeningPrompt() {
    final remaining = requiredStrikeCount - confirmedStrikeFrequenciesHz.length;
    if (confirmedStrikeFrequenciesHz.isEmpty) {
      return 'Strike $selectedNoteLabel clearly $requiredStrikeCount times '
          '(let it fade between strikes).';
    }
    if (waitingForQuietBetweenStrikes) {
      return 'Strike ${confirmedStrikeFrequenciesHz.length}/$requiredStrikeCount '
          'recorded. Let the note fade, then strike again '
          '($remaining remaining).';
    }
    return 'Strike ${confirmedStrikeFrequenciesHz.length}/$requiredStrikeCount '
        'recorded. Strike $selectedNoteLabel again ($remaining remaining).';
  }

  Future<void> startListening() async {
    setState(() {
      status = AcousticTuningWizardStatus.listening;
      latchedMeasurement = null;
      latchedFrequencyHz = null;
      resetListeningBuffers();
      statusDetail = listeningPrompt();
    });

    try {
      if (!await audioRecorder.hasPermission()) {
        throw StateError('Microphone permission was denied.');
      }

      await tearDownCapture();

      final engine = ScoreFollowerEngine.create(
        sampleRateHz: wizardSampleRateHz,
        hopLengthSamples: wizardHopLengthSamples,
      );
      pitchEngine = engine;

      final audioStream = await audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 22050,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );
      audioStreamSubscription = audioStream.listen((pcm16Bytes) {
        final liveEngine = pitchEngine;
        if (liveEngine == null) {
          return;
        }
        latestPcmRms = computePcm16Rms(pcm16Bytes);
        ScoreFollowerAudioPushChannel(liveEngine.audioPushChannel)
            .pushPcm16Frame(pcm16Bytes);
      });

      pitchPollTimer = Timer.periodic(pitchPollInterval, (_) {
        onPitchPollTick();
      });
    } catch (error) {
      await tearDownCapture();
      if (!mounted) {
        return;
      }
      setState(() {
        status = AcousticTuningWizardStatus.failed;
        statusDetail = error.toString();
        resetListeningBuffers();
      });
    }
  }

  Future<void> stopToIdle() async {
    await tearDownCapture();
    if (!mounted) {
      return;
    }
    setState(() {
      status = AcousticTuningWizardStatus.idle;
      statusDetail = null;
      latchedMeasurement = null;
      latchedFrequencyHz = null;
      resetListeningBuffers();
    });
  }

  Future<void> retryListening() async {
    await startListening();
  }

  void onPitchPollTick() {
    if (!mounted || !isActivelyListening || isLatchingInProgress) {
      return;
    }

    final engine = pitchEngine;
    if (engine == null) {
      return;
    }

    final estimate = engine.estimateDominantPitch();
    final passesNoiseGate = estimate != null &&
        estimate.confidence >= minimumConfidenceForDetection &&
        latestPcmRms >= minimumPcmRmsForDetection &&
        estimate.frequencyHz.isFinite &&
        estimate.frequencyHz > 0.0;

    if (!passesNoiseGate) {
      onQuietPoll();
      return;
    }

    onVoicedPoll(estimate.frequencyHz);
  }

  void onQuietPoll() {
    // Closing an attack after enough voiced frames commits one strike.
    if (currentAttackFrequenciesHz.length >= minimumFramesPerStrike) {
      tryCommitCurrentAttackAsStrike();
      return;
    }

    currentAttackFrequenciesHz.clear();

    if (waitingForQuietBetweenStrikes) {
      consecutiveQuietPolls += 1;
      if (consecutiveQuietPolls >= quietPollsBetweenStrikes) {
        setState(() {
          waitingForQuietBetweenStrikes = false;
          consecutiveQuietPolls = 0;
          statusDetail = listeningPrompt();
        });
      }
      return;
    }

    // Idle silence between strikes: keep the strike counter, refresh prompt once.
    if (confirmedStrikeFrequenciesHz.isNotEmpty &&
        statusDetail != listeningPrompt()) {
      setState(() {
        statusDetail = listeningPrompt();
      });
    }
  }

  void onVoicedPoll(double frequencyHz) {
    if (waitingForQuietBetweenStrikes) {
      // Still decaying / ringing from the previous strike — ignore until quiet.
      consecutiveQuietPolls = 0;
      return;
    }

    if (currentAttackFrequenciesHz.isNotEmpty) {
      final centsFromMedian = frequencyDistanceCents(
        frequencyHz,
        medianFrequencyHz(currentAttackFrequenciesHz),
      );
      if (centsFromMedian > maximumStrikeMatchCents) {
        // Pitch jumped mid-attack (noise / wrong note) — restart this strike.
        currentAttackFrequenciesHz
          ..clear()
          ..add(frequencyHz);
        return;
      }
    }

    currentAttackFrequenciesHz.add(frequencyHz);
  }

  void tryCommitCurrentAttackAsStrike() {
    final strikeFrequencyHz = medianFrequencyHz(currentAttackFrequenciesHz);
    currentAttackFrequenciesHz.clear();

    if (confirmedStrikeFrequenciesHz.isNotEmpty) {
      final referenceMedianHz = medianFrequencyHz(confirmedStrikeFrequenciesHz);
      final centsFromStrikes =
          frequencyDistanceCents(strikeFrequencyHz, referenceMedianHz);
      if (centsFromStrikes > maximumStrikeMatchCents) {
        setState(() {
          confirmedStrikeFrequenciesHz
            ..clear()
            ..add(strikeFrequencyHz);
          waitingForQuietBetweenStrikes = true;
          consecutiveQuietPolls = 0;
          statusDetail =
              'Pitch differed from previous strikes — restarting. '
              'Strike $selectedNoteLabel 3 times again.';
        });
        return;
      }
    }

    confirmedStrikeFrequenciesHz.add(strikeFrequencyHz);
    waitingForQuietBetweenStrikes = true;
    consecutiveQuietPolls = 0;

    if (confirmedStrikeFrequenciesHz.length >= requiredStrikeCount) {
      final lockedFrequencyHz = medianFrequencyHz(confirmedStrikeFrequenciesHz);
      final measurement = mapDetectedFrequencyToTuning(
        detectedFrequencyHz: lockedFrequencyHz,
        referencePitchClass: selectedPitchClass,
        referenceOctave: selectedOctave,
      );
      isLatchingInProgress = true;
      unawaited(autoLatchMeasurement(measurement, lockedFrequencyHz));
      return;
    }

    setState(() {
      statusDetail = listeningPrompt();
    });
  }

  Future<void> autoLatchMeasurement(
    AcousticTuningMeasurement measurement,
    double frequencyHz,
  ) async {
    await tearDownCapture();
    if (!mounted) {
      return;
    }
    setState(() {
      status = AcousticTuningWizardStatus.latched;
      latchedFrequencyHz = frequencyHz;
      latchedMeasurement = measurement;
      confirmedStrikeFrequenciesHz.clear();
      currentAttackFrequenciesHz.clear();
      waitingForQuietBetweenStrikes = false;
      statusDetail =
          'Locked from 3 strikes. Adjust note/octave if needed, then Save — or Retry.';
    });
  }

  void onReferenceNoteChanged({int? pitchClass, int? octave}) {
    setState(() {
      if (pitchClass != null) {
        selectedPitchClass = pitchClass;
      }
      if (octave != null) {
        selectedOctave = octave;
      }
      final lockedFrequencyHz = latchedFrequencyHz;
      if (status == AcousticTuningWizardStatus.latched &&
          lockedFrequencyHz != null) {
        latchedMeasurement = mapDetectedFrequencyToTuning(
          detectedFrequencyHz: lockedFrequencyHz,
          referencePitchClass: selectedPitchClass,
          referenceOctave: selectedOctave,
        );
      } else if (isActivelyListening) {
        statusDetail = listeningPrompt();
      }
    });
  }

  Future<void> applyAndClose() async {
    final measurement = latchedMeasurement;
    if (measurement == null || !canSave) {
      return;
    }
    await tearDownCapture();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(
      AcousticTuningWizardResult(
        baseFrequencyHz: measurement.baseFrequencyHz,
        transpositionSemitones: measurement.transpositionSemitones,
      ),
    );
  }

  Future<void> cancelAndClose() async {
    await tearDownCapture();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  String statusLabel() {
    switch (status) {
      case AcousticTuningWizardStatus.idle:
        return 'Idle';
      case AcousticTuningWizardStatus.listening:
        return 'Listening for strikes';
      case AcousticTuningWizardStatus.latched:
        return 'Locked';
      case AcousticTuningWizardStatus.failed:
        return 'Failed';
    }
  }

  static double computePcm16Rms(Uint8List pcm16Bytes) {
    final sampleCount = pcm16Bytes.length ~/ 2;
    if (sampleCount == 0) {
      return 0.0;
    }
    final byteData = ByteData.sublistView(pcm16Bytes);
    var sumSquares = 0.0;
    for (var sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
      final sample =
          byteData.getInt16(sampleIndex * 2, Endian.little) / 32768.0;
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / sampleCount);
  }

  static double medianFrequencyHz(List<double> frequenciesHz) {
    final sorted = List<double>.from(frequenciesHz)..sort();
    final middleIndex = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middleIndex];
    }
    return (sorted[middleIndex - 1] + sorted[middleIndex]) / 2.0;
  }

  static double frequencyDistanceCents(double firstHz, double secondHz) {
    if (firstHz <= 0.0 || secondHz <= 0.0) {
      return double.infinity;
    }
    return (1200.0 * (math.log(firstHz / secondHz) / math.ln2)).abs();
  }

  Widget buildStrikeIndicators(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (var strikeIndex = 0; strikeIndex < requiredStrikeCount; strikeIndex++) ...[
          if (strikeIndex > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: strikeIndex < confirmedStrikeFrequenciesHz.length
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final measurement = latchedMeasurement;
    final heardNote = measurement == null
        ? null
        : nearestNoteLabel(measurement.detectedFrequencyHz);
    final strikeProgressLabel =
        '${confirmedStrikeFrequenciesHz.length}/$requiredStrikeCount strikes';

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Determine Tuning',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Select the note you will play, then strike it clearly '
            '$requiredStrikeCount times (let each strike fade before the next). '
            'Works with piano, guitar, and other decaying instruments.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey<int>(selectedPitchClass),
                  initialValue: selectedPitchClass,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var pitchClass = 0;
                        pitchClass < chromaticNoteNames.length;
                        pitchClass++)
                      DropdownMenuItem<int>(
                        value: pitchClass,
                        child: Text(chromaticNoteNames[pitchClass]),
                      ),
                  ],
                  onChanged: isActivelyListening
                      ? null
                      : (pitchClass) {
                          if (pitchClass == null) {
                            return;
                          }
                          onReferenceNoteChanged(pitchClass: pitchClass);
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey<int>(selectedOctave),
                  initialValue: selectedOctave,
                  decoration: const InputDecoration(
                    labelText: 'Octave',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final octave in availableOctaves)
                      DropdownMenuItem<int>(
                        value: octave,
                        child: Text('$octave'),
                      ),
                  ],
                  onChanged: isActivelyListening
                      ? null
                      : (octave) {
                          if (octave == null) {
                            return;
                          }
                          onReferenceNoteChanged(octave: octave);
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Status: ${statusLabel()}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (statusDetail != null) ...[
            const SizedBox(height: 4),
            Text(statusDetail!, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (isActivelyListening) ...[
            const SizedBox(height: 12),
            Text(
              strikeProgressLabel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            buildStrikeIndicators(context),
          ],
          if (measurement != null && heardNote != null) ...[
            const SizedBox(height: 16),
            Text(
              'Heard pitch: ${heardNote.noteName}${heardNote.octave} '
              '(${measurement.detectedFrequencyHz.toStringAsFixed(1)} Hz)',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Base tuning (A4 equivalent): '
              '${measurement.baseFrequencyHz.toStringAsFixed(1)} Hz',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'This is the instrument concert A derived from your '
              '$selectedNoteLabel strikes — not a second detected note.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Transposition: '
              '${measurement.transpositionSemitones >= 0 ? '+' : ''}'
              '${measurement.transpositionSemitones} semitones',
            ),
          ],
          const SizedBox(height: 20),
          if (status == AcousticTuningWizardStatus.idle ||
              status == AcousticTuningWizardStatus.failed)
            FilledButton(
              onPressed: startListening,
              child: const Text('Start listening'),
            )
          else if (status == AcousticTuningWizardStatus.latched)
            OutlinedButton(
              onPressed: retryListening,
              child: const Text('Retry'),
            )
          else
            OutlinedButton(
              onPressed: stopToIdle,
              child: const Text('Stop'),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: cancelAndClose,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: canSave ? applyAndClose : null,
                  child: const Text('Save / Finish'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
