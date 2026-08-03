"""
Chromagram (Pitch Class Profile) extraction pipeline.

This module implements the acoustic feature extraction stage of the Score
Following Engine. It computes a chromagram from an audio signal, which
represents the relative intensity of each of the twelve pitch classes
(C, C#, D, D#, E, F, F#, G, G#, A, A#, B) over time, independent of octave.

The extraction pipeline applies three DSP refinements over a naive
STFT-based approach, each targeting a specific failure mode observed in
practice:

1. Harmonic-Percussive Source Separation (HPSS): the percussive component
   (broadband transients such as keystrokes, onsets, and other noise) is
   discarded before pitch analysis, since it pollutes chroma bins with
   energy that is not tied to any specific pitch class.
2. Dynamic tuning estimation: rather than assuming a perfect A4 = 440 Hz
   reference, the actual tuning deviation of the recording is estimated
   from its harmonic content and fed into the Constant-Q analysis so that
   frequency bins align with the instrument's real pitch center.
3. Constant-Q Transform (CQT): frequency bins are spaced logarithmically,
   matching the logarithmic nature of musical pitch. This gives every
   semitone, including in low octaves, a comparable number of analysis
   bins, unlike the linearly spaced bins of an STFT.

The resulting chromagram is the primary acoustic feature that will later be
consumed by the Online Dynamic Time Warping (DTW) alignment module to match
a live microphone performance against a reference musical score.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Optional

import librosa
import librosa.display
import matplotlib.pyplot as plt
import numpy as np
from numpy.typing import NDArray

CONSTANT_Q_MINIMUM_FREQUENCY_HZ: float = float(librosa.note_to_hz("C1"))


@dataclass(frozen=True)
class ChromagramExtractionConfig:
    """Configuration parameters governing the CQT-based chromagram computation."""

    targetSampleRateHz: int = 22050
    hopLengthSamples: int = 512
    pitchClassCount: int = 12
    constantQBinsPerOctave: int = 36
    constantQOctaveCount: int = 7
    constantQMinimumFrequencyHz: float = CONSTANT_Q_MINIMUM_FREQUENCY_HZ
    harmonicPercussiveSeparationMargin: float = 3.0
    tuningEstimationResolution: float = 0.01


class ChromagramExtractor:
    """
    Extracts a Constant-Q Transform based chromagram from an audio file.

    The chromagram folds the harmonic spectral energy distribution into
    twelve pitch class bins per analysis frame, producing a timbre-invariant,
    octave-invariant representation of harmonic content. Using a
    logarithmically spaced Constant-Q Transform in place of a linearly
    spaced Short-Time Fourier Transform gives low-register semitones the
    same effective frequency resolution as high-register ones, which the
    STFT cannot provide. Combining this with Harmonic-Percussive Source
    Separation and per-recording tuning estimation makes the resulting
    chromagram robust to broadband noise, spectral leakage, and instruments
    that are not perfectly tuned to the standard A4 = 440 Hz reference,
    which is essential when aligning a live audio signal to a symbolic
    score representation via Dynamic Time Warping.
    """

    def __init__(self, config: Optional[ChromagramExtractionConfig] = None) -> None:
        self.config: ChromagramExtractionConfig = config or ChromagramExtractionConfig()
        self.rawAudioSignal: Optional[NDArray[np.float32]] = None
        self.sampleRateHz: Optional[int] = None
        self.harmonicAudioSignal: Optional[NDArray[np.float32]] = None
        self.percussiveAudioSignal: Optional[NDArray[np.float32]] = None
        self.estimatedTuningDeviation: Optional[float] = None
        self.constantQTransform: Optional[NDArray[np.complex64]] = None
        self.chromagram: Optional[NDArray[np.float32]] = None

    def loadAudioFile(self, audioFilePath: str) -> NDArray[np.float32]:
        """
        Loads an audio file from disk and resamples it to the configured target
        sample rate. Standardizing the sample rate guarantees a deterministic
        frequency-to-bin mapping regardless of the recording device used to
        capture the original signal.
        """
        if not os.path.isfile(audioFilePath):
            raise FileNotFoundError(f"Audio file not found at path: {audioFilePath}")

        audioSignal, sampleRateHz = librosa.load(
            audioFilePath,
            sr=self.config.targetSampleRateHz,
            mono=True,
        )
        self.rawAudioSignal = audioSignal.astype(np.float32)
        self.sampleRateHz = sampleRateHz
        return self.rawAudioSignal

    def separateHarmonicComponent(self) -> NDArray[np.float32]:
        """
        Applies Harmonic-Percussive Source Separation (HPSS) to the loaded
        audio signal and discards the percussive component. Broadband,
        non-pitched transients (onsets, keystrokes, background noise) are
        concentrated in the percussive component, so removing it before
        pitch analysis prevents that energy from polluting the chromagram.
        A margin greater than one biases the median-filtering masks toward a
        cleaner, more conservative separation at the cost of slightly
        attenuating sharp note attacks, which is an acceptable trade-off
        since only sustained harmonic content is relevant for chroma
        extraction.
        """
        if self.rawAudioSignal is None:
            raise RuntimeError(
                "Audio signal must be loaded before source separation. Call loadAudioFile first."
            )

        harmonicComponent, percussiveComponent = librosa.effects.hpss(
            self.rawAudioSignal,
            margin=self.config.harmonicPercussiveSeparationMargin,
        )
        self.harmonicAudioSignal = harmonicComponent.astype(np.float32)
        self.percussiveAudioSignal = percussiveComponent.astype(np.float32)
        return self.harmonicAudioSignal

    def estimateTuningDeviation(self) -> float:
        """
        Estimates the tuning deviation of the harmonic component relative to
        the standard twelve-tone equal temperament grid anchored at
        A4 = 440 Hz. The result is expressed in fractions of a semitone bin.
        Estimating tuning per recording, instead of assuming a perfect
        reference, prevents energy peaks from a slightly sharp or flat
        instrument from bleeding into neighboring Pitch Class bins.
        """
        if self.harmonicAudioSignal is None:
            self.separateHarmonicComponent()

        self.estimatedTuningDeviation = float(
            librosa.estimate_tuning(
                y=self.harmonicAudioSignal,
                sr=self.sampleRateHz,
                resolution=self.config.tuningEstimationResolution,
                bins_per_octave=self.config.pitchClassCount,
            )
        )
        return self.estimatedTuningDeviation

    def computeConstantQTransform(self) -> NDArray[np.complex64]:
        """
        Computes the Constant-Q Transform of the harmonic component, using
        the estimated tuning deviation so that its logarithmically spaced
        frequency bins align with the instrument's real pitch centers rather
        than an idealized A4 = 440 Hz grid. Unlike the STFT, the CQT spaces
        bins geometrically, giving every semitone comparable resolution
        across the whole pitch range, including the lower octaves where an
        STFT bin spacing is too coarse to separate adjacent semitones.
        """
        if self.harmonicAudioSignal is None:
            self.separateHarmonicComponent()
        if self.estimatedTuningDeviation is None:
            self.estimateTuningDeviation()

        self.constantQTransform = librosa.cqt(
            y=self.harmonicAudioSignal,
            sr=self.sampleRateHz,
            hop_length=self.config.hopLengthSamples,
            fmin=self.config.constantQMinimumFrequencyHz,
            n_bins=self.config.constantQOctaveCount * self.config.constantQBinsPerOctave,
            bins_per_octave=self.config.constantQBinsPerOctave,
            tuning=self.estimatedTuningDeviation,
        )
        return self.constantQTransform

    def extractChromagram(self) -> NDArray[np.float32]:
        """
        Extracts the CQT-based chromagram (Pitch Class Profile) from the
        previously computed Constant-Q Transform. Each of the twelve rows
        corresponds to a pitch class and each column corresponds to an
        analysis frame in time.
        """
        if self.constantQTransform is None:
            self.computeConstantQTransform()

        constantQMagnitude = np.abs(self.constantQTransform)
        chromagram = librosa.feature.chroma_cqt(
            C=constantQMagnitude,
            sr=self.sampleRateHz,
            hop_length=self.config.hopLengthSamples,
            fmin=self.config.constantQMinimumFrequencyHz,
            bins_per_octave=self.config.constantQBinsPerOctave,
            n_octaves=self.config.constantQOctaveCount,
            tuning=self.estimatedTuningDeviation,
            n_chroma=self.config.pitchClassCount,
        )
        self.chromagram = chromagram.astype(np.float32)
        return self.chromagram

    def processAudioFile(self, audioFilePath: str) -> NDArray[np.float32]:
        """
        Convenience pipeline method that runs the full extraction sequence,
        loading the audio file, separating its harmonic component, estimating
        its tuning deviation, computing its Constant-Q Transform, and
        returning the resulting chromagram in a single call.
        """
        self.loadAudioFile(audioFilePath)
        self.separateHarmonicComponent()
        self.estimateTuningDeviation()
        self.computeConstantQTransform()
        return self.extractChromagram()

    def getTuningDeviationInCents(self) -> float:
        """
        Converts the estimated tuning deviation from fractional semitone bins
        into cents (one semitone equals one hundred cents), which is a more
        commonly reported unit for describing tuning offsets.
        """
        if self.estimatedTuningDeviation is None:
            raise RuntimeError("Tuning deviation has not been estimated yet. Call estimateTuningDeviation first.")
        return self.estimatedTuningDeviation * 100.0

    def plotChromagram(
        self,
        outputImagePath: str,
        figureTitle: str = "Constant-Q Chromagram (Pitch Class Profile)",
    ) -> None:
        """
        Renders the chromagram as a clean, clearly labeled time-versus-pitch-
        class heatmap and saves it to disk as a high-resolution image. The
        subtitle reports the estimated tuning deviation so that the plot is
        self-documenting regarding the tuning correction applied upstream.
        """
        if self.chromagram is None:
            raise RuntimeError("Chromagram has not been computed yet. Call extractChromagram first.")

        figure, axes = plt.subplots(figsize=(12, 6))
        chromaDisplay = librosa.display.specshow(
            self.chromagram,
            sr=self.sampleRateHz,
            hop_length=self.config.hopLengthSamples,
            x_axis="time",
            y_axis="chroma",
            cmap="magma",
            vmin=0.0,
            vmax=1.0,
            ax=axes,
        )

        tuningSubtitle = ""
        if self.estimatedTuningDeviation is not None:
            tuningSubtitle = f" (Estimated tuning deviation: {self.getTuningDeviationInCents():+.1f} cents)"
        axes.set_title(f"{figureTitle}{tuningSubtitle}")
        axes.set_xlabel("Time (seconds)")
        axes.set_ylabel("Pitch Class")
        figure.colorbar(chromaDisplay, ax=axes, label="Normalized Energy")
        figure.tight_layout()
        figure.savefig(outputImagePath, dpi=300)
        plt.close(figure)


if __name__ == "__main__":
    placeholderAudioFilePath = r"E:\Proyectos\OMR\audio\3 ago 2026, 15_03_34.wav"
    outputImagePath = r"E:\Proyectos\OMR\audio\chromagram_output_refactorized2.png"

    extractionConfig = ChromagramExtractionConfig()
    extractor = ChromagramExtractor(config=extractionConfig)

    try:
        chromagramResult = extractor.processAudioFile(placeholderAudioFilePath)
        tuningDeviationCents = extractor.getTuningDeviationInCents()
        print(f"Chromagram successfully computed with shape: {chromagramResult.shape}")
        print(f"Estimated tuning deviation: {tuningDeviationCents:+.1f} cents")
        extractor.plotChromagram(outputImagePath)
        print(f"Chromagram visualization saved to: {outputImagePath}")
    except FileNotFoundError as fileNotFoundError:
        print(
            f"Placeholder audio file not found: {fileNotFoundError}. "
            f"Place a valid audio file named '{placeholderAudioFilePath}' in this directory to run the extractor."
        )
