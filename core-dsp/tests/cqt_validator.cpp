// Standalone command-line validator for the Constant-Q Transform pipeline.
//
// Purpose: before implementing the Online DTW alignment algorithm, this tool
// lets us empirically confirm that score_follower_core's production
// Constant-Q Transform pipeline (ConstantQFeatureExtractor, via its factory)
// processes real recorded audio sensibly, by loading a .wav file from disk,
// feeding it through the same CircularAudioBuffer-mediated data flow the
// mobile host application will eventually use, and printing the resulting
// chromagram to the console as a readable numeric matrix.
//
// This file implements its own minimal RIFF WAV parser rather than depending
// on any external library, matching this thesis codebase's existing policy
// (see research/chromagram_extractor.py's rationale and core-dsp's own
// dependency-free RadixTwoFft) of keeping every DSP-adjacent building block
// self-authored and auditable. It supports the two PCM encodings a validator
// tool realistically needs to handle: 16-bit signed integer PCM and 32-bit
// IEEE float PCM, mono or multi-channel (down-mixed to mono by averaging).
// It assumes a little-endian host, which covers every realistic desktop,
// mobile, and CI build target for this project.
#include "Chromagram.hpp"
#include "CircularAudioBuffer.hpp"
#include "FeatureExtractorFactory.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using scorefollower::dsp::ChromaVector;
using scorefollower::dsp::Chromagram;
using scorefollower::dsp::PitchClassCount;

// Decoded, down-mixed-to-mono audio ready to feed into a FeatureExtractor.
struct DecodedWavAudio {
    std::vector<float> monoSamples;
    std::uint32_t sampleRateHz = 0;
};

std::array<char, 4> readFourCharacterCode(std::ifstream& fileStream) {
    std::array<char, 4> code{};
    fileStream.read(code.data(), static_cast<std::streamsize>(code.size()));
    return code;
}

bool fourCharacterCodeEquals(const std::array<char, 4>& code, const char* expected) {
    return code[0] == expected[0] && code[1] == expected[1] && code[2] == expected[2] && code[3] == expected[3];
}

std::uint32_t readUint32LittleEndian(std::ifstream& fileStream) {
    std::uint8_t bytes[4] = {0, 0, 0, 0};
    fileStream.read(reinterpret_cast<char*>(bytes), 4);
    return static_cast<std::uint32_t>(bytes[0]) | (static_cast<std::uint32_t>(bytes[1]) << 8) |
           (static_cast<std::uint32_t>(bytes[2]) << 16) | (static_cast<std::uint32_t>(bytes[3]) << 24);
}

std::uint16_t readUint16LittleEndian(std::ifstream& fileStream) {
    std::uint8_t bytes[2] = {0, 0};
    fileStream.read(reinterpret_cast<char*>(bytes), 2);
    return static_cast<std::uint16_t>(static_cast<std::uint16_t>(bytes[0]) | (static_cast<std::uint16_t>(bytes[1]) << 8));
}

