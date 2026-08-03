// Dependency-injection seam for the forward Fourier transform used inside
// the Constant-Q Transform pipeline. Concrete DSP classes (see
// ConstantQFeatureExtractor) depend only on this interface, never on a
// specific FFT implementation, so a mobile host application can later inject
// a platform-accelerated backend (for example Accelerate's vDSP on iOS, or a
// NEON-optimized implementation on Android) without any change to the CQT
// math itself. createDefaultSpectralBackend returns a portable, dependency-
// free implementation suitable for development, testing, and any platform
// without a native accelerated FFT available.
#pragma once

#include "ScoreFollowerCoreExport.hpp"

#include <complex>
#include <cstddef>
#include <memory>

namespace scorefollower::dsp {

// Computes forward discrete Fourier transforms of a fixed, power-of-two
// length. Implementations are expected to be safe to invoke repeatedly from
// a non-real-time analysis thread without allocating on the call path
// itself; any internal scratch state required by a specific implementation
// (for example twiddle factor tables) should be prepared once, either in the
// implementation's constructor or the first time a given transformLength is
// requested, and reused thereafter.
class SpectralBackend {
public:
    virtual ~SpectralBackend() = default;

    // Allocates and caches whatever internal scratch state (twiddle factor
    // tables, bit-reversal tables, and so on) is needed to later call
    // forwardTransform with this exact transformLength, which must be a
    // power of two. Callers must invoke this once per distinct length during
    // a non-real-time configuration phase, before ever calling
    // forwardTransform with that length; this is the only method on this
    // interface that is allowed to allocate.
    virtual void prepareTransformLength(std::size_t transformLength) = 0;

    // Computes the forward FFT of realInputWindowed (a real-valued signal of
    // exactly transformLength samples, already windowed and zero-padded by
    // the caller) and writes the full complex spectrum, of transformLength
    // complex bins, into complexOutputSpectrum. transformLength must have
    // been previously passed to prepareTransformLength. The caller owns both
    // buffers; this call performs no allocation.
    virtual void forwardTransform(const float* realInputWindowed,
                                   std::complex<float>* complexOutputSpectrum,
                                   std::size_t transformLength) = 0;

    // Complex-input counterpart of forwardTransform, used to precompute the
    // spectra of the Constant-Q Transform's complex-valued (windowed
    // exponential) analysis kernels. transformLength must have been
    // previously passed to prepareTransformLength. Performs no allocation.
    virtual void forwardTransformComplex(const std::complex<float>* complexInput,
                                          std::complex<float>* complexOutputSpectrum,
                                          std::size_t transformLength) = 0;
};

// Constructs the library's built-in, dependency-free SpectralBackend
// implementation (a radix-2 Cooley-Tukey FFT). See RadixTwoFft.hpp and
// DefaultSpectralBackend.hpp for the implementation.
SCORE_FOLLOWER_CORE_API std::unique_ptr<SpectralBackend> createDefaultSpectralBackend();

}  // namespace scorefollower::dsp
