#include "DefaultSpectralBackend.hpp"

#include <memory>
#include <stdexcept>
#include <utility>

namespace scorefollower::dsp {

void DefaultSpectralBackend::prepareTransformLength(std::size_t transformLength) {
    for (const auto& transform : preparedTransforms) {
        if (transform.preparedLength() == transformLength) {
            return;  // Already prepared; nothing to do.
        }
    }

    internal::RadixTwoFft newTransform;
    newTransform.prepare(transformLength);
    preparedTransforms.push_back(std::move(newTransform));
}

void DefaultSpectralBackend::forwardTransform(const float* realInputWindowed,
                                               std::complex<float>* complexOutputSpectrum,
                                               std::size_t transformLength) {
    findPreparedTransform(transformLength).computeForwardTransform(realInputWindowed, complexOutputSpectrum);
}

void DefaultSpectralBackend::forwardTransformComplex(const std::complex<float>* complexInput,
                                                       std::complex<float>* complexOutputSpectrum,
                                                       std::size_t transformLength) {
    findPreparedTransform(transformLength).computeForwardTransformComplex(complexInput, complexOutputSpectrum);
}

const internal::RadixTwoFft& DefaultSpectralBackend::findPreparedTransform(std::size_t transformLength) const {
    for (const auto& transform : preparedTransforms) {
        if (transform.preparedLength() == transformLength) {
            return transform;
        }
    }

    throw std::logic_error(
        "DefaultSpectralBackend was asked to transform a length that was never passed to "
        "prepareTransformLength.");
}

std::unique_ptr<SpectralBackend> createDefaultSpectralBackend() {
    return std::make_unique<DefaultSpectralBackend>();
}

}  // namespace scorefollower::dsp
