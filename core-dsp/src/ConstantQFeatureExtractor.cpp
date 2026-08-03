// Implements a direct, per-octave-batched Constant-Q Transform, as opposed
// to the recursive per-octave downsampling scheme used internally by
// reference implementations such as librosa.cqt.
//
// Why not recursive downsampling: that approach requires a cascade of
// half-band anti-aliasing/decimation filters, per-octave filter state, and a
// frame-rate reconciliation step across octaves running at different
// effective sample rates. That is substantially more DSP machinery than
// fits one focused implementation pass. Critically, FeatureExtractor's own
// contract (see FeatureExtractor.hpp) documents ingestAudioFrame as running
// on a non-real-time analysis thread, so the hard constraint this class must
// satisfy is "no allocation, no locking, no unbounded blocking" -- not
// microsecond-level latency. A directly-computed, per-octave-batched CQT is
// simpler to implement and verify correctly while still honoring that
// constraint.
//
// The underlying math, computed once per octave per analysis hop:
//   1. Precompute (in configure(), the only allocating phase), for every
//      bin in every octave, a Hann-windowed complex exponential analysis
//      kernel at that bin's exact center frequency, zero-padded to that
//      octave's shared power-of-two FFT size, right-aligned so kernels of
//      different length within the same octave all end at the same time
//      instant (avoiding a bin-dependent group-delay offset). Its spectrum
//      is computed once via SpectralBackend::forwardTransformComplex and
//      cached.
//   2. At each analysis hop, take one real-input FFT of the most recent
//      audio samples per octave.
//   3. For each bin, compute sum_k AudioSpectrum(k) * conj(KernelSpectrum(k)),
//      scaled by 1/transformLength. By Parseval's/Plancherel's theorem for
//      the DFT, this is exactly equal to the time-domain inner product of
//      the raw audio segment against the (windowed) kernel -- i.e. exactly
//      the textbook Constant-Q correlation (Brown & Puckette, 1992) -- but
//      computed via one FFT per octave plus O(transformLength) dot products
//      per bin, rather than an O(kernelLength) direct convolution per bin.
//
// This dense per-bin dot product is not as cheap as it could be: real CQT
// kernels are narrowband, so their spectra are effectively sparse (most
// frequency bins carry negligible energy). Truncating each stored kernel
// spectrum to a small window around its center bin (as librosa's sparse
// kernel matrix does) would substantially reduce this cost. That
// optimization is deliberately deferred; see TECHNICAL_CHANGELOG.md.
#include "ConstantQFeatureExtractor.hpp"

#include "RadixTwoFft.hpp"

#include <algorithm>
#include <cmath>
#include <complex>
#include <stdexcept>
#include <utility>

