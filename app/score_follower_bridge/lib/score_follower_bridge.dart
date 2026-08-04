/// Idiomatic Dart API over score_follower_core's C ABI
/// (../../core-dsp/include/ScoreFollowerCApi.h), built on top of the
/// low-level @Native bindings in src/score_follower_bindings.dart.
///
/// The concurrency model mirrors score_follower_core's own single-
/// producer/single-consumer contract one hop further into Dart: a
/// [ScoreFollowerEngine] is created and owned by whichever isolate manages
/// its lifecycle (typically the UI isolate); [ScoreFollowerEngine.audioPushChannel]
/// then hands a small, plain-data descriptor to a background isolate, which
/// reconstructs a [ScoreFollowerAudioPushChannel] from it and becomes the
/// sole writer via [ScoreFollowerAudioPushChannel.pushAudioFrame]; the UI
/// isolate remains the sole reader via
/// [ScoreFollowerEngine.getCurrentAlignmentPosition] (or, symmetrically, a
/// [ScoreFollowerPositionReader] reconstructed from
/// [ScoreFollowerEngine.positionReaderHandleAddress] if the reading isolate
/// is not the owning one either). Pointers are plain integer addresses, not
/// GC-tracked Dart objects, so sharing them across isolates by address is
/// safe by construction; see score_follower_core's own
/// std::atomic<double>-backed AlignmentPosition publishing for why the read
/// side needs no additional synchronization.
library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkg_ffi;

import 'src/score_follower_bindings.dart' as bindings;

/// Number of pitch classes per chroma frame; re-exported from
/// src/score_follower_bindings.dart so callers building a reference
/// chromagram's flat row-major array never need to import that library
/// directly.
const int scoreFollowerPitchClassCount = bindings.scoreFollowerPitchClassCount;

/// Idiomatic mirror of `ScoreFollowerAlignmentPosition`
/// (ScoreFollowerCApi.h) / `AlignmentPosition` (AlignmentEngine.hpp),
/// expressed with the same field names as the underlying C++ struct rather
/// than the C ABI's snake_case field names.
final class ScoreFollowerAlignmentPosition {
  const ScoreFollowerAlignmentPosition({
    required this.referenceFrameIndex,
    required this.alignmentConfidence,
    required this.cumulativeDistortionCost,
  });

  factory ScoreFollowerAlignmentPosition._fromNative(
    bindings.ScoreFollowerAlignmentPositionNative native,
  ) {
    return ScoreFollowerAlignmentPosition(
      referenceFrameIndex: native.reference_frame_index,
      alignmentConfidence: native.alignment_confidence,
      cumulativeDistortionCost: native.cumulative_distortion_cost,
    );
  }

  /// Fractional index into the reference chromagram's frame sequence.
  final double referenceFrameIndex;

  /// Confidence estimate for [referenceFrameIndex], in `[0, 1]`.
  final double alignmentConfidence;

  /// Cumulative Online DTW distortion cost accumulated so far.
  final double cumulativeDistortionCost;

  static const zero = ScoreFollowerAlignmentPosition(
    referenceFrameIndex: 0.0,
    alignmentConfidence: 0.0,
    cumulativeDistortionCost: 0.0,
  );

  @override
  String toString() {
    return 'ScoreFollowerAlignmentPosition(referenceFrameIndex: '
        '${referenceFrameIndex.toStringAsFixed(3)}, alignmentConfidence: '
        '${alignmentConfidence.toStringAsFixed(3)}, cumulativeDistortionCost: '
        '${cumulativeDistortionCost.toStringAsFixed(3)})';
  }
}

/// Converts a chunk of little-endian, signed 16-bit PCM mono audio bytes
/// (the format `package:record`'s `AudioEncoder.pcm16bits` streaming mode
/// delivers) into the `[-1.0, 1.0]`-normalized float32 samples
/// [ScoreFollowerEngine.pushAudioFrame]/[ScoreFollowerAudioPushChannel.pushAudioFrame]
/// expect.
Float32List convertPcm16BytesToFloat32Samples(Uint8List pcm16Bytes) {
  final sampleCount = pcm16Bytes.length ~/ 2;
  final floatSamples = Float32List(sampleCount);
  final byteData = ByteData.sublistView(pcm16Bytes);
  const normalizationFactor = 1.0 / 32768.0;
  for (var sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
    final signedSample = byteData.getInt16(sampleIndex * 2, Endian.little);
    floatSamples[sampleIndex] = signedSample * normalizationFactor;
  }
  return floatSamples;
}

/// A small, plain-data (isolate-message-safe) handle to the audio-push side
/// of a [ScoreFollowerEngine], meant to be sent to a background isolate via
/// `Isolate.spawn`'s entry-point message and reconstructed there as a
/// [ScoreFollowerAudioPushChannel].
final class ScoreFollowerAudioPushChannelDescriptor {
  const ScoreFollowerAudioPushChannelDescriptor({
    required this.engineHandleAddress,
    required this.audioPushBufferAddress,
    required this.audioPushBufferCapacitySamples,
  });

