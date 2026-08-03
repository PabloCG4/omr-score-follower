// Shared acoustic feature data structures produced by FeatureExtractor
// implementations and consumed by AlignmentEngine implementations. Kept in
// its own header, independent of both interfaces, to avoid duplicating the
// definition and to keep the feature representation reusable by future
// components (e.g. offline reference-chromagram generation tools).
#pragma once

#include <array>
#include <cstddef>
#include <vector>

namespace scorefollower::dsp {

// Number of pitch classes in a standard twelve-tone equal temperament
// chromagram (C, C#, D, D#, E, F, F#, G, G#, A, A#, B).
inline constexpr std::size_t PitchClassCount = 12;

// Energy distribution across the twelve pitch classes for a single analysis
// frame, mirroring one column of the chromagrams produced by the Python
// research pipeline (see research/chromagram_extractor.py).
struct ChromaVector {
    std::array<float, PitchClassCount> pitchClassEnergies{};
};

// A full sequence of chroma vectors accumulated over time, together with the
// timing metadata required to map a frame index back to a wall-clock time.
struct Chromagram {
    std::vector<ChromaVector> frames;
    double sampleRateHz = 0.0;
    std::size_t hopLengthSamples = 0;

    // Tuning deviation, in cents, estimated for the recording this chromagram
    // was extracted from, relative to the standard A4 = 440 Hz reference.
    // Zero until an actual estimate has been assigned by the extraction or
    // alignment pipeline.
    double estimatedTuningDeviationCents = 0.0;

    // Maps a frame index to its timestamp, in seconds, from the start of the
    // analyzed audio signal. Returns zero if the sample rate has not been set.
    [[nodiscard]] double getFrameTimestampSeconds(std::size_t frameIndex) const noexcept {
        if (sampleRateHz <= 0.0) {
            return 0.0;
        }
        return (static_cast<double>(frameIndex) * static_cast<double>(hopLengthSamples)) / sampleRateHz;
    }
};

}  // namespace scorefollower::dsp
