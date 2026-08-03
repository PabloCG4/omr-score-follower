// Minimal, explicitly temporary AlignmentEngine implementation. It performs
// a bounded-window nearest-neighbor cosine-similarity match on each
// incoming live chroma vector rather than a real Online Dynamic Time
// Warping (DTW) search: it has no notion of a monotonicity constraint, a
// step-cost function, or a globally cost-optimal warping path. It exists so
// the rest of the pipeline (FeatureExtractor -> AlignmentEngine ->
// AutoCorrelationTuningCompensator) is concrete and end-to-end testable
// while a real Online DTW engine (Dixon-style) is developed as a follow-up,
// dedicated task with its own search-window, step-condition, and distance-
// metric design.
#pragma once

#include "AlignmentEngine.hpp"
#include "ChromaRotationTuningCompensator.hpp"
#include "Chromagram.hpp"

#include <cstddef>

namespace scorefollower::dsp {

class NearestFrameAlignmentEngine final : public AlignmentEngine {
public:
    // searchWindowFrames: how far, in reference frames, the nearest-match
    // search looks on either side of the current position on each call to
    // ingestLiveChromaVector. Bounded and fixed, so the search itself never
    // allocates.
    // referenceCalibrationFrameCount: number of reference frames, starting
    // from the beginning of the piece, averaged to build the tuning
    // compensator's reference profile (mirrors the "first few seconds"
    // calibration window on the live side).
    explicit NearestFrameAlignmentEngine(std::size_t searchWindowFrames = 50,
                                          std::size_t referenceCalibrationFrameCount = 100);

    void loadReferenceChromagram(const Chromagram& referenceChromagram) override;
    void ingestLiveChromaVector(const ChromaVector& liveChromaVector) override;
    [[nodiscard]] AlignmentPosition getCurrentAlignmentPosition() const override;
    AutoCorrelationTuningCompensator& getTuningCompensator() override;
    void reset() override;

private:
    std::size_t searchWindowFrames;
    std::size_t referenceCalibrationFrameCount;

    Chromagram referenceChromagram{};
    std::size_t currentReferenceFrameIndex = 0;
    double cumulativeDistortionCost = 0.0;
    double lastAlignmentConfidence = 0.0;

    ChromaRotationTuningCompensator tuningCompensator;
};

}  // namespace scorefollower::dsp