  final int engineHandleAddress;
  final int audioPushBufferAddress;
  final int audioPushBufferCapacitySamples;
}

/// The sole-writer side of a [ScoreFollowerEngine], reconstructed inside a
/// background isolate from a [ScoreFollowerAudioPushChannelDescriptor].
/// Does not own the underlying native memory (the owning
/// [ScoreFollowerEngine] does) and must not outlive it.
final class ScoreFollowerAudioPushChannel {
  ScoreFollowerAudioPushChannel(ScoreFollowerAudioPushChannelDescriptor descriptor)
      : _handle = ffi.Pointer<bindings.ScoreFollowerEngineHandle>.fromAddress(descriptor.engineHandleAddress),
        _audioPushBuffer = ffi.Pointer<ffi.Float>.fromAddress(descriptor.audioPushBufferAddress),
        _audioPushBufferCapacitySamples = descriptor.audioPushBufferCapacitySamples;

  final ffi.Pointer<bindings.ScoreFollowerEngineHandle> _handle;
  final ffi.Pointer<ffi.Float> _audioPushBuffer;
  final int _audioPushBufferCapacitySamples;

  /// Copies [audioSamples] into the persistent native push buffer (a
  /// single bulk `memcpy` via `TypedData.setAll`, never a per-call
  /// allocation) and forwards them to `score_follower_push_audio_frame`.
  /// Throws an [ArgumentError] if [audioSamples] is larger than the buffer
  /// capacity fixed when the owning [ScoreFollowerEngine] was created.
  void pushAudioFrame(Float32List audioSamples) {
    if (audioSamples.length > _audioPushBufferCapacitySamples) {
      throw ArgumentError(
        'audioSamples.length (${audioSamples.length}) exceeds this push '
        'channel\'s buffer capacity ($_audioPushBufferCapacitySamples); '
        'construct ScoreFollowerEngine.create with a larger '
        'audioPushBufferCapacitySamples.',
      );
    }
    _audioPushBuffer.asTypedList(audioSamples.length).setAll(0, audioSamples);
    bindings.scoreFollowerPushAudioFrame(_handle, _audioPushBuffer, audioSamples.length);
  }

  /// Convenience wrapper combining [convertPcm16BytesToFloat32Samples] and
  /// [pushAudioFrame] for callers streaming raw `AudioEncoder.pcm16bits`
  /// bytes directly (e.g. from `package:record`'s `startStream`).
  void pushPcm16Frame(Uint8List pcm16Bytes) {
    pushAudioFrame(convertPcm16BytesToFloat32Samples(pcm16Bytes));
  }
}

/// The sole-reader side of a [ScoreFollowerEngine], reconstructed from a
/// plain integer handle address. Safe to poll concurrently with a
/// [ScoreFollowerAudioPushChannel] writing from a different isolate; see
/// this library's own top-level documentation for why.
final class ScoreFollowerPositionReader {
  ScoreFollowerPositionReader(int engineHandleAddress)
      : _handle = ffi.Pointer<bindings.ScoreFollowerEngineHandle>.fromAddress(engineHandleAddress);

  final ffi.Pointer<bindings.ScoreFollowerEngineHandle> _handle;

  ScoreFollowerAlignmentPosition getCurrentAlignmentPosition() {
    return ScoreFollowerAlignmentPosition._fromNative(bindings.scoreFollowerGetAlignmentPosition(_handle));
  }
}

/// Owns the lifecycle of one native score_follower_core engine instance
/// plus its persistent audio-push buffer. Construct with [create], and
/// always release both the native engine and the native buffer with
/// [dispose] once done (there is no finalizer: native memory leaked here
/// is not reclaimed by the Dart garbage collector).
final class ScoreFollowerEngine {
  ScoreFollowerEngine._(this._handle, this._audioPushBuffer, this._audioPushBufferCapacitySamples);

  /// Default capacity, in samples, of the persistent native audio-push
  /// buffer allocated by [create]. 4096 float32 samples (16 KiB) comfortably
  /// covers `package:record`'s typical PCM16 stream chunk sizes at the
  /// engine's default 22050 Hz sample rate with headroom to spare.
  static const int defaultAudioPushBufferCapacitySamples = 4096;

  final ffi.Pointer<bindings.ScoreFollowerEngineHandle> _handle;
  final ffi.Pointer<ffi.Float> _audioPushBuffer;
  final int _audioPushBufferCapacitySamples;
  bool _isDisposed = false;

  /// Creates a new engine and its persistent audio-push buffer.
  /// [sampleRateHz] and [hopLengthSamples] are forwarded verbatim to the
  /// underlying FeatureExtractor's configuration and must match whatever
  /// sample rate the microphone capture stream is actually configured for
  /// (see `package:record`'s `RecordConfig.sampleRate`); all other
  /// extraction parameters keep score_follower_core's library defaults.
  /// Throws a [StateError] if native construction fails (for example, on an
  /// allocation failure).
  factory ScoreFollowerEngine.create({
    double sampleRateHz = 22050.0,
    int hopLengthSamples = 512,
    int audioPushBufferCapacitySamples = defaultAudioPushBufferCapacitySamples,
  }) {
    final handle = bindings.scoreFollowerCreate(sampleRateHz, hopLengthSamples);
    if (handle == ffi.nullptr) {
      throw StateError('score_follower_create returned NULL (native construction failure).');
    }
    final audioPushBuffer = pkg_ffi.calloc<ffi.Float>(audioPushBufferCapacitySamples);
    return ScoreFollowerEngine._(handle, audioPushBuffer, audioPushBufferCapacitySamples);
  }

