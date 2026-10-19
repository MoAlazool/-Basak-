// Runs around every test file. With RENDER_SCALE set (the preview tests'
// second pass), every test draws at that text scale, as a phone whose owner
// enlarged the text would:
//   RENDER_SCALE=1.3 RENDER_DIR=/tmp/basak-130 flutter test test/ui test/render_preview_test.dart
// Without it nothing changes.
//
// The company clock (CairoClock) follows the machine's clock in tests, so the
// fixtures written around DateTime.now() hold wherever the tests run;
// test/cairo_clock_test.dart checks the Cairo conversion itself.
import 'dart:async';
import 'dart:io';

import 'package:basak_mobile/core/time/cairo_clock.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  CairoClock.debugNow = DateTime.now;
  final scale = double.tryParse(Platform.environment['RENDER_SCALE'] ?? '');
  if (scale != null) {
    setUp(() {
      final dispatcher = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
      dispatcher.textScaleFactorTestValue = scale;
      addTearDown(dispatcher.clearTextScaleFactorTestValue);
    });
  }
  await testMain();
}
