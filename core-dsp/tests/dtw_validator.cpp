// Permanent command-line validator for the OnlineDtwAlignmentEngine.
//
// Purpose: rather than relying on a temporary, throwaway smoke test to
// confirm the Online DTW alignment engine tracks a live chroma stream
// correctly, this executable makes that validation a permanent, repeatable
// part of the codebase. It requires no external WAV files: a deterministic
// synthetic reference Chromagram (a short sequence of four distinct chords)
// is generated in-process, and three live-performance scenarios are
// simulated against it, each designed to exercise one of the alignment
// engine's core real-time-robustness properties:
//
//   Scenario A (tempo-stretched): every chord is held longer than the
//   reference, verifying diagonal tracking under a slower-than-reference
//   tempo without losing the correct chord.
//
//   Scenario B (stalled): one chord is held far longer than the reference,
//   verifying the stall step-cost penalty and its run-length safeguard keep
//   the tracked position pinned to the correct chord during the stall
//   rather than drifting ahead, and that tracking resumes correctly once
//   the performance moves on.
//
//   Scenario C (skipped): one chord is omitted entirely from the live
//   performance, verifying the skip step-cost penalty allows the tracked
//   position to advance past the skipped chord's reference segment rather
//   than remaining stuck trying to match it.
//
// The tracked AlignmentPosition::referenceFrameIndex is printed
// progressively as each live frame is ingested, so the tracking, waiting,
// and recovery behavior described above can be inspected visually, in
// addition to the automated pass/fail check printed at the end of each
// scenario.
#include "AlignmentEngine.hpp"
#include "AlignmentEngineFactory.hpp"
#include "Chromagram.hpp"

#include <algorithm>
#include <cstdio>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace {

using scorefollower::dsp::AlignmentEngine;
using scorefollower::dsp::AlignmentPosition;
using scorefollower::dsp::ChromaVector;
using scorefollower::dsp::Chromagram;
using scorefollower::dsp::createAlignmentEngine;

// A single chord definition: a human-readable name and the pitch classes
// (0 = C, 1 = C#, ..., 11 = B) that are active when it sounds.
struct NamedChord {
    const char* name;
    std::vector<int> pitchClasses;
};

constexpr std::size_t FramesPerChord = 50;

// The deterministic four-chord progression every scenario below aligns
// against: C major, G major, A minor, F major.
const std::vector<NamedChord>& referenceChordSequence() {
    static const std::vector<NamedChord> chords = {
        {"C major", {0, 4, 7}},
        {"G major", {7, 11, 2}},
        {"A minor", {9, 0, 4}},
        {"F major", {5, 9, 0}},
    };
    return chords;
}

ChromaVector makeChordChromaVector(const NamedChord& chord) {
    ChromaVector chromaVector{};
    for (int pitchClass : chord.pitchClasses) {
        chromaVector.pitchClassEnergies[static_cast<std::size_t>(pitchClass)] = 1.0F;
    }
    return chromaVector;
}

// Builds the synthetic reference Chromagram: each chord in
// referenceChordSequence held for FramesPerChord frames, back to back.
Chromagram buildReferenceChromagram() {
    Chromagram referenceChromagram;
    referenceChromagram.sampleRateHz = 22050.0;
    referenceChromagram.hopLengthSamples = 512;
    for (const NamedChord& chord : referenceChordSequence()) {
        const ChromaVector chordChromaVector = makeChordChromaVector(chord);
        for (std::size_t frameIndex = 0; frameIndex < FramesPerChord; ++frameIndex) {
            referenceChromagram.frames.push_back(chordChromaVector);
        }
    }
    return referenceChromagram;
}

// Maps an absolute reference frame index back to the chord index (into
// referenceChordSequence) that frame belongs to.
std::size_t chordIndexForReferenceFrame(std::size_t referenceFrameIndex) {
    const std::size_t lastChordIndex = referenceChordSequence().size() - 1;
    return std::min(referenceFrameIndex / FramesPerChord, lastChordIndex);
}

// One entry of a simulated live performance: play referenceChordIndex's
// chord for frameCount consecutive live frames.
struct LiveChordSegment {
    std::size_t referenceChordIndex;
    std::size_t frameCount;
};

