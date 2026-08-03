#include "FeatureExtractorFactory.hpp"

#include "ConstantQFeatureExtractor.hpp"

#include <memory>
#include <utility>

namespace scorefollower::dsp {

std::unique_ptr<FeatureExtractor> createConstantQFeatureExtractor(std::shared_ptr<SpectralBackend> spectralBackend) {
    if (!spectralBackend) {
        spectralBackend = createDefaultSpectralBackend();
    }
    return std::make_unique<ConstantQFeatureExtractor>(std::move(spectralBackend));
}

}  // namespace scorefollower::dsp
