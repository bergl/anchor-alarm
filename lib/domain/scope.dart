import 'dart:math' as math;

/// Typical height of the bow roller above the water, metres. Scope is
/// measured from the roller, so it is added to the depth.
const double defaultBowHeightM = 1.0;

enum ScopeRating {
  /// Rode does not even reach the bottom.
  tooShort,

  /// Below 3:1 — likely to drag.
  short,

  /// 3:1 to 5:1 — acceptable for all-chain in settled weather.
  fair,

  /// 5:1 or more.
  good,
}

class ScopeAdvice {
  const ScopeAdvice({
    required this.ratio,
    required this.rating,
    required this.rodeFor3M,
    required this.rodeFor5M,
  });

  /// Rode ÷ (depth + bow height).
  final double ratio;
  final ScopeRating rating;

  /// Rode needed for 3:1 and 5:1 scope, metres.
  final double rodeFor3M;
  final double rodeFor5M;
}

ScopeAdvice scopeAdvice({
  required double rodeM,
  required double depthM,
  double bowHeightM = defaultBowHeightM,
}) {
  final vertical = math.max(0.1, depthM + bowHeightM);
  final ratio = rodeM / vertical;
  final rating = rodeM <= vertical
      ? ScopeRating.tooShort
      : ratio < 3
          ? ScopeRating.short
          : ratio < 5
              ? ScopeRating.fair
              : ScopeRating.good;
  return ScopeAdvice(
    ratio: ratio,
    rating: rating,
    rodeFor3M: vertical * 3,
    rodeFor5M: vertical * 5,
  );
}
