// Public construction seam for AlignmentEngine. Host applications depend
// only on this factory and on AlignmentEngine.hpp, never on the concrete
// implementation class, so the concrete class can evolve freely (in
// particular, be replaced by a real Online DTW engine without touching any
// caller).
#pragma once

#include "AlignmentEngine.hpp"
#include "ScoreFollowerCoreExport.hpp"

#include <memory>

namespace scorefollower::dsp {

// Constructs the library's current AlignmentEngine implementation: a
// row-synchronous, fixed-width-band Online Dynamic Time Warping search (see
// OnlineDtwAlignmentEngine and TECHNICAL_CHANGELOG.md).
SCORE_FOLLOWER_CORE_API std::unique_ptr<AlignmentEngine> createAlignmentEngine();

}  // namespace scorefollower::dsp
