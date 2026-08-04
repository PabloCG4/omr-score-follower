// Plain-C application binary interface (ABI) over score_follower_core,
// intended for consumption across a foreign-function-interface (FFI)
// boundary (in particular, Dart FFI from a Flutter host application). Unlike
// every other header in include/, this file is deliberately restricted to
// C-compatible syntax throughout (no namespaces, no references, no default
// arguments) so that binding generators built on a C parser (e.g. ffigen,
// which uses libclang) can consume it directly without a C++ front end.
//
// This is not a mechanical one-to-one exposure of AlignmentEngine.hpp and
// FeatureExtractor.hpp: those two interfaces are produced and consumed
// independently by score_follower_core's C++ callers, with no built-in glue
// connecting a FeatureExtractor's output to an AlignmentEngine's input. The
// opaque ScoreFollowerEngine handle declared below is a small additional
// object, implemented in ScoreFollowerCApi.cpp, that owns one instance of
// each and forwards data between them, so that a single push_audio_frame
// call is enough to drive the full extraction-then-alignment pipeline.
#pragma once

#include "ScoreFollowerCoreExport.hpp"

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Number of pitch classes per chroma frame, mirroring
// scorefollower::dsp::PitchClassCount (Chromagram.hpp). Exposed here as a
// plain macro so that Dart callers building
// score_follower_load_reference_chromagram's flat input array know its
// row stride without hardcoding the value independently.
#define SCORE_FOLLOWER_PITCH_CLASS_COUNT 12

// Opaque handle to a ScoreFollowerEngine instance. Its real definition
// (a struct owning a FeatureExtractor and an AlignmentEngine) lives entirely
// inside ScoreFollowerCApi.cpp and is never exposed across this boundary.
typedef struct ScoreFollowerEngine ScoreFollowerEngine;

// Plain-old-data mirror of scorefollower::dsp::AlignmentPosition
// (AlignmentEngine.hpp), returned by value so that callers (including Dart,
// via an ffi.Struct subclass) never need to manage its memory explicitly.
typedef struct {
    double reference_frame_index;
    double alignment_confidence;
    double cumulative_distortion_cost;
} ScoreFollowerAlignmentPosition;

// Constructs a new engine configured for the given audio sample rate and
// hop length (both forwarded verbatim to the underlying FeatureExtractor's
// FeatureExtractionConfiguration; all other extraction parameters keep
// their library defaults). Returns NULL on failure (for example, if
// construction throws due to an allocation failure); callers must check for
// NULL before passing the result to any other function in this header.
SCORE_FOLLOWER_CORE_API ScoreFollowerEngine* score_follower_create(double sample_rate_hz,
                                                                    size_t hop_length_samples);

// Destroys a previously created engine and releases all of its resources.
// Passing NULL is a safe no-op. The handle must not be used again after
// this call returns.
SCORE_FOLLOWER_CORE_API void score_follower_destroy(ScoreFollowerEngine* engine);

// Supplies the reference chromagram the live performance will be aligned
// against, as a flat, row-major array of frame_count *
// SCORE_FOLLOWER_PITCH_CLASS_COUNT floats (one row of
// SCORE_FOLLOWER_PITCH_CLASS_COUNT pitch-class energies per frame). This is
// a one-time, non-hot-path call, typically made once at the start of a
// performance right after score_follower_create. Returns 0 on success, a
// negative value on malformed input (a NULL engine, or a NULL data pointer
// paired with a non-zero frame_count) or on an internal allocation failure.
SCORE_FOLLOWER_CORE_API int score_follower_load_reference_chromagram(
    ScoreFollowerEngine* engine, const float* pitch_class_energies_row_major, size_t frame_count,
    double sample_rate_hz, size_t hop_length_samples);

// Pushes a contiguous block of newly captured, mono, already-resampled
// audio samples into the engine. Internally, this both feeds the
// FeatureExtractor and, for every chroma frame the extractor completes as a
// result, immediately advances the AlignmentEngine by one step. This is the
// only function in this header intended to be called from a real-time (or
// near-real-time) audio-producing thread; it never blocks, allocates, or
// throws across this boundary. Passing a NULL engine is a safe no-op.
SCORE_FOLLOWER_CORE_API void score_follower_push_audio_frame(ScoreFollowerEngine* engine,
                                                               const float* audio_samples,
                                                               size_t sample_count);

// Reads the engine's current estimate of the live performance's position
// within the reference score. Safe to call concurrently with
// score_follower_push_audio_frame from a different thread: internally, this
// only reads the atomically published fields OnlineDtwAlignmentEngine
// already maintains for exactly this purpose. Passing a NULL engine returns
// a zero-initialized position.
SCORE_FOLLOWER_CORE_API ScoreFollowerAlignmentPosition
score_follower_get_alignment_position(const ScoreFollowerEngine* engine);

// Resets the engine's extraction and alignment state (partially
// accumulated audio, current position, cumulative cost) so a new
// performance attempt can begin without discarding the already-loaded
// reference chromagram. Passing a NULL engine is a safe no-op.
SCORE_FOLLOWER_CORE_API void score_follower_reset(ScoreFollowerEngine* engine);

#ifdef __cplusplus
}  // extern "C"
#endif
