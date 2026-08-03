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

// Constructs the library's current AlignmentEngine implementation. As of
// this writing this returns a minimal nearest-frame placeholder (bounded-
// window cosine-similarity matching, not a real Dynamic Time Warping
// search); see TECHNICAL_CHANGELOG.md. A real Online DTW engine is planned
// as a follow-up, drop-in replacement behind this same factory function.
SCORE_FOLLOWER_CORE_API std::unique_ptr<AlignmentEngine> createAlignmentEngine();

}  // namespace scorefollower::dsp
