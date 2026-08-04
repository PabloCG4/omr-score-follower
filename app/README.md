# app/

Phase 5.1 (Mobile Integration) Flutter workspace, sitting alongside
`../core-dsp` at the repository root.

- `score_follower_bridge/` — Dart FFI bridge package exposing
  `../core-dsp`'s C++ engine to Flutter via `dart:ffi` and a Dart build
  hook. See its own `README.md` for the required one-time setup.
- `score_follower_poc/` — minimal Flutter app (Start/Stop button, raw text
  readout) proving the microphone-capture-to-alignment pipeline is alive
  end-to-end. Depends on `score_follower_bridge` via a relative `path:`
  entry. See its own `README.md` for the required one-time setup.

Neither the Dart SDK nor the Flutter SDK were available in the environment
these two packages were scaffolded in, so every Dart/Flutter-level file in
both directories was authored by hand against the current native-assets/
`dart:ffi` toolchain, but has not actually been run (`pub get`, the build
hook, `ffigen`, `flutter run`, or any test). Both packages' own `README.md`
files spell out the exact commands to run first, in order, on a machine
with a real Flutter SDK installed, before relying on any of this code.
`../core-dsp`'s own C++ side (`ScoreFollowerCApi.h`/`.cpp`) has, by
contrast, been fully compiled, linked (including as an actual shared
library), and exercised against synthetic data with the toolchain that
*was* available; see `../TECHNICAL_CHANGELOG.md`.
