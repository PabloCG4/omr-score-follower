# score_follower_bridge

Dart FFI bridge exposing the `score_follower_core` C++ engine (see
`../../core-dsp`) to Flutter host applications, built on the current
(`package_ffi`/Dart build-hook) native-assets toolchain rather than the
deprecated `plugin_ffi` per-platform template.

## Scaffolding status and required one-time setup

Every file in this package (`pubspec.yaml`, `hook/build.dart`,
`ffigen.yaml`, `lib/score_follower_bridge.dart`,
`lib/src/score_follower_bindings.dart`) was authored by hand and is believed
correct against the current (as of this writing) Dart native-assets/hooks
API. However, neither the Dart SDK, the Flutter SDK, nor `ffigen` were
available in the environment this package was scaffolded in, so **none of
it has actually been run**: not `dart pub get`, not `hook/build.dart`, not
`dart run ffigen`, not `dart analyze`. Treat this package as a
ready-to-validate design, not a proven-working build.

Before relying on it, on a machine with a real Flutter/Dart SDK installed:

1. `cd app/score_follower_bridge && flutter pub get` (or `dart pub get`).
   This is also what first exercises `hook/build.dart`, i.e. what actually
   compiles `core-dsp` for the host desktop platform. Fix any toolchain
   version mismatches (`code_assets`/`hooks`/`native_toolchain_cmake` were
   deliberately left unpinned in `pubspec.yaml`; see its own comment) as
   they surface.
2. `dart run ffigen` to regenerate `lib/src/score_follower_bindings.dart`
   from `../../core-dsp/include/ScoreFollowerCApi.h` and confirm it matches
   the hand-written version in this checkout (see that file's own header
   comment). Diff before overwriting, in case the hand-written version
   needs a correction rather than the reverse.
3. `dart analyze` and `dart test` against a small hand-written test that
   exercises `ScoreFollowerEngine.create` /
   `loadReferenceChromagram` / `pushAudioFrame` /
   `getCurrentAlignmentPosition` / `dispose` with the same synthetic data
   `core-dsp/tests/dtw_validator.cpp` already validates, mirroring this
   project's established validate-cheaply-first practice for every prior
   DSP phase (see `TECHNICAL_CHANGELOG.md`).
4. Only after the above succeeds on desktop, attempt an Android/iOS device
   build from `../score_follower_poc`.

## Why a plain Dart package, not a Flutter plugin

This package needs no `MethodChannel`, Android Gradle, or CocoaPods
integration; Flutter's own `flutter create -h` recommends the `plugin`
template only when that is needed. A plain Dart package with a build hook
is sufficient and simpler.

## API surface

See `lib/score_follower_bridge.dart`'s own documentation comments for the
full API. In short: `ScoreFollowerEngine.create(...)` owns the native engine
and its persistent audio-push buffer; `engine.loadReferenceChromagram(...)`
loads the reference score's chromagram once; a background isolate should
reconstruct a `ScoreFollowerAudioPushChannel` from
`engine.audioPushChannel` and call `pushAudioFrame`/`pushPcm16Frame` on
every captured audio chunk; the UI isolate polls
`engine.getCurrentAlignmentPosition()` (or a `ScoreFollowerPositionReader`
reconstructed from `engine.positionReaderHandleAddress`, if polling from yet
another isolate) on a timer; `engine.dispose()` releases everything.
