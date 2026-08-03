#include "NearestFrameAlignmentEngine.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <optional>

namespace scorefollower::dsp {

namespace {

double computeCosineSimilarity(const ChromaVector& firstVector, const ChromaVector& secondVector) {
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
        return 0.0;
    }
    return dotProduct / denominator;
}

// Applies the tuning compensator's resolved whole-semitone offset, following
// the sign convention documented in ChromaRotationTuningCompensator.cpp:
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

NearestFrameAlignmentEngine::NearestFrameAlignmentEngine(std::size_t searchWindowFramesValue,
                                                           std::size_t referenceCalibrationFrameCountValue)
    : searchWindowFrames(searchWindowFramesValue), referenceCalibrationFrameCount(referenceCalibrationFrameCountValue) {}

void NearestFrameAlignmentEngine::loadReferenceChromagram(const Chromagram& newReferenceChromagram) {
    referenceChromagram = newReferenceChromagram;

    currentReferenceFrameIndex = 0;
    cumulativeDistortionCost = 0.0;
    lastAlignmentConfidence = 0.0;

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

void NearestFrameAlignmentEngine::ingestLiveChromaVector(const ChromaVector& liveChromaVector) {
    if (referenceChromagram.frames.empty()) {
        return;  // No reference loaded yet; nothing to align against.
    }

    int resolvedShiftSemitones = 0;
    if (const std::optional<double> resolvedOffset = tuningCompensator.resolveTuningOffsetSemitones(); resolvedOffset.has_value()) {
        resolvedShiftSemitones = static_cast<int>(std::lround(*resolvedOffset));
    }
    const ChromaVector correctedLiveVector = applyTuningCorrection(liveChromaVector, resolvedShiftSemitones);

    const std::size_t referenceFrameCount = referenceChromagram.frames.size();
    const std::size_t searchStart =
        (currentReferenceFrameIndex > searchWindowFrames) ? (currentReferenceFrameIndex - searchWindowFrames) : 0;
    const std::size_t searchEnd = std::min(currentReferenceFrameIndex + searchWindowFrames, referenceFrameCount - 1);

    double bestSimilarity = -2.0;  // Below the valid [-1, 1] range of cosine similarity.
    std::size_t bestFrameIndex = currentReferenceFrameIndex;
    for (std::size_t candidateFrameIndex = searchStart; candidateFrameIndex <= searchEnd; ++candidateFrameIndex) {
        const double similarity = computeCosineSimilarity(correctedLiveVector, referenceChromagram.frames[candidateFrameIndex]);
        if (similarity > bestSimilarity) {
            bestSimilarity = similarity;
            bestFrameIndex = candidateFrameIndex;
        }
    }

    currentReferenceFrameIndex = bestFrameIndex;
    lastAlignmentConfidence = bestSimilarity;
    cumulativeDistortionCost += (1.0 - bestSimilarity);
}

AlignmentPosition NearestFrameAlignmentEngine::getCurrentAlignmentPosition() const {
    AlignmentPosition position{};
    position.referenceFrameIndex = static_cast<double>(currentReferenceFrameIndex);
    position.alignmentConfidence = lastAlignmentConfidence;
    position.cumulativeDistortionCost = cumulativeDistortionCost;
    return position;
}

AutoCorrelationTuningCompensator& NearestFrameAlignmentEngine::getTuningCompensator() {
    return tuningCompensator;
}

void NearestFrameAlignmentEngine::reset() {
    // Deliberately does not reset tuningCompensator or unload
    // referenceChromagram: a resolved tuning offset and the loaded score are
    // both expected to remain valid for the rest of the performance, per
    // AlignmentEngine::reset's documented contract.
    currentReferenceFrameIndex = 0;
    cumulativeDistortionCost = 0.0;
    lastAlignmentConfidence = 0.0;
}

}  // namespace scorefollower::dsp