  /// Supplies the reference chromagram this engine's alignment path will
  /// track against. [pitchClassEnergiesRowMajor] must contain exactly
  /// `frameCount * scoreFollowerPitchClassCount` entries, laid out as one
  /// contiguous row of [scoreFollowerPitchClassCount] pitch-class energies
  /// per frame. This performs one temporary native allocation to marshal
  /// the flat array across the FFI boundary; unlike [pushAudioFrame], it is
  /// not intended to be called from a real-time path, only once per
  /// performance (typically immediately after [create]).
  void loadReferenceChromagram({
    required List<double> pitchClassEnergiesRowMajor,
    required int frameCount,
    double sampleRateHz = 22050.0,
    int hopLengthSamples = 512,
  }) {
    _checkNotDisposed();
    final expectedLength = frameCount * scoreFollowerPitchClassCount;
    if (pitchClassEnergiesRowMajor.length != expectedLength) {
      throw ArgumentError(
        'pitchClassEnergiesRowMajor.length (${pitchClassEnergiesRowMajor.length}) must equal '
        'frameCount * scoreFollowerPitchClassCount ($expectedLength).',
      );
    }
    final nativeArray = pkg_ffi.calloc<ffi.Float>(expectedLength);
    try {
      final nativeArrayView = nativeArray.asTypedList(expectedLength);
      for (var index = 0; index < expectedLength; index++) {
        nativeArrayView[index] = pitchClassEnergiesRowMajor[index];
      }
      final resultCode = bindings.scoreFollowerLoadReferenceChromagram(
        _handle,
        nativeArray,
        frameCount,
        sampleRateHz,
        hopLengthSamples,
      );
      if (resultCode != 0) {
        throw StateError('score_follower_load_reference_chromagram failed with code $resultCode.');
      }
    } finally {
      pkg_ffi.calloc.free(nativeArray);
    }
  }

  /// Pushes [audioSamples] through this engine directly, without an
  /// isolate hop. Prefer this only when the engine is being driven from the
  /// same isolate that owns it (for example, a unit test, or a
  /// single-isolate proof of concept); a production capture pipeline should
  /// instead push from a dedicated background isolate via
  /// [audioPushChannel] to avoid ever blocking the UI isolate.
  void pushAudioFrame(Float32List audioSamples) {
    _checkNotDisposed();
    ScoreFollowerAudioPushChannel(audioPushChannel).pushAudioFrame(audioSamples);
  }

  /// A plain-data descriptor of this engine's audio-push side, safe to send
  /// through an `Isolate.spawn` entry-point message and reconstruct as a
  /// [ScoreFollowerAudioPushChannel] on the receiving isolate.
  ScoreFollowerAudioPushChannelDescriptor get audioPushChannel {
    _checkNotDisposed();
    return ScoreFollowerAudioPushChannelDescriptor(
      engineHandleAddress: _handle.address,
      audioPushBufferAddress: _audioPushBuffer.address,
      audioPushBufferCapacitySamples: _audioPushBufferCapacitySamples,
    );
  }

  /// This engine's native handle address, for reconstructing a
  /// [ScoreFollowerPositionReader] on another isolate. Reading from the
  /// same isolate that owns this engine should instead just call
  /// [getCurrentAlignmentPosition] directly.
  int get positionReaderHandleAddress {
    _checkNotDisposed();
    return _handle.address;
  }

  /// Reads the engine's current estimate of the live performance's
  /// position within the reference score directly, without an isolate hop.
  ScoreFollowerAlignmentPosition getCurrentAlignmentPosition() {
    _checkNotDisposed();
    return ScoreFollowerAlignmentPosition._fromNative(bindings.scoreFollowerGetAlignmentPosition(_handle));
  }

  /// Resets the engine's extraction and alignment state so a new
  /// performance attempt can begin without discarding the already-loaded
  /// reference chromagram.
  void reset() {
    _checkNotDisposed();
    bindings.scoreFollowerReset(_handle);
  }

  /// Destroys the native engine and frees the persistent audio-push buffer.
  /// Safe to call more than once; subsequent calls are a no-op. No other
  /// method on this instance (or on any [ScoreFollowerAudioPushChannel]/
  /// [ScoreFollowerPositionReader] reconstructed from it) may be called
  /// after this returns.
  void dispose() {
    if (_isDisposed) {
      return;
    }
    bindings.scoreFollowerDestroy(_handle);
    pkg_ffi.calloc.free(_audioPushBuffer);
    _isDisposed = true;
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw StateError('ScoreFollowerEngine has already been disposed.');
    }
  }
}
