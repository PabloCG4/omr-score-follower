// Concrete AutoCorrelationTuningCompensator resolving a whole-semitone
// rotation offset between the live chroma stream and the reference score's
// chroma profile via Pearson correlation. See the .cpp file for the full
// derivation, its sign convention, and its documented resolution limit
// (whole semitones only, not fractional/cents-level tuning drift).
#pragma once

#include "AlignmentEngine.hpp"
#include "Chromagram.hpp"

#include <array>
#include <cstddef>
#include <optional>

namespace scorefollower::dsp {

class ChromaRotationTuningCompensator final : public AutoCorrelationTuningCompensator {
public:
    // minimumCalibrationFrameCount: number of calibration frames that must
    // be ingested before a resolution attempt is made. This class has no
    // direct knowledge of the hop rate, so the "first few seconds" window
    // described by the interface is expressed here in frames; the owning
    // AlignmentEngine implementation is expected to size this from its
    // configured hop rate (for example, roughly 100 frames at a ~43 Hz hop
    // rate is about 2.3 seconds).
    // minimumCorrelationConfidence: the Pearson correlation coefficient a
    // candidate shift must exceed before it is latched; below this
    // threshold the compensator keeps accumulating rather than committing
    // to a possibly-wrong offset.
    explicit ChromaRotationTuningCompensator(std::size_t minimumCalibrationFrameCount = 100,
                                              double minimumCorrelationConfidence = 0.3);

    void configureSearchRange(double minimumSemitoneOffset, double maximumSemitoneOffset) override;
    void ingestCalibrationChromaVector(const ChromaVector& liveChromaVector) override;
    [[nodiscard]] std::optional<double> resolveTuningOffsetSemitones() const override;
    [[nodiscard]] bool hasResolvedTuningOffset() const override;
    void reset() override;

    // Not part of the abstract interface: supplies the aggregate chroma
    // profile of the reference score's calibration window. Called by the
    // owning AlignmentEngine implementation from inside its own
    // loadReferenceChromagram, since AutoCorrelationTuningCompensator's
    // public contract intentionally has no notion of "the reference
    // chromagram" (only of the live stream being calibrated).
    void setReferenceProfile(const std::array<double, PitchClassCount>& profile);

private:
    // Runs the correlation search if a resolution has not already been
    // latched and enough calibration data is available. Idempotent and safe
    // to call from both resolveTuningOffsetSemitones and
    // hasResolvedTuningOffset.
    void attemptResolution() const;

    std::size_t minimumCalibrationFrameCount;
    double minimumCorrelationConfidence;

    int minimumShiftBins = -(static_cast<int>(PitchClassCount) / 2);
    int maximumShiftBins = static_cast<int>(PitchClassCount) / 2 - 1;

    std::array<double, PitchClassCount> accumulatedLiveProfile{};
    std::size_t accumulatedFrameCount = 0;

    std::array<double, PitchClassCount> referenceProfile{};
    bool hasReferenceProfile = false;

    // Mutable so the const query methods can cache the first successful
    // resolution without needing to be logically non-const: querying
    // whether a resolution exists does not change what has been observed,
    // only whether that observation has already crossed the latch
    // threshold.
    mutable std::optional<double> latchedOffsetSemitones;
};

}  // namespace scorefollower::dsp
