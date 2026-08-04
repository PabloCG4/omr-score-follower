// Dart build hook: transitively invoked by `dart pub get`/`flutter pub get`
// for every consumer of this package. Drives ../../core-dsp's own,
// unmodified CMakeLists.txt through native_toolchain_cmake's CMakeBuilder
// (no restructuring of core-dsp needed: this reuses its existing
// `install(TARGETS score_follower_core ...)` rule verbatim as the
// `targets: ['install']` target below), then registers the resulting
// installed shared library as the code asset that every @Native external
// function in lib/src/score_follower_bindings.dart resolves against at
// runtime.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    // Resolve core-dsp to an absolute path from this package's root so the
    // CMake -S argument never depends on the hooks_runner working directory
    // (which is the consuming app, not score_follower_bridge).
    final packageRootDirectory = Directory.fromUri(input.packageRoot);
    final coreDspSourceDirectory =
        Directory.fromUri(packageRootDirectory.uri.resolve('../../core-dsp/')).absolute;
    final cmakeListsFile = File.fromUri(coreDspSourceDirectory.uri.resolve('CMakeLists.txt'));
    if (!cmakeListsFile.existsSync()) {
      throw StateError(
        'core-dsp CMakeLists.txt not found at ${cmakeListsFile.path}. '
        'packageRoot=${input.packageRoot.toFilePath()}',
      );
    }

    // Without an explicit CMAKE_INSTALL_PREFIX, CMake defaults to
    // C:/Program Files/... on Windows; cmake --build --target install then
    // fails without admin rights (the failure mode observed by flutter run).
    // Point install into the hook's own output directory instead, matching
    // native_toolchain_cmake's own documented example layout.
    final installPrefixDirectory =
        Directory.fromUri(input.outputDirectory.resolve('install/')).absolute;
    final installPrefixPath = installPrefixDirectory.path.replaceAll(r'\', '/');

    final builder = CMakeBuilder.create(
      name: 'score_follower_core',
      sourceDir: coreDspSourceDirectory.uri,
      defines: {
        'CMAKE_BUILD_TYPE': 'Release',
        'CMAKE_INSTALL_PREFIX': installPrefixPath,
        // Diagnostic CLI validators (cqt_validator, dtw_validator) are
        // desktop-only throwaway tools with no role in a mobile build;
        // cross-compiling them here would be wasted work and a potential
        // source of failures unrelated to score_follower_core itself.
        'SCORE_FOLLOWER_CORE_BUILD_VALIDATORS': 'OFF',
      },
      targets: ['install'],
    );
    await builder.run(input: input, output: output);

    // score_follower_core's CMakeLists.txt installs the shared library as
    // score_follower_core.dll under <prefix>/bin (Windows RUNTIME) or
    // libscore_follower_core.so/.dylib under <prefix>/lib (POSIX LIBRARY).
    // Restrict the search to the install prefix so we never pick up a
    // stale intermediate build artifact from the CMake build tree.
    await output.findAndAddCodeAssets(
      input,
      names: {
        r'(lib)?score_follower_core\.(dll|so|dylib)': 'src/score_follower_bindings.dart',
      },
      outDir: installPrefixDirectory.uri,
      regExp: true,
    );
  });
}
