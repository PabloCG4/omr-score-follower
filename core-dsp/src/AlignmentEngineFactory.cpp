#include "AlignmentEngineFactory.hpp"

#include "NearestFrameAlignmentEngine.hpp"

#include <memory>

namespace scorefollower::dsp {

std::unique_ptr<AlignmentEngine> createAlignmentEngine() {
    return std::make_unique<NearestFrameAlignmentEngine>();
}

}  // namespace scorefollower::dsp
