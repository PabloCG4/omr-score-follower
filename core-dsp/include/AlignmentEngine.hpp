// Abstract interface for the Online Dynamic Time Warping (DTW) alignment
// engine that tracks a live chroma feature stream against a fixed reference
// chromagram extracted offline from a rendering of the musical score. Also
// declares the interface for the Auto-Correlation Tuning Compensator, which
// will evaluate a constant pitch-shift offset between the live instrument
// and the reference score's assumed tuning during the first seconds of a
// performance. No mathematical implementation is declared here yet; this
// header only fixes the production data flow that concrete implementations
// must conform to.
#pragma once

#include "Chromagram.hpp"

#include <cstddef>
#include <optional>

namespace scorefollower::dsp {

// Practice / tracking policy applied during live ingest. Rubato is the
// historical Online DTW behavior. Strict freezes reference advance when
// alignment confidence is poor. FixedTempo leaves native alignment in the
// Rubato path; the host owns the presentation cursor clock.
enum class TrackingMode {
    Rubato = 0,
    Strict = 1,
    FixedTempo = 2,
};

// The alignment engine's current estimate of where the live performance is
// located within the reference score, expressed as a fractional index into
// the reference chromagram's frame sequence so that sub-frame position can
// be interpolated by the caller (e.g. for smooth page-turn timing).
struct AlignmentPosition {
    double referenceFrameIndex = 0.0;
    double alignmentConfidence = 0.0;
    double cumulativeDistortionCost = 0.0;
};

// Placeholder for the tuning compensation subsystem. During an initial
// calibration window at the start of a performance, this component
// correlates the incoming live chroma vectors against pitch-shifted (bin-
// rotated) copies of the reference chromagram to estimate a constant tuning
// offset, in fractional semitone bins, between the live instrument and the
// reference score's assumed A4 = 440 Hz tuning. This mirrors, in the
// real-time production engine, the per-recording tuning estimation already
// validated offline in the Python research pipeline (see
// research/chromagram_extractor.py, estimateTuningDeviation).
class AutoCorrelationTuningCompensator {
public:
    virtual ~AutoCorrelationTuningCompensator() = default;

    // Restricts the offset search to the given inclusive range, expressed in
    // fractional semitone bins (for example, -1.0 to +1.0 covers up to one
    // semitone flat or sharp).
    virtual void configureSearchRange(double minimumSemitoneOffset, double maximumSemitoneOffset) = 0;

    // Feeds a live chroma vector observed during the initial calibration
    // window. Implementations are expected to accumulate these frames
    // internally until resolveTuningOffsetSemitones can produce a confident
    // estimate.
    virtual void ingestCalibrationChromaVector(const ChromaVector& liveChromaVector) = 0;

    // Attempts to resolve a stable tuning offset, in fractional semitone
    // bins, from the calibration frames ingested so far, via cross-
    // correlation against the reference chromagram. Returns std::nullopt
    // until enough calibration data has been ingested to produce a confident
    // estimate.
    [[nodiscard]] virtual std::optional<double> resolveTuningOffsetSemitones() const = 0;

    // Indicates whether a tuning offset has already been resolved and
    // latched for the remainder of the performance.
    [[nodiscard]] virtual bool hasResolvedTuningOffset() const = 0;

    // Host-supplied whole-semitone transposition latch (wizard / instrument
    // profile). Bypasses the live auto-calibration accumulator so session
    // start can apply a previously measured offset without feeding frames.
    // Seek and AlignmentEngine::reset must preserve this latch.
    virtual void latchTuningOffsetSemitones(double offsetSemitones) = 0;

    virtual void reset() = 0;
};

// Interface implemented by the concrete Online DTW alignment engine.
class AlignmentEngine {
public:
    virtual ~AlignmentEngine() = default;

    // Supplies the reference chromagram, typically extracted once offline
    // from a synthesized or recorded rendering of the score, that live
    // performances will be aligned against.
    virtual void loadReferenceChromagram(const Chromagram& referenceChromagram) = 0;

    // Feeds a single newly extracted live chroma vector into the alignment
    // engine, advancing its internal DTW state by one step.
    virtual void ingestLiveChromaVector(const ChromaVector& liveChromaVector) = 0;

    [[nodiscard]] virtual AlignmentPosition getCurrentAlignmentPosition() const = 0;

    // Repositions the alignment window so subsequent live ingest resumes
    // tracking from referenceFrameIndex (clamped to the loaded reference).
    // Clears per-performance DTW path state but preserves the loaded
    // reference chromagram and any resolved tuning offset.
    virtual void seekToReferenceFrame(double referenceFrameIndex) = 0;

    // Selects the practice-mode policy for subsequent ingestLiveChromaVector
    // calls. FixedTempo is treated identically to Rubato inside the engine;
    // host-side cursor clocks must ignore the published frame index.
    virtual void setTrackingMode(TrackingMode trackingMode) = 0;

    // Confidence below which Strict mode freezes published reference advance
    // and blocks window slides. Ignored in Rubato / FixedTempo.
    virtual void setStrictConfidenceThreshold(double threshold) = 0;

    // Grants access to the tuning compensation subsystem so the host
    // application can feed it calibration frames and query its resolved
    // offset independently of the main alignment path.
    virtual AutoCorrelationTuningCompensator& getTuningCompensator() = 0;

    // Resets the alignment state (current position, cumulative cost) but
    // deliberately does not reset the tuning compensator, since a resolved
    // tuning offset is expected to remain valid for the rest of the
    // performance.
    virtual void reset() = 0;
};

}  // namespace scorefollower::dsp
