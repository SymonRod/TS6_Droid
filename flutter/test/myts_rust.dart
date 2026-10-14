// Loads the native `tslib-frb` library for tests that exercise the Rust
// myTeamSpeak codec through flutter_rust_bridge.
//
// Build a host library first (it needs ALSA headers because tslib-audio pulls
// in cpal), e.g. in ../ts6-lib: `cargo build -p tslib-frb`, then point
// TSLIB_FRB_LIB at target/debug/libtslib_frb.so. Without it these tests fail
// with a clear message instead of silently skipping.
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:ts6_flutter/src/rust/frb_generated.dart';

Future<void> initRustForTests() async {
  final path = Platform.environment['TSLIB_FRB_LIB'];
  if (path == null || path.isEmpty) {
    throw StateError('Set TSLIB_FRB_LIB to a host build of libtslib_frb.so '
        '(cargo build -p tslib-frb in ts6-lib).');
  }
  await RustLib.init(externalLibrary: ExternalLibrary.open(path));
}
