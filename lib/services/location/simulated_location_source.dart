import 'dart:async';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../domain/geo.dart';
import '../../domain/models.dart';
import '../heading/heading_source.dart';
import 'location_source.dart';

/// Behaviours the simulator can play out.
enum SimScenario {
  /// Boat lies to its anchor, swinging gently with the wind.
  swing,

  /// Like [swing] but the anchor drags downwind at about 0.4 m/s.
  drag,

  /// Normal swing with occasional single-fix GPS jumps of 30–60 m.
  glitches,

  /// Accuracy degrades to about 40 m.
  poorGps,

  /// No fixes at all.
  gpsLoss,
}

/// A fake boat at anchor for demos, web testing and development.
///
/// Model: a virtual anchor at [anchor]; wind from [windFromDeg] which veers
/// ±25° over a 4-minute cycle; the boat lies downwind at [rodeM] plus noise.
/// The bow points into the wind, which is also emitted as the compass heading.
class SimulatedLocationSource implements LocationSource, HeadingSource {
  SimulatedLocationSource({
    LatLng? anchor,
    this.rodeM = 25,
    this.windFromDeg = 0,
    this.interval = const Duration(seconds: 1),
    math.Random? random,
  })  : anchor = anchor ?? defaultAnchor,
        _rnd = random ?? math.Random();

  /// Palmižana bay, Pakleni islands, Croatia.
  static const defaultAnchor = LatLng(43.16330, 16.39720);

  LatLng anchor;
  double rodeM;
  double windFromDeg;
  final Duration interval;
  final math.Random _rnd;

  SimScenario _scenario = SimScenario.swing;
  DateTime? _dragStart;
  double _bowDeg = 0;
  final _headingCtrl = StreamController<double?>.broadcast();

  SimScenario get scenario => _scenario;
  set scenario(SimScenario s) {
    if (s == SimScenario.drag && _scenario != SimScenario.drag) {
      _dragStart = DateTime.now();
    }
    if (s != SimScenario.drag) _dragStart = null;
    _scenario = s;
  }

  /// Puts the simulated anchor (and boat) somewhere else.
  void relocate(LatLng newAnchor) {
    anchor = newAnchor;
    _dragStart = _scenario == SimScenario.drag ? DateTime.now() : null;
  }

  @override
  String get label => 'Simulator';

  @override
  Future<LocationPermissionResult> requestPermission({bool background = false}) async =>
      LocationPermissionResult.always;

  @override
  Stream<PositionFix> watch({bool background = false}) {
    late StreamController<PositionFix> ctrl;
    Timer? timer;
    ctrl = StreamController<PositionFix>(
      onListen: () {
        void emit() {
          final f = _fix(DateTime.now());
          if (f != null) ctrl.add(f);
        }

        emit();
        timer = Timer.periodic(interval, (_) => emit());
      },
      onCancel: () => timer?.cancel(),
    );
    return ctrl.stream;
  }

  @override
  Future<PositionFix?> currentFix() async =>
      _fix(DateTime.now()) ?? _fix(DateTime.now(), ignoreLoss: true);

  @override
  Future<bool> get available async => true;

  @override
  Stream<double?> get heading async* {
    yield _bowDeg;
    yield* _headingCtrl.stream;
  }

  /// Position the simulated boat would have at [t] (no noise), for tests.
  LatLng boatAt(DateTime t) => _boat(t).$1;

  (LatLng, double) _boat(DateTime t) {
    final secs = t.millisecondsSinceEpoch / 1000.0;
    final wind = windFromDeg + 25 * math.sin(2 * math.pi * secs / 240);
    var a = anchor;
    if (_scenario == SimScenario.drag && _dragStart != null) {
      final dragged = 0.4 * t.difference(_dragStart!).inMilliseconds / 1000.0;
      a = destination(anchor, windFromDeg + 180, dragged);
    }
    final lie = rodeM + 2 * math.sin(2 * math.pi * secs / 37);
    return (destination(a, wind + 180, lie), normalizeDeg(wind));
  }

  PositionFix? _fix(DateTime t, {bool ignoreLoss = false}) {
    if (_scenario == SimScenario.gpsLoss && !ignoreLoss) return null;
    final (boat, bow) = _boat(t);
    _bowDeg = bow;
    _headingCtrl.add(bow);

    var acc = 3 + _rnd.nextDouble() * 3;
    if (_scenario == SimScenario.poorGps) acc = 35 + _rnd.nextDouble() * 15;
    var p = destination(boat, _rnd.nextDouble() * 360, _gauss() * acc * 0.5);
    if (_scenario == SimScenario.glitches && _rnd.nextDouble() < 0.03) {
      p = destination(p, _rnd.nextDouble() * 360, 30 + _rnd.nextDouble() * 30);
    }
    return PositionFix(
      position: p,
      accuracyM: acc,
      time: t,
      speedMps: 0.1,
      source: FixSource.simulated,
    );
  }

  double _gauss() {
    final u = 1 - _rnd.nextDouble();
    final v = _rnd.nextDouble();
    return (math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v)).abs();
  }
}
