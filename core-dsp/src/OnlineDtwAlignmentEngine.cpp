#include "OnlineDtwAlignmentEngine.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <optional>

namespace scorefollower::dsp {

namespace {

constexpr double PositiveInfinity = std::numeric_limits<double>::infinity();

// Cosine distance: 1 - cosineSimilarity. For the non-negative chroma
// energies produced by FeatureExtractor implementations, cosine similarity
// is bounded to [0, 1], so this local distance is bounded to [0, 1] as
// well, keeping the DTW recurrence's accumulated cost predictable in
// magnitude over a multi-minute performance.
double computeCosineDistance(const ChromaVector& firstVector, const ChromaVector& secondVector) {
    double dotProduct = 0.0;
    double firstNormSquared = 0.0;
    double secondNormSquared = 0.0;
    for (std::size_t pitchClass = 0; pitchClass < PitchClassCount; ++pitchClass) {
        const double firstValue = firstVector.pitchClassEnergies[pitchClass];
        const double secondValue = secondVector.pitchClassEnergies[pitchClass];
        dotProduct += firstValue * secondValue;
        firstNormSquared += firstValue * firstValue;
        secondNormSquared += secondValue * secondValue;
    }

    const double denominator = std::sqrt(firstNormSquared) * std::sqrt(secondNormSquared);
    if (denominator < 1e-12) {
        return 1.0;  // One or both vectors are silent/near-zero; treat as maximally dissimilar.
    }
    // Clamped to [0, 1]: for numerically identical vectors, floating-point
    // rounding in the square roots above can push dotProduct / denominator
    // an infinitesimal amount above 1.0, which would otherwise surface as a
    // meaningless negative distance (and a "-0.000" cumulative cost display
    // artifact) instead of the mathematically exact zero.
    return std::clamp(1.0 - (dotProduct / denominator), 0.0, 1.0);
}

// Applies the tuning compensator's resolved whole-semitone offset, following
// the same sign convention documented in ChromaRotationTuningCompensator.cpp:
// correctedLive[q] = liveVector[(q + k) % 12].
ChromaVector applyTuningCorrection(const ChromaVector& liveChromaVector, int resolvedShiftSemitones) {
    if (resolvedShiftSemitones == 0) {
        return liveChromaVector;
    }
    ChromaVector correctedVector{};
    for (int pitchClass = 0; pitchClass < static_cast<int>(PitchClassCount); ++pitchClass) {
        const int sourceIndex =
            ((pitchClass + resolvedShiftSemitones) % static_cast<int>(PitchClassCount) + static_cast<int>(PitchClassCount)) %
            static_cast<int>(PitchClassCount);
        correctedVector.pitchClassEnergies[static_cast<std::size_t>(pitchClass)] =
            liveChromaVector.pitchClassEnergies[static_cast<std::size_t>(sourceIndex)];
    }
    return correctedVector;
}

}  // namespace

OnlineDtwAlignmentEngine::OnlineDtwAlignmentEngine(std::size_t windowWidthFramesValue,
                                                    std::size_t referenceCalibrationFrameCountValue,
                                                    double stallStepPenaltyValue, double skipStepPenaltyValue,
                                                    std::size_t maxPlausibleSkipPerFrameValue,
                                                    std::size_t maxRunLengthFramesValue,
                                                    double runLengthEscalationPenaltyValue,
                                                    double confidenceSmoothingFactorValue)
    : windowWidthFrames(windowWidthFramesValue),
      referenceCalibrationFrameCount(referenceCalibrationFrameCountValue),
      stallStepPenalty(stallStepPenaltyValue),
      skipStepPenalty(skipStepPenaltyValue),
      maxPlausibleSkipPerFrame(maxPlausibleSkipPerFrameValue),
      maxRunLengthFrames(maxRunLengthFramesValue),
      runLengthEscalationPenalty(runLengthEscalationPenaltyValue),
      confidenceSmoothingFactor(confidenceSmoothingFactorValue) {
    // The only allocation in this class: two fixed-size row buffers, sized
    // once here and never reallocated. ingestLiveChromaVector only ever
    // swaps the previousRowCost/currentRowCost pointers between them and
    // mutates their contents in place.
    rowStorageA.resize(windowWidthFrames);
    rowStorageB.resize(windowWidthFrames);
    previousRowCost = &rowStorageA;
    currentRowCost = &rowStorageB;
}

void OnlineDtwAlignmentEngine::resetAlignmentState() {
    windowStartReferenceIndex = 0;
    costBeforeWindowStart = PositiveInfinity;
    hasIngestedFirstFrame = false;
    currentBestReferenceIndexAbsolute = 0;
    consecutiveStallFrames = 0;
    consecutiveSkipFrames = 0;
    hasEmaLocalDistance = false;
    emaLocalDistance = 0.0;

    std::fill(rowStorageA.begin(), rowStorageA.end(), PositiveInfinity);
    std::fill(rowStorageB.begin(), rowStorageB.end(), PositiveInfinity);
    previousRowCost = &rowStorageA;
    currentRowCost = &rowStorageB;

    publishAlignmentPosition(0.0, 0.0, 0.0);
}

void OnlineDtwAlignmentEngine::loadReferenceChromagram(const Chromagram& newReferenceChromagram) {
    referenceChromagram = newReferenceChromagram;
    resetAlignmentState();

    const std::size_t calibrationFrameCount = std::min(referenceCalibrationFrameCount, referenceChromagram.frames.size());
    std::array<double, PitchClassCount> referenceCalibrationProfile{};
    for (std::size_t frameIndex = 0; frameIndex < calibrationFrameCount; ++frameIndex) {
        for (std::size_t pitchClass = 0; pitchClass < PitchClassCount; ++pitchClass) {
            referenceCalibrationProfile[pitchClass] += referenceChromagram.frames[frameIndex].pitchClassEnergies[pitchClass];
        }
    }
    if (calibrationFrameCount > 0) {
        for (double& value : referenceCalibrationProfile) {
            value /= static_cast<double>(calibrationFrameCount);
        }
    }
    tuningCompensator.setReferenceProfile(referenceCalibrationProfile);
}

void OnlineDtwAlignmentEngine::slideWindowForward(std::size_t slideAmount) {
    if (slideAmount == 0) {
        return;
    }

    // currentRowCost[slideAmount - 1] is the accumulated cost of the column
    // (windowStartReferenceIndex + slideAmount - 1) that is about to be
    // evicted; that is exactly the boundary value the next call's leftmost
    // in-window column needs as its diagonal/skip predecessor.
    costBeforeWindowStart = (*currentRowCost)[slideAmount - 1];

    const std::size_t survivingColumnCount = windowWidthFrames - slideAmount;
    for (std::size_t index = 0; index < survivingColumnCount; ++index) {
        (*currentRowCost)[index] = (*currentRowCost)[index + slideAmount];
    }
    // Newly exposed columns at the window's trailing edge have never been
    // evaluated in what is about to become previousRowCost; +infinity
    // correctly disallows a row-only (stall) move into them until they have
    // been visited by at least one diagonal or skip move.
    for (std::size_t index = survivingColumnCount; index < windowWidthFrames; ++index) {
        (*currentRowCost)[index] = PositiveInfinity;
    }

    windowStartReferenceIndex += slideAmount;
}

void OnlineDtwAlignmentEngine::ingestLiveChromaVector(const ChromaVector& liveChromaVector) {
    const std::size_t referenceFrameCount = referenceChromagram.frames.size();
    if (referenceFrameCount == 0) {
        return;  // No reference loaded yet; nothing to align against.
    }

    int resolvedShiftSemitones = 0;
    if (const std::optional<double> resolvedOffset = tuningCompensator.resolveTuningOffsetSemitones(); resolvedOffset.has_value()) {
        resolvedShiftSemitones = static_cast<int>(std::lround(*resolvedOffset));
    }
    const ChromaVector correctedLiveVector = applyTuningCorrection(liveChromaVector, resolvedShiftSemitones);

    const std::size_t activeWindowWidth = std::min(windowWidthFrames, referenceFrameCount - windowStartReferenceIndex);

    double bestCostInRow = PositiveInfinity;
    std::size_t bestRelativeIndex = 0;
    double bestLocalDistance = 0.0;

    for (std::size_t relativeIndex = 0; relativeIndex < activeWindowWidth; ++relativeIndex) {
        const std::size_t absoluteReferenceIndex = windowStartReferenceIndex + relativeIndex;
        const double localDistance = computeCosineDistance(correctedLiveVector, referenceChromagram.frames[absoluteReferenceIndex]);

        double accumulatedCost;
        if (!hasIngestedFirstFrame) {
            // Open-begin boundary condition (standard in subsequence-DTW
            // alignment): the performance is not forced to start exactly at
            // reference frame 0, tolerating a short lead-in silence/pickup.
            accumulatedCost = localDistance;
        } else {
            const double diagonalPredecessor =
                (relativeIndex > 0) ? (*previousRowCost)[relativeIndex - 1] : costBeforeWindowStart;
            const double leftPredecessorForSkip =
                (relativeIndex > 0) ? (*currentRowCost)[relativeIndex - 1] : costBeforeWindowStart;

            double stallPredecessor = (*previousRowCost)[relativeIndex] + stallStepPenalty;
            double skipPredecessor = leftPredecessorForSkip + skipStepPenalty;

            // Dixon-style MaxRunCount safeguard: once a degenerate run has
            // persisted for too long, escalate its penalty so the softer,
            // constant per-step penalty above is no longer enough to keep
            // choosing it, forcing the path back toward the diagonal.
            if (consecutiveStallFrames >= maxRunLengthFrames) {
                stallPredecessor +=
                    static_cast<double>(consecutiveStallFrames - maxRunLengthFrames + 1) * runLengthEscalationPenalty;
            }
            if (consecutiveSkipFrames >= maxRunLengthFrames) {
                skipPredecessor +=
                    static_cast<double>(consecutiveSkipFrames - maxRunLengthFrames + 1) * runLengthEscalationPenalty;
            }

            accumulatedCost = localDistance + std::min({diagonalPredecessor, stallPredecessor, skipPredecessor});
        }

        (*currentRowCost)[relativeIndex] = accumulatedCost;
        if (accumulatedCost < bestCostInRow) {
            bestCostInRow = accumulatedCost;
            bestRelativeIndex = relativeIndex;
            bestLocalDistance = localDistance;
        }
    }

    const std::size_t jBestAbsolute = windowStartReferenceIndex + bestRelativeIndex;

    if (hasIngestedFirstFrame) {
        const std::size_t advance = (jBestAbsolute >= currentBestReferenceIndexAbsolute)
                                         ? (jBestAbsolute - currentBestReferenceIndexAbsolute)
                                         : 0;
        consecutiveStallFrames = (advance == 0) ? (consecutiveStallFrames + 1) : 0;
        consecutiveSkipFrames = (advance > maxPlausibleSkipPerFrame) ? (consecutiveSkipFrames + 1) : 0;
    } else {
        consecutiveStallFrames = 0;
        consecutiveSkipFrames = 0;
    }
    currentBestReferenceIndexAbsolute = jBestAbsolute;
    hasIngestedFirstFrame = true;

    emaLocalDistance = hasEmaLocalDistance ? (confidenceSmoothingFactor * bestLocalDistance +
                                               (1.0 - confidenceSmoothingFactor) * emaLocalDistance)
                                            : bestLocalDistance;
    hasEmaLocalDistance = true;
    const double alignmentConfidence = std::clamp(1.0 - emaLocalDistance, 0.0, 1.0);

    publishAlignmentPosition(static_cast<double>(jBestAbsolute), alignmentConfidence, bestCostInRow);

    // Slide the window forward once the best-matching column has advanced
    // close enough to the trailing edge that continued progress would soon
    // run off the end of the currently retained band.
    constexpr std::size_t slideThresholdFrames = 20;
    constexpr std::size_t slideAmountFrames = 20;
    const bool windowIsFull = (activeWindowWidth == windowWidthFrames);
    const bool morePieceRemainsAhead = (windowStartReferenceIndex + windowWidthFrames) < referenceFrameCount;
    if (windowIsFull && morePieceRemainsAhead && (bestRelativeIndex + slideThresholdFrames >= windowWidthFrames)) {
        std::size_t actualSlideAmount = std::min(slideAmountFrames, referenceFrameCount - (windowStartReferenceIndex + windowWidthFrames));
        actualSlideAmount = std::min(actualSlideAmount, bestRelativeIndex);
        slideWindowForward(actualSlideAmount);
    }

    std::swap(previousRowCost, currentRowCost);
}

AlignmentPosition OnlineDtwAlignmentEngine::getCurrentAlignmentPosition() const {
    AlignmentPosition position{};
    position.referenceFrameIndex = publishedReferenceFrameIndex.load(std::memory_order_acquire);
    position.alignmentConfidence = publishedAlignmentConfidence.load(std::memory_order_acquire);
    position.cumulativeDistortionCost = publishedCumulativeDistortionCost.load(std::memory_order_acquire);
    return position;
}

void OnlineDtwAlignmentEngine::seekToReferenceFrame(double referenceFrameIndex) {
    const std::size_t referenceFrameCount = referenceChromagram.frames.size();
    if (referenceFrameCount == 0) {
        resetAlignmentState();
        return;
    }

    const double clampedFrameIndex = std::clamp(
        referenceFrameIndex, 0.0, static_cast<double>(referenceFrameCount - 1));
    const std::size_t targetAbsoluteIndex = static_cast<std::size_t>(std::floor(clampedFrameIndex));

    // Clear path / run-length / EMA state, then re-center the sliding window
    // so the seek target sits near the middle (or at the start of the piece).
    resetAlignmentState();

    const std::size_t halfWindow =
        (windowWidthFrames > 0) ? (windowWidthFrames / 2) : 0;
    std::size_t desiredStart = 0;
    if (targetAbsoluteIndex > halfWindow) {
        desiredStart = targetAbsoluteIndex - halfWindow;
    }
    const std::size_t maxStart =
        (referenceFrameCount > windowWidthFrames) ? (referenceFrameCount - windowWidthFrames) : 0;
    windowStartReferenceIndex = std::min(desiredStart, maxStart);
    currentBestReferenceIndexAbsolute = targetAbsoluteIndex;
    // hasIngestedFirstFrame remains false after resetAlignmentState: the next
    // live frame re-acquires with the open-begin condition inside the new window.

    publishAlignmentPosition(clampedFrameIndex, 0.0, 0.0);
}

void OnlineDtwAlignmentEngine::publishAlignmentPosition(double referenceFrameIndex, double alignmentConfidence,
                                                         double cumulativeDistortionCost) noexcept {
    publishedReferenceFrameIndex.store(referenceFrameIndex, std::memory_order_release);
    publishedAlignmentConfidence.store(alignmentConfidence, std::memory_order_release);
    publishedCumulativeDistortionCost.store(cumulativeDistortionCost, std::memory_order_release);
}

AutoCorrelationTuningCompensator& OnlineDtwAlignmentEngine::getTuningCompensator() {
    return tuningCompensator;
}

void OnlineDtwAlignmentEngine::reset() {
    // Deliberately does not reset tuningCompensator or unload
    // referenceChromagram: a resolved tuning offset and the loaded score are
    // both expected to remain valid for the rest of the performance, per
    // AlignmentEngine::reset's documented contract.
    resetAlignmentState();
}

}  // namespace scorefollower::dsp
