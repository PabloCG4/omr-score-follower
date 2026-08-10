# score_follower_poc

Phase 5.1 proof-of-concept Flutter app. Presents a single Start/Stop button
and a raw text readout of `score_follower_core`'s tracked reference frame
index, alignment confidence, and cumulative distortion cost, updated
roughly 30 times per second while running. Deliberately not a score
renderer or page-turn UI; see the Phase 5.1 architectural plan and
`../../TECHNICAL_CHANGELOG.md`.

## Scaffolding status and required one-time setup

Only the Dart-level, project-specific files were authored by hand in this
checkout: `pubspec.yaml` and `lib/main.dart`. The rest of a normal Flutter
app (the `android/`, `ios/` platform boilerplate that `flutter create`
mechanically generates: Gradle files, `MainActivity`, the Xcode project,
default app icons, etc.) is intentionally **not** included here, because
neither the Flutter SDK nor the Dart SDK were available in the environment
this app was scaffolded in, and hand-fabricating that boilerplate from
memory (rather than letting `flutter create` generate it correctly) would
risk subtle, hard-to-detect build errors on a real device with no way to
catch them ahead of time.

On a machine with a real Flutter SDK installed:

1. From this directory, run `flutter create --platforms=android,ios .` to
   generate the missing `android/` and `ios/` platform folders (this only
   adds the platform folders; it does not need to, and should not, replace
   the `lib/main.dart` and `pubspec.yaml` already checked in here — compare
   before overwriting if prompted).
2. Add the two permission entries below, exactly as described, to the
   newly generated platform files. Both are easy to forget and otherwise
   surface only as a silent runtime failure on a real device, never in
   analysis or a desktop build.
   - `android/app/src/main/AndroidManifest.xml`: add
     `<uses-permission android:name="android.permission.RECORD_AUDIO" />`
     as a direct child of the top-level `<manifest>` element, alongside any
     other `<uses-permission>` entries `flutter create` already added.
   - `ios/Runner/Info.plist`: add an `NSMicrophoneUsageDescription` string
     key/value pair (for example, `"This app listens to your instrument to
     follow along with the score."`) as a direct child of the top-level
     `<dict>` element.
3. `flutter pub get` (transitively runs `../score_follower_bridge`'s build
   hook, compiling `../../core-dsp` for the host desktop platform first).
4. `flutter run` on a desktop target first (fastest iteration loop, per
   this project's own established validate-cheaply-first practice), before
   attempting a real Android or iOS device build.

## Reference chromagram and live tracking

Live microphone audio is converted to query chromagrams inside the native CQT
pipeline (`score_follower_bridge` / `core-dsp`). The Online DTW engine aligns
those live features against a **reference chromagram injected from Dart** via
`ScoreFollowerEngine.loadReferenceChromagram`:

- **Imported Ready scores:** floats decoded from the OMR `structural.json`
  written during PDF ingestion (`ScoreDocumentLoader.loadFromPersistedStructural`).
- **Bundled demo (`demo_four_chords`):** floats from
  `assets/scores/demo_four_chords/reference_chromagram.f32`, matching the
  progression historically validated by `../../core-dsp/tests/dtw_validator.cpp`.

The native library does not embed a hardcoded demo score; an unloaded reference
leaves DTW idle until Dart injects chromagram data.
