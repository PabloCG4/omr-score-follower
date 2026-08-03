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
    // octave. Guards against pathological memory and CPU usage if
    // constantQMinimumFrequencyHz is configured unreasonably low or
    // constantQBinsPerOctave unreasonably high; must be a power of two.
    std::size_t maximumTransformLength = 65536;
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

    // Ingests a contiguous block of newly available, mono, already-resampled
    // audio samples. Implementations are expected to internally accumulate
    // samples until a full hop-sized analysis frame is available.
    virtual void ingestAudioFrame(const float* audioSamples, std::size_t sampleCount) = 0;

    // Returns the chroma vector completed by the most recent call to
    // ingestAudioFrame, if a full analysis frame became available since the
    // last call to pollLatestChromaVector, or std::nullopt otherwise.
    virtual std::optional<ChromaVector> pollLatestChromaVector() = 0;

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