namespace scorefollower::dsp {

namespace {

std::size_t computeKernelLengthSamples(double qualityFactor, double sampleRateHz, double binFrequencyHz) {
    const double lengthEstimate = qualityFactor * sampleRateHz / binFrequencyHz;
    return static_cast<std::size_t>(std::ceil(lengthEstimate));
}

std::size_t nextPowerOfTwo(std::size_t value) {
    std::size_t powerOfTwo = 1;
    while (powerOfTwo < value) {
        powerOfTwo <<= 1;
    }
    return powerOfTwo;
}

// Number of seconds of chroma frames to reserve up front in the accumulated
// Chromagram, to avoid reallocation for typical single-piece offline runs.
// This is a soft budget, not a hard limit: longer recordings simply cause
// Chromagram::frames (a std::vector) to grow normally.
constexpr double ReservedChromagramDurationSeconds = 600.0;

}  // namespace

ConstantQFeatureExtractor::ConstantQFeatureExtractor(std::shared_ptr<SpectralBackend> injectedSpectralBackend)
    : spectralBackend(std::move(injectedSpectralBackend)) {
    if (!spectralBackend) {
        throw std::invalid_argument("ConstantQFeatureExtractor requires a non-null SpectralBackend.");
    }
}

void ConstantQFeatureExtractor::configure(const FeatureExtractionConfiguration& newConfiguration) {
    configuration = newConfiguration;

    const std::size_t binsPerOctave = configuration.constantQBinsPerOctave;
    const std::size_t octaveCount = configuration.constantQOctaveCount;

    if (binsPerOctave == 0 || octaveCount == 0) {
        throw std::invalid_argument(
            "ConstantQFeatureExtractor requires a positive constantQBinsPerOctave and constantQOctaveCount.");
    }
    if (binsPerOctave % PitchClassCount != 0) {
        throw std::invalid_argument(
            "constantQBinsPerOctave must be an exact multiple of twelve so bins fold evenly into pitch classes.");
    }
    if (configuration.sampleRateHz <= 0.0 || configuration.constantQMinimumFrequencyHz <= 0.0) {
        throw std::invalid_argument("sampleRateHz and constantQMinimumFrequencyHz must both be positive.");
    }

    octaveStates.assign(octaveCount, OctaveAnalysisState{});

    std::size_t largestTransformLength = 0;
    for (std::size_t octaveIndex = 0; octaveIndex < octaveCount; ++octaveIndex) {
        buildOctaveKernelBank(octaveIndex, octaveStates[octaveIndex]);
        largestTransformLength = std::max(largestTransformLength, octaveStates[octaveIndex].transformLength);
    }

    audioHistory.prepare(largestTransformLength);
    binMagnitudeScratch.assign(octaveCount * binsPerOctave, 0.0F);

    totalSamplesIngested = 0;
    samplesAccountedForByAnalysisFrames = 0;
    pendingChromaVector.reset();

    accumulatedChromagram = Chromagram{};
    accumulatedChromagram.sampleRateHz = configuration.sampleRateHz;
    accumulatedChromagram.hopLengthSamples = configuration.hopLengthSamples;
    const double framesPerSecond = configuration.sampleRateHz / static_cast<double>(configuration.hopLengthSamples);
    accumulatedChromagram.frames.reserve(
        static_cast<std::size_t>(framesPerSecond * ReservedChromagramDurationSeconds));
}

void ConstantQFeatureExtractor::buildOctaveKernelBank(std::size_t octaveIndex, OctaveAnalysisState& octaveState) {
    const std::size_t binsPerOctave = configuration.constantQBinsPerOctave;
    const double sampleRateHz = configuration.sampleRateHz;

    // Constant-Q quality factor: the ratio of a bin's center frequency to
    // its bandwidth, identical for every bin at every octave by
    // construction. This is what gives the transform its name.
    const double qualityFactor = 1.0 / (std::pow(2.0, 1.0 / static_cast<double>(binsPerOctave)) - 1.0);
    const double tuningMultiplier = std::pow(2.0, configuration.tuningOffsetSemitones / 12.0);
    const double octaveBaseFrequencyHz =
        configuration.constantQMinimumFrequencyHz * std::pow(2.0, static_cast<double>(octaveIndex)) * tuningMultiplier;

    // The lowest bin in the octave (binWithinOctave == 0) needs the longest
    // kernel; every other bin in this octave shares this octave's FFT size.
    const std::size_t longestKernelLength = computeKernelLengthSamples(qualityFactor, sampleRateHz, octaveBaseFrequencyHz);
    std::size_t transformLength = nextPowerOfTwo(longestKernelLength);
    transformLength = std::min(transformLength, configuration.maximumTransformLength);
    transformLength = std::max<std::size_t>(transformLength, 2);

    octaveState.transformLength = transformLength;
    octaveState.kernelSpectraByBin.assign(binsPerOctave,
                                           std::vector<std::complex<float>>(transformLength, std::complex<float>(0.0F, 0.0F)));
    octaveState.audioSegmentScratch.assign(transformLength, 0.0F);
    octaveState.audioSpectrumScratch.assign(transformLength, std::complex<float>(0.0F, 0.0F));

    spectralBackend->prepareTransformLength(transformLength);

    std::vector<std::complex<float>> paddedKernelScratch(transformLength, std::complex<float>(0.0F, 0.0F));

    for (std::size_t binWithinOctave = 0; binWithinOctave < binsPerOctave; ++binWithinOctave) {
        const double binFrequencyHz =
            octaveBaseFrequencyHz * std::pow(2.0, static_cast<double>(binWithinOctave) / static_cast<double>(binsPerOctave));

        std::size_t kernelLength = computeKernelLengthSamples(qualityFactor, sampleRateHz, binFrequencyHz);
        kernelLength = std::clamp<std::size_t>(kernelLength, 1, transformLength);

        std::fill(paddedKernelScratch.begin(), paddedKernelScratch.end(), std::complex<float>(0.0F, 0.0F));

        // Right-align (zero-pad at the front): every bin's kernel, regardless
        // of its own length, ends at the same time instant (the most recent
        // sample), so folding octaves together later does not introduce a
        // bin-dependent group-delay offset.
        const std::size_t kernelStartOffset = transformLength - kernelLength;
        for (std::size_t sampleIndex = 0; sampleIndex < kernelLength; ++sampleIndex) {
            const double hannWindowValue =
                (kernelLength > 1)
                    ? 0.5 - 0.5 * std::cos(2.0 * internal::PiConstant * static_cast<double>(sampleIndex) /
                                           static_cast<double>(kernelLength - 1))
                    : 1.0;
            const double phase = -2.0 * internal::PiConstant * binFrequencyHz * static_cast<double>(sampleIndex) / sampleRateHz;
            const double normalization = 1.0 / static_cast<double>(kernelLength);
            paddedKernelScratch[kernelStartOffset + sampleIndex] =
                std::complex<float>(static_cast<float>(hannWindowValue * std::cos(phase) * normalization),
                                     static_cast<float>(hannWindowValue * std::sin(phase) * normalization));
        }

        spectralBackend->forwardTransformComplex(paddedKernelScratch.data(), octaveState.kernelSpectraByBin[binWithinOctave].data(),
                                                  transformLength);
    }
}

void ConstantQFeatureExtractor::ingestAudioFrame(const float* audioSamples, std::size_t sampleCount) {
    if (octaveStates.empty()) {
        throw std::logic_error("ConstantQFeatureExtractor::ingestAudioFrame called before configure().");
    }

    for (std::size_t sampleIndex = 0; sampleIndex < sampleCount; ++sampleIndex) {
        audioHistory.pushSample(audioSamples[sampleIndex]);
        ++totalSamplesIngested;

        const bool historyFullyPrimed = audioHistory.getAvailableSampleCount() >= audioHistory.getCapacity();
        const bool hopBoundaryReached =
            (totalSamplesIngested - samplesAccountedForByAnalysisFrames) >= configuration.hopLengthSamples;

        if (historyFullyPrimed && hopBoundaryReached) {
            computeAndAppendAnalysisFrame();
            samplesAccountedForByAnalysisFrames += configuration.hopLengthSamples;
        }
    }
}

void ConstantQFeatureExtractor::computeAndAppendAnalysisFrame() {
    const std::size_t binsPerOctave = configuration.constantQBinsPerOctave;

    for (std::size_t octaveIndex = 0; octaveIndex < octaveStates.size(); ++octaveIndex) {
        OctaveAnalysisState& octaveState = octaveStates[octaveIndex];

        audioHistory.copyMostRecentSamples(octaveState.transformLength, octaveState.audioSegmentScratch.data());
        spectralBackend->forwardTransform(octaveState.audioSegmentScratch.data(), octaveState.audioSpectrumScratch.data(),
                                           octaveState.transformLength);

        const double inverseTransformLength = 1.0 / static_cast<double>(octaveState.transformLength);
        for (std::size_t binWithinOctave = 0; binWithinOctave < binsPerOctave; ++binWithinOctave) {
            const std::vector<std::complex<float>>& kernelSpectrum = octaveState.kernelSpectraByBin[binWithinOctave];

            std::complex<double> correlationAccumulator(0.0, 0.0);
            for (std::size_t frequencyBin = 0; frequencyBin < octaveState.transformLength; ++frequencyBin) {
                correlationAccumulator += static_cast<std::complex<double>>(octaveState.audioSpectrumScratch[frequencyBin]) *
                                           std::conj(static_cast<std::complex<double>>(kernelSpectrum[frequencyBin]));
            }

            const double constantQMagnitude = std::abs(correlationAccumulator) * inverseTransformLength;
            binMagnitudeScratch[octaveIndex * binsPerOctave + binWithinOctave] = static_cast<float>(constantQMagnitude);
        }
    }

    ChromaVector chromaVector{};
    foldMagnitudesIntoChromaVector(binMagnitudeScratch, binsPerOctave, chromaVector);

    pendingChromaVector = chromaVector;
    accumulatedChromagram.frames.push_back(chromaVector);
}

void ConstantQFeatureExtractor::foldMagnitudesIntoChromaVector(const std::vector<float>& allBinMagnitudes,
                                                                std::size_t binsPerOctave,
                                                                ChromaVector& outputChromaVector) {
    outputChromaVector = ChromaVector{};

    const std::size_t binsPerPitchClass = binsPerOctave / PitchClassCount;
    for (std::size_t binIndex = 0; binIndex < allBinMagnitudes.size(); ++binIndex) {
        const std::size_t binWithinOctave = binIndex % binsPerOctave;
        const std::size_t pitchClass = binWithinOctave / binsPerPitchClass;
        outputChromaVector.pitchClassEnergies[pitchClass] += allBinMagnitudes[binIndex];
    }

    // Max-normalize, matching librosa's chroma_cqt default (norm=inf), so
    // downstream consumers (the alignment engine, diagnostic plots) see
    // values in a consistent [0, 1] range regardless of input signal level.
    float maximumEnergy = 0.0F;
    for (const float energy : outputChromaVector.pitchClassEnergies) {
        maximumEnergy = std::max(maximumEnergy, energy);
    }
    if (maximumEnergy > 1e-9F) {
        for (float& energy : outputChromaVector.pitchClassEnergies) {
            energy /= maximumEnergy;
        }
    }
}

std::optional<ChromaVector> ConstantQFeatureExtractor::pollLatestChromaVector() {
    if (!pendingChromaVector.has_value()) {
        return std::nullopt;
    }
    const ChromaVector result = *pendingChromaVector;
    pendingChromaVector.reset();
    return result;
}

const Chromagram& ConstantQFeatureExtractor::getAccumulatedChromagram() const {
    return accumulatedChromagram;
}

void ConstantQFeatureExtractor::reset() {
    audioHistory.prepare(audioHistory.getCapacity());
    std::fill(binMagnitudeScratch.begin(), binMagnitudeScratch.end(), 0.0F);
    totalSamplesIngested = 0;
    samplesAccountedForByAnalysisFrames = 0;
    pendingChromaVector.reset();
    accumulatedChromagram.frames.clear();
}

}  // namespace scorefollower::dsp
