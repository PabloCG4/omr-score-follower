# core-dsp: production C++ core DSP engine for the Mobile OMR Score Following
# Engine. Builds the score_follower_core shared library, intended to be
# consumed by platform-specific host applications (Android via JNI, iOS via a
# Swift/Objective-C++ bridge) through the public interfaces declared in
# include/.

cmake_minimum_required(VERSION 3.18)

project(ScoreFollowerCore
    VERSION 0.1.0
    DESCRIPTION "Real-time acoustic feature extraction and score alignment core for the Mobile OMR Score Following Engine"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

set(SCORE_FOLLOWER_CORE_PUBLIC_HEADERS
    include/ScoreFollowerCoreExport.hpp
    include/LibraryInfo.hpp
    include/Chromagram.hpp
    include/CircularAudioBuffer.hpp
    include/FeatureExtractor.hpp
    include/AlignmentEngine.hpp
)

set(SCORE_FOLLOWER_CORE_SOURCES
    src/LibraryInfo.cpp
)

add_library(score_follower_core SHARED
    ${SCORE_FOLLOWER_CORE_SOURCES}
    ${SCORE_FOLLOWER_CORE_PUBLIC_HEADERS}
)
add_library(ScoreFollowerCore::score_follower_core ALIAS score_follower_core)

target_include_directories(score_follower_core
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
)

target_compile_definitions(score_follower_core
    PRIVATE
        SCORE_FOLLOWER_CORE_BUILDING_SHARED_LIBRARY
)

set_target_properties(score_follower_core PROPERTIES
    VERSION ${PROJECT_VERSION}
    SOVERSION ${PROJECT_VERSION_MAJOR}
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
    POSITION_INDEPENDENT_CODE ON
)

if(MSVC)
    target_compile_options(score_follower_core PRIVATE
        /W4
        /permissive-
        $<$<CONFIG:Release>:/O2>
    )
else()
    target_compile_options(score_follower_core PRIVATE
        -Wall
        -Wextra
        -Wpedantic
        $<$<CONFIG:Release>:-O3>
    )
endif()

# RTTI is unnecessary for this library's interface-based (pure virtual)
# design; disabling it keeps the compiled footprint smaller, which matters on
# mobile targets. Exceptions are intentionally left enabled at this stage,
# since the standard containers used by the public interfaces (e.g.
# std::vector inside Chromagram) rely on them for allocation failure
# reporting; real-time-critical call paths must instead be designed to avoid
# triggering allocations in the first place, as CircularAudioBuffer already
# does.
if(NOT MSVC)
    target_compile_options(score_follower_core PRIVATE -fno-rtti)
endif()

install(
    TARGETS score_follower_core
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin
    ARCHIVE DESTINATION lib
)
install(
    DIRECTORY include/
    DESTINATION include
    FILES_MATCHING PATTERN "*.hpp"
)
