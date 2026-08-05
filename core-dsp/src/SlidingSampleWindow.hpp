// A fixed-capacity audio history buffer that always exposes the most
// recently written samples. This is deliberately distinct from
// CircularAudioBuffer's destructive-read producer/consumer queue semantics:
// writes here never "consume" data for a separate reader thread, they
// simply overwrite the oldest retained sample once the window is full.
// ConstantQFeatureExtractor keeps one instance of this per extractor, sized
// to its longest Constant-Q kernel, and every octave reads its own
// (shorter or equal-length) tail out of it.
#pragma once

#include <cstddef>
#include <vector>

namespace scorefollower::dsp::internal {

class SlidingSampleWindow {
public:
    // Allocates storage for capacitySamples. This is the only method on
    // this class that allocates; call it once during a non-real-time
    // configuration phase, before any call to pushSample.
    void prepare(std::size_t capacitySamples) {
        storage.assign(capacitySamples, 0.0F);
        capacity = capacitySamples;
        writeHeadIndex = 0;
        samplesWrittenSoFar = 0;
    }

    [[nodiscard]] std::size_t getCapacity() const noexcept {
        return capacity;
    }

    // Number of valid samples currently retained (less than capacity until
    // the window has been filled at least once, capacity thereafter).
    [[nodiscard]] std::size_t getAvailableSampleCount() const noexcept {
        return samplesWrittenSoFar;
    }

    // Appends one new sample, overwriting the oldest retained sample once
    // the window is full. Performs no allocation.
    void pushSample(float sampleValue) noexcept {
        storage[writeHeadIndex] = sampleValue;
        writeHeadIndex = (writeHeadIndex + 1) % capacity;
        if (samplesWrittenSoFar < capacity) {
            ++samplesWrittenSoFar;
        }
    }

    // Copies the most recent sampleCount samples, in chronological order
    // (oldest of the requested range first), into destination, which must
    // have room for at least sampleCount floats. sampleCount must not
    // exceed getCapacity(). When fewer than sampleCount samples have been
    // written yet, the leading (oldest) portion is zero-padded so callers
    // can run FFT-sized analysis from the first hop without waiting for the
    // full Constant-Q history to fill (which can be several seconds at low
    // analysis frequencies). Performs no allocation.
    void copyMostRecentSamples(std::size_t sampleCount, float* destination) const noexcept {
        if (sampleCount == 0 || capacity == 0) {
            return;
        }
        if (sampleCount > capacity) {
            sampleCount = capacity;
        }

        const std::size_t available = samplesWrittenSoFar;
        if (sampleCount > available) {
            const std::size_t padCount = sampleCount - available;
            for (std::size_t padIndex = 0; padIndex < padCount; ++padIndex) {
                destination[padIndex] = 0.0F;
            }
            if (available == 0) {
                return;
            }
            std::size_t readIndex = (writeHeadIndex + capacity - available) % capacity;
            for (std::size_t sampleIndex = 0; sampleIndex < available; ++sampleIndex) {
                destination[padCount + sampleIndex] = storage[readIndex];
                readIndex = (readIndex + 1) % capacity;
            }
            return;
        }

        std::size_t readIndex = (writeHeadIndex + capacity - sampleCount) % capacity;
        for (std::size_t index = 0; index < sampleCount; ++index) {
            destination[index] = storage[readIndex];
            readIndex = (readIndex + 1) % capacity;
        }
    }

private:
    std::vector<float> storage;
    std::size_t capacity = 0;
    std::size_t writeHeadIndex = 0;
    std::size_t samplesWrittenSoFar = 0;
};

}  // namespace scorefollower::dsp::internal
