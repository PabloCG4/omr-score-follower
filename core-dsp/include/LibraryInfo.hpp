// Minimal, dependency-free entry point compiled into score_follower_core.
// Its purpose is twofold: it gives the shared library at least one concrete
// translation unit to build against, and it exposes a stable ABI version
// query that mobile host applications (JNI bindings on Android, or a Swift
// bridging layer on iOS) can call at startup to verify binary compatibility
// before invoking any of the DSP interfaces declared elsewhere in this
// library.
#pragma once

#include "ScoreFollowerCoreExport.hpp"

namespace scorefollower::dsp {

// Returns the semantic version string of the compiled score_follower_core
// shared library, for example "0.1.0".
SCORE_FOLLOWER_CORE_API const char* getLibraryVersionString() noexcept;

}  // namespace scorefollower::dsp