// Feeds livePerformancePlan through a freshly constructed AlignmentEngine
// loaded with the standard reference chord progression, printing the
// tracked AlignmentPosition progressively (decimated to a fixed maximum
// number of printed rows, mirroring cqt_validator's table format), then
// checks that the final tracked chord matches expectedFinalChordIndex.
void runAlignmentScenario(const std::string& scenarioTitle, const std::string& scenarioDescription,
                           const std::vector<LiveChordSegment>& livePerformancePlan,
                           std::size_t expectedFinalChordIndex) {
    std::printf("\n=== %s ===\n%s\n\n", scenarioTitle.c_str(), scenarioDescription.c_str());

    const Chromagram referenceChromagram = buildReferenceChromagram();
    const std::unique_ptr<AlignmentEngine> alignmentEngine = createAlignmentEngine();
    alignmentEngine->loadReferenceChromagram(referenceChromagram);

    std::size_t totalLiveFrameCount = 0;
    for (const LiveChordSegment& segment : livePerformancePlan) {
        totalLiveFrameCount += segment.frameCount;
    }

    constexpr std::size_t maximumRowsToPrint = 50;
    const std::size_t printStride = (totalLiveFrameCount > maximumRowsToPrint) ? (totalLiveFrameCount / maximumRowsToPrint) : 1;

    std::printf("%10s  %-10s  %14s  %12s  %16s\n", "LiveFrame", "LiveChord", "RefFrameIdx", "Confidence",
                "CumulativeCost");

    std::size_t liveFrameCounter = 0;
    for (const LiveChordSegment& segment : livePerformancePlan) {
        const NamedChord& chord = referenceChordSequence()[segment.referenceChordIndex];
        const ChromaVector liveChromaVector = makeChordChromaVector(chord);

        for (std::size_t frameIndex = 0; frameIndex < segment.frameCount; ++frameIndex) {
            alignmentEngine->ingestLiveChromaVector(liveChromaVector);

            if (liveFrameCounter % printStride == 0) {
                const AlignmentPosition position = alignmentEngine->getCurrentAlignmentPosition();
                std::printf("%10zu  %-10s  %14.2f  %12.2f  %16.3f\n", liveFrameCounter, chord.name,
                            position.referenceFrameIndex, position.alignmentConfidence,
                            position.cumulativeDistortionCost);
            }
            ++liveFrameCounter;
        }
    }

    const AlignmentPosition finalPosition = alignmentEngine->getCurrentAlignmentPosition();
    const std::size_t clampedFinalReferenceFrameIndex =
        std::min(static_cast<std::size_t>(finalPosition.referenceFrameIndex), referenceChromagram.frames.size() - 1);
    const std::size_t trackedFinalChordIndex = chordIndexForReferenceFrame(clampedFinalReferenceFrameIndex);
    const bool scenarioPassed = (trackedFinalChordIndex == expectedFinalChordIndex);

    std::printf("\nFinal tracked reference frame: %.2f (chord: %s)\n", finalPosition.referenceFrameIndex,
                referenceChordSequence()[trackedFinalChordIndex].name);
    std::printf("[%s] Expected final chord: %s\n\n", scenarioPassed ? "PASS" : "FAIL",
                referenceChordSequence()[expectedFinalChordIndex].name);
}

}  // namespace

int main() {
    const std::vector<NamedChord>& chords = referenceChordSequence();
    const std::size_t lastChordIndex = chords.size() - 1;

    std::printf("Online DTW Validator: reference progression = ");
    for (std::size_t chordIndex = 0; chordIndex < chords.size(); ++chordIndex) {
        std::printf("%s%s", chords[chordIndex].name, (chordIndex + 1 < chords.size()) ? " -> " : "");
    }
    std::printf(" (%zu frames/chord, %zu frames total)\n", FramesPerChord, chords.size() * FramesPerChord);

    // Scenario A: tempo-stretched performance. Every chord is held 1.3x
    // longer than the reference tempo, simulating a musician playing
    // slightly slower than the recorded/rendered reference.
    {
        std::vector<LiveChordSegment> livePerformancePlan;
        const std::size_t stretchedFrameCount = static_cast<std::size_t>(static_cast<double>(FramesPerChord) * 1.3);
        for (std::size_t chordIndex = 0; chordIndex < chords.size(); ++chordIndex) {
            livePerformancePlan.push_back({chordIndex, stretchedFrameCount});
        }
        runAlignmentScenario(
            "Scenario A: Tempo-Stretched Performance",
            "Every chord is held 1.3x longer than the reference tempo. The tracked reference position "
            "should advance at a proportionally slower rate but never lose the correct chord.",
            livePerformancePlan, lastChordIndex);
    }

    // Scenario B: stalled performance. The second chord (G major) is held
    // 5x longer than the reference, simulating a musician sustaining a
    // chord far longer than notated (for example, a fermata or a memory
    // lapse), which should trigger the engine's stall step-cost penalty.
    {
        std::vector<LiveChordSegment> livePerformancePlan;
        for (std::size_t chordIndex = 0; chordIndex < chords.size(); ++chordIndex) {
            const std::size_t frameCount = (chordIndex == 1) ? (FramesPerChord * 5) : FramesPerChord;
            livePerformancePlan.push_back({chordIndex, frameCount});
        }
        runAlignmentScenario(
            "Scenario B: Stalled Performance",
            "The second chord (G major) is held 5x longer than the reference. The tracked reference "
            "position should stay pinned within that chord's segment during the stall, then resume "
            "advancing correctly once the performance moves on.",
            livePerformancePlan, lastChordIndex);
    }

    // Scenario C: skipped performance. The second chord (G major) is
    // omitted entirely, simulating a musician skipping ahead (for example,
    // a cut section), which should trigger the engine's skip step-cost
    // penalty.
    {
        std::vector<LiveChordSegment> livePerformancePlan;
        for (std::size_t chordIndex = 0; chordIndex < chords.size(); ++chordIndex) {
            if (chordIndex == 1) {
                continue;
            }
            livePerformancePlan.push_back({chordIndex, FramesPerChord});
        }
        runAlignmentScenario(
            "Scenario C: Skipped Performance",
            "The second chord (G major) is skipped entirely. The tracked reference position should "
            "advance past the skipped chord's reference segment rather than remaining stuck trying to "
            "match it.",
            livePerformancePlan, lastChordIndex);
    }

    return 0;
}