// Minimal RIFF/WAVE chunk walker: reads the "fmt " and "data" chunks and
// skips (word-aligned, per the RIFF specification) every other chunk type
// (LIST, fact, cue, and so on), so real-world WAV files produced by common
// recording tools parse correctly even though this parser only needs two of
// their chunks.
DecodedWavAudio loadMonoFloatSamplesFromWavFile(const std::string& filePath) {
    std::ifstream fileStream(filePath, std::ios::binary);
    if (!fileStream.is_open()) {
        throw std::runtime_error("Unable to open WAV file: " + filePath);
    }

    const std::array<char, 4> riffCode = readFourCharacterCode(fileStream);
    if (!fourCharacterCodeEquals(riffCode, "RIFF")) {
        throw std::runtime_error("File is not a RIFF container: " + filePath);
    }
    readUint32LittleEndian(fileStream);  // Overall RIFF chunk size; unused.
    const std::array<char, 4> waveCode = readFourCharacterCode(fileStream);
    if (!fourCharacterCodeEquals(waveCode, "WAVE")) {
        throw std::runtime_error("RIFF file is not a WAVE file: " + filePath);
    }

    bool foundFormatChunk = false;
    bool foundDataChunk = false;
    std::uint16_t audioFormatCode = 0;
    std::uint16_t channelCount = 0;
    std::uint32_t sampleRateHz = 0;
    std::uint16_t bitsPerSample = 0;
    std::vector<std::uint8_t> dataChunkBytes;

    while (fileStream.good()) {
        const std::array<char, 4> chunkId = readFourCharacterCode(fileStream);
        if (!fileStream.good()) {
            break;  // Reached end of file cleanly between chunks.
        }
        const std::uint32_t chunkSize = readUint32LittleEndian(fileStream);

        if (fourCharacterCodeEquals(chunkId, "fmt ")) {
            audioFormatCode = readUint16LittleEndian(fileStream);
            channelCount = readUint16LittleEndian(fileStream);
            sampleRateHz = readUint32LittleEndian(fileStream);
            readUint32LittleEndian(fileStream);  // Byte rate; derivable, unused.
            readUint16LittleEndian(fileStream);  // Block align; derivable, unused.
            bitsPerSample = readUint16LittleEndian(fileStream);
            foundFormatChunk = true;

            constexpr std::uint32_t canonicalFormatChunkBytesRead = 16;
            if (chunkSize > canonicalFormatChunkBytesRead) {
                fileStream.seekg(static_cast<std::streamoff>(chunkSize - canonicalFormatChunkBytesRead), std::ios::cur);
            }
        } else if (fourCharacterCodeEquals(chunkId, "data")) {
            dataChunkBytes.resize(chunkSize);
            fileStream.read(reinterpret_cast<char*>(dataChunkBytes.data()), static_cast<std::streamsize>(chunkSize));
            foundDataChunk = true;
        } else {
            fileStream.seekg(static_cast<std::streamoff>(chunkSize), std::ios::cur);
        }

        if ((chunkSize % 2) != 0 && fileStream.good()) {
            fileStream.seekg(1, std::ios::cur);  // RIFF chunks are padded to even byte boundaries.
        }
    }

    if (!foundFormatChunk || !foundDataChunk) {
        throw std::runtime_error("WAV file is missing a required 'fmt ' or 'data' chunk: " + filePath);
    }

    constexpr std::uint16_t pcmIntegerFormatCode = 1;
    constexpr std::uint16_t ieeeFloatFormatCode = 3;
    const bool isSupportedSixteenBitPcm = (audioFormatCode == pcmIntegerFormatCode && bitsPerSample == 16);
    const bool isSupportedThirtyTwoBitFloat = (audioFormatCode == ieeeFloatFormatCode && bitsPerSample == 32);
    if (!isSupportedSixteenBitPcm && !isSupportedThirtyTwoBitFloat) {
        throw std::runtime_error(
            "Unsupported WAV encoding (only 16-bit PCM and 32-bit IEEE float are supported): " + filePath);
    }
    if (channelCount == 0) {
        throw std::runtime_error("WAV file reports zero audio channels: " + filePath);
    }

    const std::size_t bytesPerSample = static_cast<std::size_t>(bitsPerSample) / 8;
    const std::size_t bytesPerFrame = bytesPerSample * channelCount;
    const std::size_t totalSampleFrames = (bytesPerFrame > 0) ? (dataChunkBytes.size() / bytesPerFrame) : 0;

    DecodedWavAudio decodedAudio;
    decodedAudio.sampleRateHz = sampleRateHz;
    decodedAudio.monoSamples.resize(totalSampleFrames);

    for (std::size_t frameIndex = 0; frameIndex < totalSampleFrames; ++frameIndex) {
        double channelSum = 0.0;
        for (std::uint16_t channelIndex = 0; channelIndex < channelCount; ++channelIndex) {
            const std::size_t byteOffset = (frameIndex * channelCount + channelIndex) * bytesPerSample;
            double sampleValue = 0.0;

            if (isSupportedSixteenBitPcm) {
                const std::uint16_t rawUnsigned = static_cast<std::uint16_t>(
                    static_cast<std::uint16_t>(dataChunkBytes[byteOffset]) |
                    (static_cast<std::uint16_t>(dataChunkBytes[byteOffset + 1]) << 8));
                const std::int16_t rawSigned = static_cast<std::int16_t>(rawUnsigned);
                sampleValue = static_cast<double>(rawSigned) / 32768.0;
            } else {
                std::uint32_t rawBits = static_cast<std::uint32_t>(dataChunkBytes[byteOffset]) |
                                         (static_cast<std::uint32_t>(dataChunkBytes[byteOffset + 1]) << 8) |
                                         (static_cast<std::uint32_t>(dataChunkBytes[byteOffset + 2]) << 16) |
                                         (static_cast<std::uint32_t>(dataChunkBytes[byteOffset + 3]) << 24);
                float floatSample = 0.0F;
                std::memcpy(&floatSample, &rawBits, sizeof(float));
                sampleValue = static_cast<double>(floatSample);
            }

            channelSum += sampleValue;
        }
        decodedAudio.monoSamples[frameIndex] = static_cast<float>(channelSum / static_cast<double>(channelCount));
    }

    return decodedAudio;
}

