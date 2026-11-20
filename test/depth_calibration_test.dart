import 'package:flutter_test/flutter_test.dart';
import 'package:baseerte_ai/depth/depth_calibration.dart';

void main() {
  test('fits notebook linear calibration from measured samples', () {
    final samples = [
      const CalibrationSample(rawMeters: 2.0, actualMeters: 1.0),
      const CalibrationSample(rawMeters: 3.0, actualMeters: 2.0),
      const CalibrationSample(rawMeters: 4.0, actualMeters: 3.0),
      const CalibrationSample(rawMeters: 5.0, actualMeters: 4.0),
    ];
    final fitted = DepthCalibration.fit(samples);
    expect(fitted, isNotNull);
    expect(fitted!.slope, closeTo(1.0, 1e-10));
    expect(fitted.intercept, closeTo(-1.0, 1e-10));
    expect(fitted.apply(3.5), closeTo(2.5, 1e-10));
  });

  test('does not fit too few samples', () {
    final fitted = DepthCalibration.fit([
      const CalibrationSample(rawMeters: 3.0, actualMeters: 2.0),
      const CalibrationSample(rawMeters: 4.0, actualMeters: 3.0),
    ]);
    expect(fitted, isNull);
  });

  test('rejects unchanging model outputs', () {
    final fitted = DepthCalibration.fit([
      const CalibrationSample(rawMeters: 3.0, actualMeters: 1.0),
      const CalibrationSample(rawMeters: 3.0, actualMeters: 2.0),
      const CalibrationSample(rawMeters: 3.0, actualMeters: 3.0),
    ]);
    expect(fitted, isNull);
  });

  test('rejects decreasing raw depth when real distance increases', () {
    final fitted = DepthCalibration.fit([
      const CalibrationSample(rawMeters: 3.0, actualMeters: 1.0),
      const CalibrationSample(rawMeters: 2.0, actualMeters: 2.0),
      const CalibrationSample(rawMeters: 1.0, actualMeters: 3.0),
    ]);
    expect(fitted, isNull);
  });

  test('sample JSON round trip', () {
    const sample = CalibrationSample(rawMeters: 2.9, actualMeters: 1.9);
    final loaded = CalibrationSample.fromJson(sample.toJson());
    expect(loaded, isNotNull);
    expect(loaded!.rawMeters, sample.rawMeters);
    expect(loaded.actualMeters, sample.actualMeters);
  });
}
