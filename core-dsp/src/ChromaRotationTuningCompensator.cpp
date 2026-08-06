// Sign convention (kept consistent with NearestFrameAlignmentEngine, the
// only current consumer of a resolved offset): resolveTuningOffsetSemitones
// returns an integer k (returned as a double for interface-forward-
// compatibility with a future finer-grained resolution) such that
//
//     referenceProfile[(p - k + 12) % 12]
//
// best correlates with the observed mean live chroma profile at pitch
// class p, for p in [0, 12). Equivalently: the live instrument is reporting
// energy k pitch-class bins higher than the reference expects, so a live
// chroma vector can be corrected back into the reference's frame of
// reference via
//
//     correctedLive[q] = liveVector[(q + k) % 12].
//
// Resolution limit: because this class only ever sees the folded, 12-bin
// ChromaVector (per AlignmentEngine.hpp's public contract), it can only
// detect whole-semitone-bin misalignments (for example, a transposing
// instrument, or a systematic one-semitone bin-mapping error). Fractional,
// cents-level tuning drift -- the kind measured by the Python research
// pipeline's librosa.estimate_tuning (see research/chromagram_extractor.py)
// -- is a finer-grained problem that requires operating before chroma
// folding, at the Constant-Q bin level, and is out of scope for this
// chroma-vector-based interface.
#include "ChromaRotationTuningCompensator.hpp"

#include <algorithm>
#include <cmath>
#include <utility>

namespace scorefollower::dsp {

namespace {

double computePearsonCorrelation(const std::array<double, PitchClassCount>& firstProfile,
                                  const std::array<double, PitchClassCount>& secondProfile) {
    double firstMean = 0.0;
    double secondMean = 0.0;
    for (std::size_t pitchClass = 0; pitchClass < PitchClassCount; ++pitchClass) {
        firstMean += firstProfile[pitchClass];
        secondMean += secondProfile[pitchClass];
    }
    firstMean /= static_cast<double>(PitchClassCount);
    secondMean /= static_cast<double>(PitchClassCount);

    double covariance = 0.0;
    double firstVariance = 0.0;
    double secondVariance = 0.0;
    for (std::size_t pitchClass = 0; pitchClass < PitchClassCount; ++pitchClass) {
        const double firstDelta = firstProfile[pitchClass] - firstMean;
        const double secondDelta = secondProfile[pitchClass] - secondMean;
        covariance += firstDelta * secondDelta;
        firstVariance += firstDelta * firstDelta;
        secondVariance += secondDelta * secondDelta;
    }

    const double denominator = std::sqrt(firstVariance * secondVariance);
    if (denominator < 1e-12) {
        return 0.0;  // One or both profiles are (near-)constant; correlation is undefined, treat as no match.
    }
    return covariance / denominator;
}

}  // namespace

ChromaRotationTuningCompensator::ChromaRotationTuningCompensator(std::size_t minimumCalibrationFrameCountValue,
                                                                   double minimumCorrelationConfidenceValue)
    : minimumCalibrationFrameCount(minimumCalibrationFrameCountValue),
      minimumCorrelationConfidence(minimumCorrelationConfidenceValue) {}

void ChromaRotationTuningCompensator::configureSearchRange(double minimumSemitoneOffset, double maximumSemitoneOffset) {
    constexpr int maximumMeaningfulShift = static_cast<int>(PitchClassCount) - 1;

    int requestedMinimum = static_cast<int>(std::lround(minimumSemitoneOffset));
    int requestedMaximum = static_cast<int>(std::lround(maximumSemitoneOffset));
    if (requestedMinimum > requestedMaximum) {
        std::swap(requestedMinimum, requestedMaximum);
    }

    minimumShiftBins = std::clamp(requestedMinimum, -maximumMeaningfulShift, maximumMeaningfulShift);
    maximumShiftBins = std::clamp(requestedMaximum, -maximumMeaningfulShift, maximumMeaningfulShift);
}

void ChromaRotationTuningCompensator::ingestCalibrationChromaVector(const ChromaVector& liveChromaVector) {
    if (latchedOffsetSemitones.has_value()) {
        return;  // Already resolved and latched; no need to keep accumulating.
    }
    for (std::size_t pitchClass = 0; pitchClass < PitchClassCount; ++pitchClass) {
        accumulatedLiveProfile[pitchClass] += liveChromaVector.pitchClassEnergies[pitchClass];
    }
    ++accumulatedFrameCount;
}

void ChromaRotationTuningCompensator::attemptResolution() const {
    if (latchedOffsetSemitones.has_value() || !hasReferenceProfile) {
        return;
    }
    if (accumulatedFrameCount < minimumCalibrationFrameCount) {
        return;
    }

    std::array<double, PitchClassCount> meanLiveProfile{};
    for (std::size_t pitchClass = 0; pitchClass < PitchClassCount; ++pitchClass) {
        meanLiveProfile[pitchClass] = accumulatedLiveProfile[pitchClass] / static_cast<double>(accumulatedFrameCount);
    }

    double bestCorrelation = -2.0;  // Below the valid [-1, 1] range of Pearson r, so the first candidate always wins initially.
    int bestShift = 0;

    for (int candidateShift = minimumShiftBins; candidateShift <= maximumShiftBins; ++candidateShift) {
        std::array<double, PitchClassCount> rotatedReference{};
        for (int pitchClass = 0; pitchClass < static_cast<int>(PitchClassCount); ++pitchClass) {
            const int sourceIndex =
                ((pitchClass - candidateShift) % static_cast<int>(PitchClassCount) + static_cast<int>(PitchClassCount)) %
                static_cast<int>(PitchClassCount);
            rotatedReference[static_cast<std::size_t>(pitchClass)] = referenceProfile[static_cast<std::size_t>(sourceIndex)];
        }

        const double correlation = computePearsonCorrelation(meanLiveProfile, rotatedReference);
        if (correlation > bestCorrelation) {
            bestCorrelation = correlation;
            bestShift = candidateShift;
        }
    }

    if (bestCorrelation >= minimumCorrelationConfidence) {
        latchedOffsetSemitones = static_cast<double>(bestShift);
    }
}

std::optional<double> ChromaRotationTuningCompensator::resolveTuningOffsetSemitones() const {
    attemptResolution();
    return latchedOffsetSemitones;
}

bool ChromaRotationTuningCompensator::hasResolvedTuningOffset() const {
    attemptResolution();
    return latchedOffsetSemitones.has_value();
}

void ChromaRotationTuningCompensator::latchTuningOffsetSemitones(double offsetSemitones) {
    // Whole-semitone bins only: matches the chroma-rotation resolution limit.
    const double roundedOffset = static_cast<double>(static_cast<int>(std::lround(offsetSemitones)));
    latchedOffsetSemitones = roundedOffset;
    // Host latch is authoritative; stop accumulating auto-calibration frames.
    accumulatedLiveProfile.fill(0.0);
    accumulatedFrameCount = 0;
}

void ChromaRotationTuningCompensator::reset() {
    accumulatedLiveProfile.fill(0.0);
    accumulatedFrameCount = 0;
    latchedOffsetSemitones.reset();
    // Deliberately does not clear referenceProfile/hasReferenceProfile: the
    // reference score's calibration profile does not change across
    // calibration attempts within the same loaded piece.
}

void ChromaRotationTuningCompensator::setReferenceProfile(const std::array<double, PitchClassCount>& profile) {
    referenceProfile = profile;
    hasReferenceProfile = true;
}

}  // namespace scorefollower::dsp