// Feeds decodedAudio into featureExtractor by simulating the real-time data
// flow the mobile host application will eventually use: fixed-size blocks
// are written into a CircularAudioBuffer (as a real audio callback would),
// then immediately drained and handed to ingestAudioFrame (as the
// non-real-time analysis thread would). This is a single-threaded
// simulation of that two-thread architecture, exercising the exact same
// buffer class and call sequence without the added complexity of real
// thread synchronization, which is unnecessary for this offline validator.
void feedAudioThroughSimulatedRealTimePipeline(scorefollower::dsp::FeatureExtractor& featureExtractor,
                                                const std::vector<float>& monoSamples) {
    constexpr std::size_t simulatedAudioCallbackBlockSize = 512;
    constexpr std::size_t ringBufferCapacitySamples = 4096;

    scorefollower::dsp::CircularAudioBuffer<float, ringBufferCapacitySamples> ringBuffer;
    std::vector<float> drainScratch(ringBufferCapacitySamples);

    std::size_t samplesPushedIntoRingBuffer = 0;
    while (samplesPushedIntoRingBuffer < monoSamples.size()) {
        const std::size_t remainingSamples = monoSamples.size() - samplesPushedIntoRingBuffer;
        const std::size_t blockSize = std::min(simulatedAudioCallbackBlockSize, remainingSamples);

        const std::size_t samplesWritten =
            ringBuffer.writeAvailable(monoSamples.data() + samplesPushedIntoRingBuffer, blockSize);
        samplesPushedIntoRingBuffer += samplesWritten;

        const std::size_t samplesAvailableToDrain = ringBuffer.availableSamplesToRead();
        if (samplesAvailableToDrain > 0) {
            const std::size_t samplesDrained = ringBuffer.readAvailable(drainScratch.data(), samplesAvailableToDrain);
            featureExtractor.ingestAudioFrame(drainScratch.data(), samplesDrained);
        }
    }
}

constexpr std::array<const char*, PitchClassCount> PitchClassNames = {"C",  "C#", "D",  "D#", "E",  "F",
                                                                       "F#", "G",  "G#", "A",  "A#", "B"};

std::size_t findDominantPitchClass(const ChromaVector& chromaVector) {
    std::size_t dominantIndex = 0;
    float dominantEnergy = chromaVector.pitchClassEnergies[0];
    for (std::size_t pitchClass = 1; pitchClass < PitchClassCount; ++pitchClass) {
        if (chromaVector.pitchClassEnergies[pitchClass] > dominantEnergy) {
            dominantEnergy = chromaVector.pitchClassEnergies[pitchClass];
            dominantIndex = pitchClass;
        }
    }
    return dominantIndex;
}

