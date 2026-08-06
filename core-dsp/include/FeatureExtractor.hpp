// Abstract interface for the real-time acoustic feature extraction pipeline.
// Concrete implementations will perform Harmonic-Percussive Source
// Separation, Constant-Q Transform analysis, and chroma folding, mirroring
// the DSP pipeline validated in the Python research phase (see
// research/chromagram_extractor.py). No mathematical implementation is
// declared here yet; this header only fixes the production data flow that
// concrete implementations must conform to.
#pragma once

#include "Chromagram.hpp"

#include <cstddef>
#include <optional>

namespace scorefollower::dsp {

// Parameters governing a FeatureExtractor implementation, kept as plain data
// so that the same configuration can be constructed once by the host
// application (mobile audio engine or offline analysis tool) and shared
// between the Python research pipeline's equivalent settings and this
// production implementation.
struct FeatureExtractionConfiguration {
    double sampleRateHz = 22050.0;
    std::size_t hopLengthSamples = 512;
    std::size_t constantQBinsPerOctave = 36;
    std::size_t constantQOctaveCount = 7;
    double constantQMinimumFrequencyHz = 32.703195662574829;  // Note C1.

    // Constant pitch-shift correction, in fractional semitones, applied to
    // every Constant-Q analysis kernel's center frequency before it is
    // built. Intended to be populated from a previously resolved
    // AutoCorrelationTuningCompensator offset (see AlignmentEngine.hpp) when
    // re-configuring the extractor for a specific instrument's tuning.
    // Zero means no correction (kernels assume standard A4 = 440 Hz).
    double tuningOffsetSemitones = 0.0;

    // Safety ceiling on the FFT size computed for the lowest analysis
    // octave. Must be a power of two. The live mobile default is 8192
    // (~370 ms at 22050 Hz): a 65536-point dense CQT per hop is not
    // sustainable in real time on mobile/desktop UI hosts and was the
    // primary cause of "Not Responding" freezes under microphone load.
    // Offline validators may raise this for research-grade low-frequency
    // resolution.
    std::size_t maximumTransformLength = 8192;

    // When true, every completed analysis hop is appended to the extractor's
    // accumulated chromagram (offline / validator use). Live score-following
    // leaves this false so a multi-minute performance cannot grow an
    // unbounded std::vector on the audio path.
    bool accumulateChromagramFrames = false;

    // Bounded FIFO of chroma frames waiting for pollLatestChromaVector.
    // Prevents silent frame loss when several hops complete inside one
    // ingestAudioFrame call, while capping memory if the consumer stalls.
    std::size_t maxPendingChromaFrames = 8;
};

// Dominant fundamental estimate derived from pre-fold Constant-Q bin
// magnitudes (peak bin + parabolic interpolation). Used by the acoustic
// tuning wizard; confidence is in [0, 1] and near-zero means silence or
// an unusable peak.
struct DominantPitchEstimate {
    double frequencyHz = 0.0;
    double confidence = 0.0;
};

// Interface implemented by the concrete DSP pipeline that turns a stream of
// raw audio samples, drained from a CircularAudioBuffer by a non-real-time
// analysis thread, into a chromagram. Implementations own all intermediate
// analysis buffers so that ingestAudioFrame can be called repeatedly with
// arbitrarily sized chunks of audio without the caller needing to know the
// underlying hop size or windowing scheme.
class FeatureExtractor {
public:
    virtual ~FeatureExtractor() = default;

    // Applies (or re-applies) the extraction configuration. Implementations
    // are expected to allocate any internal analysis buffers here rather
    // than during ingestAudioFrame, so that ingestion remains allocation-free
    // once configured.
    virtual void configure(const FeatureExtractionConfiguration& configuration) = 0;

    // Rebuilds analysis kernels so their center frequencies track
    // `tuningOffsetSemitones` (12 * log2(A4_Hz / 440)). Intended for
    // session-prepare retune, not the real-time audio path.
    virtual void setTuningOffsetSemitones(double tuningOffsetSemitones) = 0;

    // Ingests a contiguous block of newly available, mono, already-resampled
    // audio samples. Implementations are expected to internally accumulate
    // samples until a full hop-sized analysis frame is available.
    virtual void ingestAudioFrame(const float* audioSamples, std::size_t sampleCount) = 0;

    // Returns the chroma vector completed by the most recent call to
    // ingestAudioFrame, if a full analysis frame became available since the
    // last call to pollLatestChromaVector, or std::nullopt otherwise.
    virtual std::optional<ChromaVector> pollLatestChromaVector() = 0;

    // Returns the most recent CQT peak-based pitch estimate from a completed
    // analysis hop, or std::nullopt when no hop has completed yet or the
    // peak failed the silence gate.
    [[nodiscard]] virtual std::optional<DominantPitchEstimate> getLatestDominantPitchEstimate() const = 0;

    // Returns the full chromagram accumulated since construction or the last
    // call to reset. Primarily intended for offline analysis, diagnostics,
    // and generating reference chromagrams from a rendered score, rather
    // than for the real-time alignment path.
    [[nodiscard]] virtual const Chromagram& getAccumulatedChromagram() const = 0;

    // Discards all accumulated state (partial frames and the accumulated
    // chromagram), returning the extractor to the state it was in
    // immediately after configure was last called.
    virtual void reset() = 0;
};

}  // namespace scorefollower::dsp
