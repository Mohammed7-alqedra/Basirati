import 'dart:math' as math;

/// One tape-measured test point. The model's raw output may still be wrong.
class CalibrationSample {
  final double rawMeters;
  final double actualMeters;

  const CalibrationSample({
    required this.rawMeters,
    required this.actualMeters,
  });

  Map<String, double> toJson() => {
        'rawMeters': rawMeters,
        'actualMeters': actualMeters,
      };

  static CalibrationSample? fromJson(Object? json) {
    if (json is! Map) return null;
    final raw = json['rawMeters'];
    final actual = json['actualMeters'];
    if (raw is! num || actual is! num) return null;
    final r = raw.toDouble();
    final a = actual.toDouble();
    if (!r.isFinite || !a.isFinite || r <= 0 || a <= 0) return null;
    return CalibrationSample(rawMeters: r, actualMeters: a);
  }
}

/// Replaces hard-coded coefficients with the notebook's np.polyfit approach.
/// This is an experimental least-squares fit, not a safety certification.
class DepthCalibration {
  final double slope;
  final double intercept;

  const DepthCalibration(this.slope, this.intercept);

  double apply(double rawMeters) =>
      math.max(0.0, slope * rawMeters + intercept);

  /// The notebook requires 2 samples. For phone testing, require at least 3
  /// and a range of tape measurements to avoid an unstable two-point fit.
  static DepthCalibration? fit(List<CalibrationSample> samples) {
    if (samples.length < 3) return null;

    final actualValues = samples.map((s) => s.actualMeters);
    if (actualValues.reduce(math.max) - actualValues.reduce(math.min) < 0.5) {
      return null;
    }

    final count = samples.length;
    final meanRaw =
        samples.fold<double>(0, (sum, s) => sum + s.rawMeters) / count;
    final meanActual =
        samples.fold<double>(0, (sum, s) => sum + s.actualMeters) / count;

    double covariance = 0;
    double variance = 0;
    for (final sample in samples) {
      final dx = sample.rawMeters - meanRaw;
      covariance += dx * (sample.actualMeters - meanActual);
      variance += dx * dx;
    }
    if (variance < 1e-8) return null;

    final slope = covariance / variance;
    final intercept = meanActual - slope * meanRaw;
    // Negative slopes would mean farther objects systematically yield a
    // smaller raw depth, which contradicts this metric checkpoint's semantics.
    if (!slope.isFinite || !intercept.isFinite || slope <= 0) return null;

    return DepthCalibration(slope, intercept);
  }
}
