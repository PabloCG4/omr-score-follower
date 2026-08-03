// Self-contained, header-only, iterative radix-2 Cooley-Tukey FFT. This is
// the library's built-in, dependency-free spectral transform, used by
// DefaultSpectralBackend. It intentionally avoids vendoring a third-party
// FFT library so that every line of math in this thesis codebase is
// self-authored and auditable; platform-accelerated backends (Accelerate's
// vDSP on iOS, a NEON-optimized implementation on Android) can later be
// injected through the SpectralBackend interface without touching this
// class or any of its callers.
#pragma once

#include <cmath>
#include <complex>
#include <cstddef>
#include <stdexcept>
#include <vector>

namespace scorefollower::dsp::internal {

// Defined locally rather than relying on the non-standard M_PI macro, which
// is unavailable by default on MSVC and some MinGW configurations.
inline constexpr double PiConstant = 3.14159265358979323846;

// Prepares (once, allocating) the bit-reversal permutation and twiddle
// factor tables for one fixed transform length, then computes forward FFTs
// of that exact length with no further allocation.
class RadixTwoFft {
public:
    // Allocates the internal tables for transformLength, which must be a
    // power of two greater than or equal to two. Safe to call again to
    // re-prepare for a different length (replaces the previous tables).
    void prepare(std::size_t transformLength) {
        if (transformLength < 2 || (transformLength & (transformLength - 1)) != 0) {
            throw std::invalid_argument("RadixTwoFft::prepare requires a power-of-two length of at least two.");
        }

        length = transformLength;
        log2Length = computeLog2(length);

        bitReversalIndices.assign(length, 0);
        for (std::size_t index = 0; index < length; ++index) {
            bitReversalIndices[index] = reverseBits(index, log2Length);
        }

        // One twiddle factor per distinct angle needed across all butterfly
        // stages: exp(-2*pi*i*k/length) for k in [0, length/2).
        twiddleFactors.assign(length / 2, std::complex<float>(1.0F, 0.0F));
        const double angleStep = -2.0 * PiConstant / static_cast<double>(length);
        for (std::size_t k = 0; k < length / 2; ++k) {
            const double angle = angleStep * static_cast<double>(k);
            twiddleFactors[k] = std::complex<float>(static_cast<float>(std::cos(angle)),
                                                      static_cast<float>(std::sin(angle)));
        }

        scratch.assign(length, std::complex<float>(0.0F, 0.0F));
    }

    // Returns the transform length this instance is currently prepared for,
    // or zero if prepare has not been called yet.
    [[nodiscard]] std::size_t preparedLength() const noexcept {
        return length;
    }

    // Computes the forward FFT of a real-valued input of exactly
    // preparedLength() samples, writing the full complex spectrum into
    // output (also preparedLength() complex entries). Performs no
    // allocation; this method is safe to call from a non-real-time analysis
    // thread that must not stall on the heap.
    void computeForwardTransform(const float* realInput, std::complex<float>* output) const {
        // Bit-reversal permutation: place each (real) input sample directly
        // into its bit-reversed slot in the working buffer.
        for (std::size_t index = 0; index < length; ++index) {
            scratch[bitReversalIndices[index]] = std::complex<float>(realInput[index], 0.0F);
        }
        runButterflyStages();
        for (std::size_t index = 0; index < length; ++index) {
            output[index] = scratch[index];
        }
    }

    // Complex-input counterpart of computeForwardTransform, used to compute
    // the spectrum of a complex-valued signal (for example a windowed
    // complex exponential Constant-Q analysis kernel). Performs no
    // allocation.
    void computeForwardTransformComplex(const std::complex<float>* complexInput,
                                         std::complex<float>* output) const {
        for (std::size_t index = 0; index < length; ++index) {
            scratch[bitReversalIndices[index]] = complexInput[index];
        }
        runButterflyStages();
        for (std::size_t index = 0; index < length; ++index) {
            output[index] = scratch[index];
        }
    }

private:
    static unsigned int computeLog2(std::size_t powerOfTwoValue) {
        unsigned int exponent = 0;
        while ((static_cast<std::size_t>(1) << exponent) < powerOfTwoValue) {
            ++exponent;
        }
        return exponent;
    }

    static std::size_t reverseBits(std::size_t value, unsigned int bitCount) {
        std::size_t reversed = 0;
        for (unsigned int bit = 0; bit < bitCount; ++bit) {
            reversed = (reversed << 1) | (value & 1U);
            value >>= 1;
        }
        return reversed;
    }

    // Iterative Cooley-Tukey butterflies, doubling the sub-transform size at
    // each of log2Length stages, operating in place on scratch. Shared by
    // both the real-input and complex-input entry points, since after the
    // initial bit-reversed placement the butterfly math is identical.
    void runButterflyStages() const {
        for (unsigned int stage = 1; stage <= log2Length; ++stage) {
            const std::size_t subTransformSize = static_cast<std::size_t>(1) << stage;
            const std::size_t halfSubTransformSize = subTransformSize / 2;
            const std::size_t twiddleStride = length / subTransformSize;

            for (std::size_t groupStart = 0; groupStart < length; groupStart += subTransformSize) {
                for (std::size_t butterflyIndex = 0; butterflyIndex < halfSubTransformSize; ++butterflyIndex) {
                    const std::complex<float>& twiddle = twiddleFactors[butterflyIndex * twiddleStride];
                    const std::size_t evenIndex = groupStart + butterflyIndex;
                    const std::size_t oddIndex = evenIndex + halfSubTransformSize;

                    const std::complex<float> evenValue = scratch[evenIndex];
                    const std::complex<float> oddValue = twiddle * scratch[oddIndex];

                    scratch[evenIndex] = evenValue + oddValue;
                    scratch[oddIndex] = evenValue - oddValue;
                }
            }
        }
    }

    std::size_t length = 0;
    unsigned int log2Length = 0;
    std::vector<std::size_t> bitReversalIndices;
    std::vector<std::complex<float>> twiddleFactors;

    // Mutable working buffer reused by every computeForwardTransform call;
    // marked mutable so computeForwardTransform can remain logically const
    // (it does not change the prepared tables) while still avoiding
    // per-call allocation of its scratch storage.
    mutable std::vector<std::complex<float>> scratch;
};

}  // namespace scorefollower::dsp::internal
