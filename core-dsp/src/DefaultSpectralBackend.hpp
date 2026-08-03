// Default, dependency-free SpectralBackend implementation built on the
// self-contained internal::RadixTwoFft. See SpectralBackend.hpp for the
// public interface and the rationale for the dependency-injection design.
#pragma once

#include "RadixTwoFft.hpp"
#include "SpectralBackend.hpp"

#include <complex>
#include <cstddef>
#include <vector>

namespace scorefollower::dsp {

// Supports being prepared for a small, fixed set of distinct transform
// lengths (in the Constant-Q pipeline, one length per octave). Each
// prepared length is looked up by a bounded linear scan over
// preparedTransforms at call time, so forwardTransform itself never
// allocates; only prepareTransformLength does.
class DefaultSpectralBackend final : public SpectralBackend {
public:
    void prepareTransformLength(std::size_t transformLength) override;

    void forwardTransform(const float* realInputWindowed,
                           std::complex<float>* complexOutputSpectrum,
                           std::size_t transformLength) override;

    void forwardTransformComplex(const std::complex<float>* complexInput,
                                  std::complex<float>* complexOutputSpectrum,
                                  std::size_t transformLength) override;

private:
    // Returns the prepared transform for transformLength, or throws
    // std::logic_error if prepareTransformLength was never called for it.
    const internal::RadixTwoFft& findPreparedTransform(std::size_t transformLength) const;


    std::vector<internal::RadixTwoFft> preparedTransforms;
};

}  // namespace scorefollower::dsp
