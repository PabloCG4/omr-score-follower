// Cross-platform symbol export/import macro for the score_follower_core
// shared library. On Windows, symbols are hidden by default and must be
// explicitly exported; on POSIX systems with hidden visibility as the
// default compiler setting, symbols must be explicitly given default
// visibility to be part of the shared library's public ABI.
#pragma once

#if defined(_WIN32) || defined(_WIN64)
    #if defined(SCORE_FOLLOWER_CORE_BUILDING_SHARED_LIBRARY)
        #define SCORE_FOLLOWER_CORE_API __declspec(dllexport)
    #else
        #define SCORE_FOLLOWER_CORE_API __declspec(dllimport)
    #endif
#elif defined(__GNUC__) || defined(__clang__)
    #define SCORE_FOLLOWER_CORE_API __attribute__((visibility("default")))
#else
    #define SCORE_FOLLOWER_CORE_API
#endif
