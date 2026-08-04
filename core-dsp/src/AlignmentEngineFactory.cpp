#include "AlignmentEngineFactory.hpp"

#include "OnlineDtwAlignmentEngine.hpp"

#include <memory>

namespace scorefollower::dsp {

std::unique_ptr<AlignmentEngine> createAlignmentEngine() {
    return std::make_unique<OnlineDtwAlignmentEngine>();
}

}  // namespace scorefollower::dsp
