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
                                                    double confidenceSmoothingFactorValue,
                                                    double poorMatchLocalDistanceThresholdValue,
                                                    double poorMatchAdvancePenaltyValue)
    : windowWidthFrames(windowWidthFramesValue),
      referenceCalibrationFrameCount(referenceCalibrationFrameCountValue),
      stallStepPenalty(stallStepPenaltyValue),
      skipStepPenalty(skipStepPenaltyValue),
      maxPlausibleSkipPerFrame(maxPlausibleSkipPerFrameValue),
      maxRunLengthFrames(maxRunLengthFramesValue),
      runLengthEscalationPenalty(runLengthEscalationPenaltyValue),
      confidenceSmoothingFactor(confidenceSmoothingFactorValue),
      poorMatchLocalDistanceThreshold(poorMatchLocalDistanceThresholdValue),
      poorMatchAdvancePenalty(poorMatchAdvancePenaltyValue) {
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

    // Match-quality signals from the previous published state. Used both to
    // bias the recurrence (prefer stall on noise) and to hard-cap how far
    // the published reference index may advance on this live frame.
    const double previousPublishedConfidence =
        publishedAlignmentConfidence.load(std::memory_order_relaxed);
    const bool previousMatchIsPoor =
        hasEmaLocalDistance && (emaLocalDistance >= poorMatchLocalDistanceThreshold);
    const bool previousConfidenceIsPoor =
        previousPublishedConfidence < strictConfidenceThreshold;
    // Strict always forbids multi-frame skips; Rubato also forbids them while
    // the match is already in the amber/red band so silence cannot race.
    const bool skipDisallowed = (trackingMode == TrackingMode::Strict) || previousMatchIsPoor ||
                                previousConfidenceIsPoor;

    double bestCostInRow = PositiveInfinity;
    std::size_t bestRelativeIndex = 0;
    double bestLocalDistance = 0.0;

    for (std::size_t relativeIndex = 0; relativeIndex < activeWindowWidth; ++relativeIndex) {
        const std::size_t absoluteReferenceIndex = windowStartReferenceIndex + relativeIndex;
        const double localDistance =
            computeCosineDistance(correctedLiveVector, referenceChromagram.frames[absoluteReferenceIndex]);

        double accumulatedCost;
        if (!hasIngestedFirstFrame) {
            // Open-begin boundary condition (standard in subsequence-DTW
            // alignment): the performance is not forced to start exactly at
            // reference frame 0, tolerating a short lead-in silence/pickup.
            accumulatedCost = localDistance;
        } else {
            double diagonalPredecessor =
                (relativeIndex > 0) ? (*previousRowCost)[relativeIndex - 1] : costBeforeWindowStart;
            const double leftPredecessorForSkip =
                (relativeIndex > 0) ? (*currentRowCost)[relativeIndex - 1] : costBeforeWindowStart;

            double stallPredecessor = (*previousRowCost)[relativeIndex] + stallStepPenalty;
            double skipPredecessor = leftPredecessorForSkip + skipStepPenalty;

            // Local-distance-dependent advance penalty: a poor match at this
            // column must not be cheaper to reach by skipping or walking the
            // diagonal than by stalling on the previously tracked column.
            if (localDistance >= poorMatchLocalDistanceThreshold || previousMatchIsPoor) {
                diagonalPredecessor += poorMatchAdvancePenalty;
                skipPredecessor += poorMatchAdvancePenalty;
            }

            // Dixon-style MaxRunCount: escalate only while the match is still
            // good. Escalating stall during silence/wrong notes was the primary
            // runaway mechanism (forced forward progress on noise).
            if (!previousMatchIsPoor && !previousConfidenceIsPoor &&
                consecutiveStallFrames >= maxRunLengthFrames) {
                stallPredecessor +=
                    static_cast<double>(consecutiveStallFrames - maxRunLengthFrames + 1) *
                    runLengthEscalationPenalty;
            }
            if (consecutiveSkipFrames >= maxRunLengthFrames) {
                skipPredecessor +=
                    static_cast<double>(consecutiveSkipFrames - maxRunLengthFrames + 1) *
                    runLengthEscalationPenalty;
            }

            if (skipDisallowed) {
                skipPredecessor = PositiveInfinity;
            }

            accumulatedCost =
                localDistance + std::min({diagonalPredecessor, stallPredecessor, skipPredecessor});
        }

        (*currentRowCost)[relativeIndex] = accumulatedCost;
        if (accumulatedCost < bestCostInRow) {
            bestCostInRow = accumulatedCost;
            bestRelativeIndex = relativeIndex;
            bestLocalDistance = localDistance;
        }
    }

    std::size_t jBestAbsolute = windowStartReferenceIndex + bestRelativeIndex;

    emaLocalDistance = hasEmaLocalDistance ? (confidenceSmoothingFactor * bestLocalDistance +
                                               (1.0 - confidenceSmoothingFactor) * emaLocalDistance)
                                            : bestLocalDistance;
    hasEmaLocalDistance = true;
    const double alignmentConfidence = std::clamp(1.0 - emaLocalDistance, 0.0, 1.0);

    // Hard advance cap: while confidence is below the Strict / amber boundary,
    // the published reference index must not move forward (Rubato and Strict).
    // This is belt-and-suspenders with the recurrence bias above. Also covers
    // the open-begin frame after seek so a poor first match cannot teleport.
    const bool confidenceBlocksAdvance = alignmentConfidence < strictConfidenceThreshold;
    if (confidenceBlocksAdvance && jBestAbsolute > currentBestReferenceIndexAbsolute) {
        jBestAbsolute = currentBestReferenceIndexAbsolute;
        if (jBestAbsolute >= windowStartReferenceIndex) {
            bestRelativeIndex = jBestAbsolute - windowStartReferenceIndex;
        } else {
            bestRelativeIndex = 0;
            jBestAbsolute = windowStartReferenceIndex;
        }
    }

    // Strict gate: freeze the published index at the last good frame, keep
    // updating confidence for the UI, and never slide the DTW window.
    const bool strictGateActive =
        (trackingMode == TrackingMode::Strict) && confidenceBlocksAdvance;

    if (strictGateActive) {
        consecutiveStallFrames = hasIngestedFirstFrame ? (consecutiveStallFrames + 1) : 0;
        consecutiveSkipFrames = 0;
        hasIngestedFirstFrame = true;
        // Keep internal best pinned so recovery resumes from the stalled note.
        const double stalledReferenceFrameIndex =
            publishedReferenceFrameIndex.load(std::memory_order_relaxed);
        if (stalledReferenceFrameIndex >= 0.0) {
            currentBestReferenceIndexAbsolute =
                static_cast<std::size_t>(std::floor(stalledReferenceFrameIndex));
        }
        publishAlignmentPosition(stalledReferenceFrameIndex, alignmentConfidence, bestCostInRow);
    } else {
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

        publishAlignmentPosition(static_cast<double>(jBestAbsolute), alignmentConfidence, bestCostInRow);

        // Never slide while confidence is poor: sliding would drag the search
        // band away from the expected note and prevent recovery.
        if (!confidenceBlocksAdvance) {
            constexpr std::size_t slideThresholdFrames = 20;
            constexpr std::size_t slideAmountFrames = 20;
            const bool windowIsFull = (activeWindowWidth == windowWidthFrames);
            const bool morePieceRemainsAhead =
                (windowStartReferenceIndex + windowWidthFrames) < referenceFrameCount;
            if (windowIsFull && morePieceRemainsAhead &&
                (bestRelativeIndex + slideThresholdFrames >= windowWidthFrames)) {
                std::size_t actualSlideAmount = std::min(
                    slideAmountFrames, referenceFrameCount - (windowStartReferenceIndex + windowWidthFrames));
                actualSlideAmount = std::min(actualSlideAmount, bestRelativeIndex);
                slideWindowForward(actualSlideAmount);
            }
        }
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

void OnlineDtwAlignmentEngine::setTrackingMode(TrackingMode trackingModeValue) {
    trackingMode = trackingModeValue;
}

void OnlineDtwAlignmentEngine::setStrictConfidenceThreshold(double threshold) {
    if (!std::isfinite(threshold)) {
        return;
    }
    strictConfidenceThreshold = std::clamp(threshold, 0.0, 1.0);
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
