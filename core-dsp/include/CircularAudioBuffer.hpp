// A single-producer, single-consumer, lock-free circular buffer designed for
// passing raw audio samples from a real-time audio callback thread to a
// non-real-time analysis thread without ever blocking the audio thread.
#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <type_traits>

namespace scorefollower::dsp {

// All storage is a fixed-size std::array embedded directly in the object, so
// the entire buffer is allocated exactly once, at construction time. No heap
// allocation, locking, or system call of any kind occurs inside tryWrite,
// tryRead, writeAvailable, or readAvailable, which makes those four methods
// safe to call from the audio thread's real-time callback.
//
// This class is only safe for exactly one producer thread and one consumer
// thread operating concurrently; it is not safe for multiple producers or
// multiple consumers.
template <typename SampleType, std::size_t BufferCapacitySamples>
class CircularAudioBuffer {
    static_assert(BufferCapacitySamples > 0, "BufferCapacitySamples must be greater than zero.");
    static_assert(std::is_trivially_copyable_v<SampleType>,
                  "SampleType must be trivially copyable for real-time-safe element copies.");

public:
    CircularAudioBuffer() noexcept : writeIndex(0), readIndex(0) {}

    CircularAudioBuffer(const CircularAudioBuffer&) = delete;
    CircularAudioBuffer& operator=(const CircularAudioBuffer&) = delete;
    CircularAudioBuffer(CircularAudioBuffer&&) = delete;
    CircularAudioBuffer& operator=(CircularAudioBuffer&&) = delete;

    // Total number of samples the buffer can hold at once.
    [[nodiscard]] static constexpr std::size_t capacity() noexcept {
        return BufferCapacitySamples;
    }

    // Number of samples currently available to read. Safe to call from
    // either thread, though the result may be immediately stale.
    [[nodiscard]] std::size_t availableSamplesToRead() const noexcept {
        const std::size_t currentWriteIndex = writeIndex.load(std::memory_order_acquire);
        const std::size_t currentReadIndex = readIndex.load(std::memory_order_acquire);
        return (currentWriteIndex + StorageSize - currentReadIndex) % StorageSize;
    }

    // Remaining free slots available to write. Safe to call from either
    // thread, though the result may be immediately stale.
    [[nodiscard]] std::size_t availableCapacityToWrite() const noexcept {
        return BufferCapacitySamples - availableSamplesToRead();
    }

    // Attempts to write a single sample. Returns false without blocking if
    // the buffer is full. Must only be called from the producer thread.
    bool tryWrite(SampleType sampleValue) noexcept {
        const std::size_t currentWriteIndex = writeIndex.load(std::memory_order_relaxed);
        const std::size_t nextWriteIndex = advance(currentWriteIndex);
        if (nextWriteIndex == readIndex.load(std::memory_order_acquire)) {
            return false;  // Buffer full.
        }
        sampleStorage[currentWriteIndex] = sampleValue;
        writeIndex.store(nextWriteIndex, std::memory_order_release);
        return true;
    }

    // Writes as many samples as possible from sourceSamples, stopping early
    // if the buffer becomes full. Returns the number of samples actually
    // written. Must only be called from the producer thread.
    std::size_t writeAvailable(const SampleType* sourceSamples, std::size_t sampleCount) noexcept {
        std::size_t samplesWritten = 0;
        while (samplesWritten < sampleCount && tryWrite(sourceSamples[samplesWritten])) {
            ++samplesWritten;
        }
        return samplesWritten;
    }

    // Attempts to read a single sample. Returns false without blocking if the
    // buffer is empty. Must only be called from the consumer thread.
    bool tryRead(SampleType& outputSampleValue) noexcept {
        const std::size_t currentReadIndex = readIndex.load(std::memory_order_relaxed);
        if (currentReadIndex == writeIndex.load(std::memory_order_acquire)) {
            return false;  // Buffer empty.
        }
        outputSampleValue = sampleStorage[currentReadIndex];
        readIndex.store(advance(currentReadIndex), std::memory_order_release);
        return true;
    }

    // Reads as many samples as possible into destinationSamples, stopping
    // early if the buffer becomes empty. Returns the number of samples
    // actually read. Must only be called from the consumer thread.
    std::size_t readAvailable(SampleType* destinationSamples, std::size_t sampleCount) noexcept {
        std::size_t samplesRead = 0;
        while (samplesRead < sampleCount && tryRead(destinationSamples[samplesRead])) {
            ++samplesRead;
        }
        return samplesRead;
    }

    // Discards all buffered samples. This is not safe to call concurrently
    // with tryWrite/tryRead and must only be invoked while the producer and
    // consumer threads are both known to be idle, for example before
    // starting or after stopping the audio stream.
    void reset() noexcept {
        writeIndex.store(0, std::memory_order_relaxed);
        readIndex.store(0, std::memory_order_relaxed);
    }

private:
    // One extra slot is reserved internally so the full and empty states can
    // be distinguished from one another using only the two indices, without
    // maintaining a separate atomic element counter.
    static constexpr std::size_t StorageSize = BufferCapacitySamples + 1;

    [[nodiscard]] static constexpr std::size_t advance(std::size_t index) noexcept {
        const std::size_t nextIndex = index + 1;
        return nextIndex == StorageSize ? 0 : nextIndex;
    }

    std::array<SampleType, StorageSize> sampleStorage{};

    // Each index is aligned to its own cache line to prevent false sharing
    // between the producer thread (which writes writeIndex and reads
    // readIndex) and the consumer thread (which writes readIndex and reads
    // writeIndex).
    alignas(64) std::atomic<std::size_t> writeIndex;
    alignas(64) std::atomic<std::size_t> readIndex;
};

}  // namespace scorefollower::dsp
