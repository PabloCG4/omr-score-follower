// Implementation of the plain-C ABI declared in ScoreFollowerCApi.h. This
// is the only translation unit in score_follower_core that connects a
// FeatureExtractor's output directly to an AlignmentEngine's input; every
// other consumer of these two interfaces (cqt_validator, dtw_validator)
// exercises them independently.
#include "ScoreFollowerCApi.h"

#include "AlignmentEngine.hpp"
#include "AlignmentEngineFactory.hpp"
#include "Chromagram.hpp"
#include "FeatureExtractor.hpp"
#include "FeatureExtractorFactory.hpp"

#include <memory>
#include <optional>

using scorefollower::dsp::AlignmentEngine;
using scorefollower::dsp::AlignmentPosition;
using scorefollower::dsp::ChromaVector;
using scorefollower::dsp::Chromagram;
using scorefollower::dsp::FeatureExtractionConfiguration;
using scorefollower::dsp::FeatureExtractor;
using scorefollower::dsp::PitchClassCount;
using scorefollower::dsp::createAlignmentEngine;
using scorefollower::dsp::createConstantQFeatureExtractor;

// Real definition of the opaque handle declared in ScoreFollowerCApi.h.
// Deliberately owns its two sub-engines as C++ objects (not exposed across
// the C boundary) and provides the extraction-to-alignment glue that
// neither sub-engine implements on its own.
struct ScoreFollowerEngine {
    std::unique_ptr<FeatureExtractor> featureExtractor;
    std::unique_ptr<AlignmentEngine> alignmentEngine;
};

namespace {

ScoreFollowerAlignmentPosition toCApiAlignmentPosition(const AlignmentPosition& position) noexcept {
    ScoreFollowerAlignmentPosition capiPosition{};
    capiPosition.reference_frame_index = position.referenceFrameIndex;
    capiPosition.alignment_confidence = position.alignmentConfidence;
    capiPosition.cumulative_distortion_cost = position.cumulativeDistortionCost;
    return capiPosition;
}

}  // namespace

