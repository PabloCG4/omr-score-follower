// Public construction seam for FeatureExtractor. Host applications (mobile
// JNI/Swift bridges, offline analysis tools) depend only on this factory and
// on FeatureExtractor.hpp/SpectralBackend.hpp, never on the concrete
// implementation class, so the concrete class can evolve freely.
#pragma once

#include "FeatureExtractor.hpp"
#include "ScoreFollowerCoreExport.hpp"
#include "SpectralBackend.hpp"

#include <memory>

namespace scorefollower::dsp {

// Constructs the library's Constant-Q Transform based FeatureExtractor
// implementation. Pass a null spectralBackend (the default) to use the
// library's built-in, dependency-free FFT; pass a platform-accelerated
// implementation (Accelerate/vDSP on iOS, a NEON-tuned backend on Android)
// to use it instead, with no other change required anywhere else in the
// pipeline.
SCORE_FOLLOWER_CORE_API std::unique_ptr<FeatureExtractor> createConstantQFeatureExtractor(
    std::shared_ptr<SpectralBackend> spectralBackend = nullptr);

}  // namespace scorefollower::dsp
