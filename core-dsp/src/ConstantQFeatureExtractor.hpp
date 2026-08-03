// Concrete FeatureExtractor computing a Constant-Q Transform based
// chromagram. See the .cpp file for the full derivation of the underlying
// math and its trade-offs versus a recursive-downsampling implementation
// such as librosa.cqt.
#pragma once

#include "Chromagram.hpp"
#include "FeatureExtractor.hpp"
#include "SlidingSampleWindow.hpp"
#include "SpectralBackend.hpp"

#include <complex>
#include <cstddef>
#include <memory>
#include <optional>
#include <vector>

namespace scorefollower::dsp {

class ConstantQFeatureExtractor final : public FeatureExtractor {
public:
    // spectralBackend must not be null. Pass createDefaultSpectralBackend()
    // for the library's built-in, dependency-free FFT, or inject a
    // platform-accelerated implementation (Accelerate/vDSP, a NEON-tuned
    // backend, and so on).
    explicit ConstantQFeatureExtractor(std::shared_ptr<SpectralBackend> spectralBackend);

    void configure(const FeatureExtractionConfiguration& configuration) override;
    void ingestAudioFrame(const float* audioSamples, std::size_t sampleCount) override;
    std::optional<ChromaVector> pollLatestChromaVector() override;
    [[nodiscard]] const Chromagram& getAccumulatedChromagram() const override;
    void reset() override;

private:
    // Precomputed analysis state for one Constant-Q octave, built once in
    // configure() and read-only thereafter until the next configure()/reset().
    struct OctaveAnalysisState {
        std::size_t transformLength = 0;
        // kernelSpectraByBin[binWithinOctave] is the transformLength-sized
        // spectrum of that bin's Hann-windowed complex exponential kernel.
        std::vector<std::vector<std::complex<float>>> kernelSpectraByBin;
        // Reused every analysis hop; sized once here to keep ingestAudioFrame
        // allocation-free.
        std::vector<float> audioSegmentScratch;
        std::vector<std::complex<float>> audioSpectrumScratch;
    };

    void buildOctaveKernelBank(std::size_t octaveIndex, OctaveAnalysisState& octaveState);
    void computeAndAppendAnalysisFrame();
    static void foldMagnitudesIntoChromaVector(const std::vector<float>& allBinMagnitudes,
                                                std::size_t binsPerOctave,
                                                ChromaVector& outputChromaVector);

    std::shared_ptr<SpectralBackend> spectralBackend;
    FeatureExtractionConfiguration configuration{};

    internal::SlidingSampleWindow audioHistory;
    std::vector<OctaveAnalysisState> octaveStates;
    // Flattened as [octaveIndex * binsPerOctave + binWithinOctave]; reused
    // every hop.
    std::vector<float> binMagnitudeScratch;

    std::size_t totalSamplesIngested = 0;
    std::size_t samplesAccountedForByAnalysisFrames = 0;

    Chromagram accumulatedChromagram{};
    std::optional<ChromaVector> pendingChromaVector;
};

}  // namespace scorefollower::dsp