// Prints the chromagram as a numeric matrix: one row per analysis frame,
// one column per pitch class, plus the dominant pitch class for quick
// visual scanning. Long recordings are decimated to a fixed maximum number
// of printed rows so the table stays readable in a terminal.
void printChromagramAsTable(const Chromagram& chromagram) {
    const std::size_t totalFrames = chromagram.frames.size();

    std::printf("\nChromagram summary: %zu analysis frames, hop = %zu samples, sample rate = %.1f Hz\n", totalFrames,
                chromagram.hopLengthSamples, chromagram.sampleRateHz);

    if (totalFrames == 0) {
        std::printf(
            "No analysis frames were produced. The Constant-Q pipeline needs enough audio to fill its lowest "
            "octave's analysis window before it can emit a first frame (roughly a few seconds for the default "
            "configuration) -- try a longer recording.\n");
        return;
    }

    constexpr std::size_t maximumRowsToPrint = 60;
    const std::size_t rowStride = (totalFrames > maximumRowsToPrint) ? (totalFrames / maximumRowsToPrint) : 1;
    if (rowStride > 1) {
        std::printf("(Showing every %zu-th frame to keep this table readable; %zu frames were computed in total.)\n",
                    rowStride, totalFrames);
    }

    std::printf("%8s %9s ", "Frame", "Time(s)");
    for (const char* pitchClassName : PitchClassNames) {
        std::printf("%6s", pitchClassName);
    }
    std::printf("  Dominant\n");

    for (std::size_t frameIndex = 0; frameIndex < totalFrames; frameIndex += rowStride) {
        const ChromaVector& frame = chromagram.frames[frameIndex];
        const double timestampSeconds = chromagram.getFrameTimestampSeconds(frameIndex);
        const std::size_t dominantPitchClass = findDominantPitchClass(frame);

        std::printf("%8zu %9.2f ", frameIndex, timestampSeconds);
        for (std::size_t pitchClass = 0; pitchClass < PitchClassCount; ++pitchClass) {
            std::printf("%6.2f", static_cast<double>(frame.pitchClassEnergies[pitchClass]));
        }
        std::printf("  %s\n", PitchClassNames[dominantPitchClass]);
    }
}

}  // namespace

int main(int argumentCount, char** argumentValues) {
    const std::string wavFilePath = (argumentCount > 1) ? argumentValues[1] : "sample.wav";

    std::printf("CQT Validator: loading '%s'\n", wavFilePath.c_str());

    DecodedWavAudio decodedAudio;
    try {
        decodedAudio = loadMonoFloatSamplesFromWavFile(wavFilePath);
    } catch (const std::exception& loadError) {
        std::fprintf(stderr, "Failed to load WAV file: %s\n", loadError.what());
        std::fprintf(stderr, "Usage: cqt_validator <path-to-16-bit-or-32-bit-float-wav-file>\n");
        return 1;
    }

    if (decodedAudio.monoSamples.empty() || decodedAudio.sampleRateHz == 0) {
        std::fprintf(stderr, "WAV file contained no usable audio samples: %s\n", wavFilePath.c_str());
        return 1;
    }

    const double durationSeconds =
        static_cast<double>(decodedAudio.monoSamples.size()) / static_cast<double>(decodedAudio.sampleRateHz);
    std::printf("Loaded %zu mono samples at %u Hz (%.2f seconds of audio).\n", decodedAudio.monoSamples.size(),
                decodedAudio.sampleRateHz, durationSeconds);

    scorefollower::dsp::FeatureExtractionConfiguration configuration;
    configuration.sampleRateHz = static_cast<double>(decodedAudio.sampleRateHz);
    configuration.hopLengthSamples = 512;
    // The remaining fields (Constant-Q bin resolution, octave count, minimum
    // frequency) intentionally keep their production defaults, so this tool
    // validates the same pipeline configuration the mobile application will
    // actually run, not a scaled-down test configuration.

    const std::unique_ptr<scorefollower::dsp::FeatureExtractor> featureExtractor =
        scorefollower::dsp::createConstantQFeatureExtractor();
    featureExtractor->configure(configuration);

    feedAudioThroughSimulatedRealTimePipeline(*featureExtractor, decodedAudio.monoSamples);

    printChromagramAsTable(featureExtractor->getAccumulatedChromagram());

    return 0;
}