extern "C" {

ScoreFollowerEngine* score_follower_create(double sample_rate_hz, size_t hop_length_samples) {
    try {
        std::unique_ptr<ScoreFollowerEngine> engine = std::make_unique<ScoreFollowerEngine>();
        engine->featureExtractor = createConstantQFeatureExtractor();
        engine->alignmentEngine = createAlignmentEngine();

        FeatureExtractionConfiguration configuration;
        configuration.sampleRateHz = sample_rate_hz;
        configuration.hopLengthSamples = hop_length_samples;
        // Live FFI path: keep the mobile real-time defaults (8192-point CQT
        // ceiling, no unbounded chromagram accumulation). Offline validators
        // override these when they configure a FeatureExtractor directly.
        configuration.maximumTransformLength = 8192;
        configuration.accumulateChromagramFrames = false;
        configuration.maxPendingChromaFrames = 8;
        engine->featureExtractor->configure(configuration);

        return engine.release();
    } catch (...) {
        // Construction/configuration is not documented as real-time-safe (it
        // is expected to allocate), so an exception here is plausible under
        // memory pressure; report failure through the NULL-handle contract
        // instead of letting the exception cross this extern "C" boundary.
        return nullptr;
    }
}

void score_follower_destroy(ScoreFollowerEngine* engine) {
    delete engine;  // delete on a NULL pointer is a well-defined no-op.
}

int score_follower_load_reference_chromagram(ScoreFollowerEngine* engine,
                                               const float* pitch_class_energies_row_major, size_t frame_count,
                                               double sample_rate_hz, size_t hop_length_samples) {
    if (engine == nullptr || (pitch_class_energies_row_major == nullptr && frame_count > 0)) {
        return -1;
    }
    try {
        Chromagram referenceChromagram;
        referenceChromagram.sampleRateHz = sample_rate_hz;
        referenceChromagram.hopLengthSamples = hop_length_samples;
        referenceChromagram.frames.resize(frame_count);
        for (size_t frameIndex = 0; frameIndex < frame_count; ++frameIndex) {
            ChromaVector& frame = referenceChromagram.frames[frameIndex];
            const float* frameEnergies = pitch_class_energies_row_major + (frameIndex * PitchClassCount);
            for (size_t pitchClass = 0; pitchClass < PitchClassCount; ++pitchClass) {
                frame.pitchClassEnergies[pitchClass] = frameEnergies[pitchClass];
            }
        }
        engine->alignmentEngine->loadReferenceChromagram(referenceChromagram);
        return 0;
    } catch (...) {
        return -2;
    }
}

void score_follower_push_audio_frame(ScoreFollowerEngine* engine, const float* audio_samples,
                                      size_t sample_count) {
    if (engine == nullptr) {
        return;
    }
    try {
        engine->featureExtractor->ingestAudioFrame(audio_samples, sample_count);
        while (const std::optional<ChromaVector> liveChromaVector = engine->featureExtractor->pollLatestChromaVector()) {
            engine->alignmentEngine->ingestLiveChromaVector(*liveChromaVector);
        }
    } catch (...) {
        // C++ exceptions must never unwind across an extern "C" frame: doing
        // so is undefined behavior on the Android NDK/iOS toolchains this
        // library targets, and Dart FFI has no exception model to catch it
        // regardless. ingestAudioFrame and pollLatestChromaVector are
        // documented allocation-free in steady state (once configure has
        // run), and ingestLiveChromaVector likewise for
        // OnlineDtwAlignmentEngine, so this guard is a hard safety net
        // against undefined behavior, not an expected code path; there is
        // deliberately no partial-progress recovery here beyond dropping the
        // remainder of this call.
    }
}

ScoreFollowerAlignmentPosition score_follower_get_alignment_position(const ScoreFollowerEngine* engine) {
    if (engine == nullptr) {
        return ScoreFollowerAlignmentPosition{};
    }
    try {
        return toCApiAlignmentPosition(engine->alignmentEngine->getCurrentAlignmentPosition());
    } catch (...) {
        return ScoreFollowerAlignmentPosition{};
    }
}

int score_follower_seek_to_reference_frame(ScoreFollowerEngine* engine, double reference_frame_index) {
    if (engine == nullptr) {
        return -1;
    }
    try {
        engine->featureExtractor->reset();
        engine->alignmentEngine->seekToReferenceFrame(reference_frame_index);
        return 0;
    } catch (...) {
        return -2;
    }
}

int score_follower_set_tracking_mode(ScoreFollowerEngine* engine, ScoreFollowerTrackingMode mode) {
    if (engine == nullptr) {
        return -1;
    }
    try {
        scorefollower::dsp::TrackingMode trackingMode;
        switch (mode) {
            case SCORE_FOLLOWER_TRACKING_MODE_RUBATO:
                trackingMode = scorefollower::dsp::TrackingMode::Rubato;
                break;
            case SCORE_FOLLOWER_TRACKING_MODE_STRICT:
                trackingMode = scorefollower::dsp::TrackingMode::Strict;
                break;
            case SCORE_FOLLOWER_TRACKING_MODE_FIXED_TEMPO:
                // Native alignment stays Rubato-equivalent; Dart owns the cursor.
                trackingMode = scorefollower::dsp::TrackingMode::FixedTempo;
                break;
            default:
                return -3;
        }
        engine->alignmentEngine->setTrackingMode(trackingMode);
        return 0;
    } catch (...) {
        return -2;
    }
}

int score_follower_set_strict_confidence_threshold(ScoreFollowerEngine* engine, double threshold) {
    if (engine == nullptr) {
        return -1;
    }
    if (!(threshold >= 0.0 && threshold <= 1.0)) {
        return -3;
    }
    try {
        engine->alignmentEngine->setStrictConfidenceThreshold(threshold);
        return 0;
    } catch (...) {
        return -2;
    }
}

void score_follower_reset(ScoreFollowerEngine* engine) {
    if (engine == nullptr) {
        return;
    }
    try {
        engine->featureExtractor->reset();
        engine->alignmentEngine->reset();
    } catch (...) {
        // Swallow defensively; see score_follower_push_audio_frame's comment.
    }
}

}  // extern "C"
