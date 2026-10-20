import 'package:anchor_alarm/domain/scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('30 m of rode in 13.4 m is short scope', () {
    final a = scopeAdvice(rodeM: 30, depthM: 13.4);
    expect(a.ratio, closeTo(30 / 14.4, 1e-9));
    expect(a.rating, ScopeRating.short);
    expect(a.rodeFor3M, closeTo(43.2, 1e-9));
    expect(a.rodeFor5M, closeTo(72, 1e-9));
  });

  test('ratings at the boundaries', () {
    expect(scopeAdvice(rodeM: 5, depthM: 5).rating, ScopeRating.tooShort);
    expect(scopeAdvice(rodeM: 6, depthM: 5).rating, ScopeRating.tooShort);
    expect(scopeAdvice(rodeM: 17.9, depthM: 5).rating, ScopeRating.short);
    expect(scopeAdvice(rodeM: 18, depthM: 5).rating, ScopeRating.fair);
    expect(scopeAdvice(rodeM: 29.9, depthM: 5).rating, ScopeRating.fair);
    expect(scopeAdvice(rodeM: 30, depthM: 5).rating, ScopeRating.good);
  });

  test('bow height is configurable and zero depth is safe', () {
    expect(scopeAdvice(rodeM: 15, depthM: 5, bowHeightM: 0).rating, ScopeRating.fair);
    expect(scopeAdvice(rodeM: 10, depthM: 0).ratio, closeTo(10, 1e-9));
  });
}
