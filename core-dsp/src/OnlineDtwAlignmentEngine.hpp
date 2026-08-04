// Production AlignmentEngine: a row-synchronous, fixed-width-band Online
// Dynamic Time Warping (DTW) search that tracks a live chroma stream against
// a fully pre-loaded reference chromagram.
//
// This is deliberately not a port of Simon Dixon's bidirectional On-line
// Time Warping algorithm ("Live Tracking of Musical Performances Using
// On-line Time Warping", 2005), which handles the harder case where *both*
// the reference and the live signal arrive in real time and therefore needs
// to independently decide whether to evaluate a new Row, Column, or Both at
// each step. Here, the reference chromagram is fully known in advance (see
// loadReferenceChromagram) and only the live axis streams in real time (one
// call to ingestLiveChromaVector per new frame), so the live time index
// always advances by exactly one per call. That constraint collapses the
// classic Sakoe-Chiba/Itakura banded DTW recurrence down to needing exactly
// one previous row of accumulated cost, not a full two-dimensional band,
// following Muller's "Fundamentals of Music Processing" treatment of banded
// DTW and score-following synchronization (Chapters 3 and 7) as closely as
// Dixon's. This is a strictly leaner design for this exact one-sided
// real-time problem.
#pragma once

#include "AlignmentEngine.hpp"
#include "ChromaRotationTuningCompensator.hpp"
#include "Chromagram.hpp"

#include <atomic>
#include <cstddef>
#include <vector>

namespace scorefollower::dsp {

class OnlineDtwAlignmentEngine final : public AlignmentEngine {
public:
    // windowWidthFrames: fixed width, in reference frames, of the sliding
    // band the DTW recurrence searches on every call. Bounds per-call time
    // to O(windowWidthFrames) and, together with the two row buffers below,
    // bounds per-call extra memory to O(windowWidthFrames) as well,
    // independent of the reference length or elapsed performance time.
    // referenceCalibrationFrameCount: number of reference frames, from the
    // start of the piece, averaged to build the tuning compensator's
    // reference profile (mirrors NearestFrameAlignmentEngine's precedent).
    // stallStepPenalty / skipStepPenalty: additive cost applied to the
    // row-only (reference held while live time advances) and column-only
    // (reference advances without new live evidence) recurrence moves,
    // biasing the path toward diagonal, steady-tempo tracking while still
    // permitting graded tempo deviation.
    // maxPlausibleSkipPerFrame: a single-frame reference jump larger than
    // this is counted toward the skip run-length safeguard.
    // maxRunLengthFrames: once either the stall or skip move has been
    // selected for this many consecutive frames, an escalating extra
    // penalty is applied to that move to force the path off a degenerate
    // run (the direct analogue of Dixon's MaxRunCount, adapted to this
    // row-synchronous recurrence).
    // runLengthEscalationPenalty: per-excess-frame additive penalty applied
    // once a run exceeds maxRunLengthFrames.
    // confidenceSmoothingFactor: exponential-moving-average weight (in
    // (0, 1]) applied to the per-frame local distance at the best-matching
    // column, used to derive AlignmentPosition::alignmentConfidence as a
    // bounded, non-decaying quality signal (deliberately decoupled from the
    // monotonically growing cumulative DTW cost).
    explicit OnlineDtwAlignmentEngine(std::size_t windowWidthFramesValue = 200,
                                       std::size_t referenceCalibrationFrameCountValue = 100,
                                       double stallStepPenaltyValue = 0.15,
                                       double skipStepPenaltyValue = 0.15,
                                       std::size_t maxPlausibleSkipPerFrameValue = 4,
                                       std::size_t maxRunLengthFramesValue = 15,
                                       double runLengthEscalationPenaltyValue = 0.5,
                                       double confidenceSmoothingFactorValue = 0.1);

    void loadReferenceChromagram(const Chromagram& referenceChromagram) override;
    void ingestLiveChromaVector(const ChromaVector& liveChromaVector) override;
    [[nodiscard]] AlignmentPosition getCurrentAlignmentPosition() const override;
    void seekToReferenceFrame(double referenceFrameIndex) override;
    AutoCorrelationTuningCompensator& getTuningCompensator() override;
    void reset() override;

private:
    // Re-initializes all per-performance alignment state (window position,
    // row buffers, run-length counters, published position) without
    // touching referenceChromagram or tuningCompensator. Shared by
    // loadReferenceChromagram (after installing a new reference) and reset.
    void resetAlignmentState();

    // Slides the sliding reference window forward by slideAmount frames:
    // preserves the single boundary scalar needed by the next call's
    // leftmost-column recurrence, shifts the surviving columns of
    // currentRowCost down, and marks the newly exposed columns as
    // never-visited (+infinity) so the next call's row-only move into them
    // is correctly disallowed. O(windowWidthFrames), never allocates.
    void slideWindowForward(std::size_t slideAmount);

    void publishAlignmentPosition(double referenceFrameIndex, double alignmentConfidence,
                                   double cumulativeDistortionCost) noexcept;

    std::size_t windowWidthFrames;
    std::size_t referenceCalibrationFrameCount;
    double stallStepPenalty;
    double skipStepPenalty;
    std::size_t maxPlausibleSkipPerFrame;
    std::size_t maxRunLengthFrames;
    double runLengthEscalationPenalty;
    double confidenceSmoothingFactor;

    Chromagram referenceChromagram{};

    // The two DTW recurrence row buffers, each sized to windowWidthFrames
    // exactly once (in the constructor) and never reallocated afterward.
    // previousRowCost/currentRowCost are pointers into these two buffers
    // that are swapped (not copied) at the end of every call, so advancing
    // the recurrence by one live frame costs zero allocation and zero
    // per-call O(W) copying beyond the sweep itself.
    std::vector<double> rowStorageA;
    std::vector<double> rowStorageB;
    std::vector<double>* previousRowCost = nullptr;
    std::vector<double>* currentRowCost = nullptr;

    // Absolute reference frame index that relative index 0 of the row
    // buffers currently corresponds to.
    std::size_t windowStartReferenceIndex = 0;

    // D(t-1, windowStartReferenceIndex - 1): the single boundary scalar
    // carried forward across window slides so the leftmost in-window column
    // still has a well-defined diagonal/skip predecessor. +infinity when
    // windowStartReferenceIndex == 0 (no predecessor exists before the
    // start of the piece).
    double costBeforeWindowStart = 0.0;

    bool hasIngestedFirstFrame = false;
    std::size_t currentBestReferenceIndexAbsolute = 0;
    std::size_t consecutiveStallFrames = 0;
    std::size_t consecutiveSkipFrames = 0;
    bool hasEmaLocalDistance = false;
    double emaLocalDistance = 0.0;

    // Published via relaxed-store/acquire-load atomics rather than a lock,
    // since ingestLiveChromaVector (the analysis thread) and
    // getCurrentAlignmentPosition (typically polled by a UI/render thread
    // for page-turn timing) are expected to run concurrently.
    std::atomic<double> publishedReferenceFrameIndex{0.0};
    std::atomic<double> publishedAlignmentConfidence{0.0};
    std::atomic<double> publishedCumulativeDistortionCost{0.0};

    ChromaRotationTuningCompensator tuningCompensator;
};

}  // namespace scorefollower::dsp
