import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../domain/geo.dart';
import '../domain/weather.dart';
import '../domain/weather_risk.dart';
import '../services/weather/weather_service.dart';
import 'app_settings.dart';
import 'providers.dart';
import 'watch_controller.dart';

/// Forecast shown in the app, its analysis and the fetch status.
class WeatherState {
  const WeatherState({
    this.forecast,
    this.risk,
    this.loading = false,
    this.error,
    this.lastAttempt,
  });

  /// Last good forecast (fresh or from the cache).
  final Forecast? forecast;

  /// [forecast] analysed with the current thresholds.
  final WeatherRisk? risk;
  final bool loading;

  /// Why the last fetch failed (null after a successful one).
  final String? error;
  final DateTime? lastAttempt;

  bool get hasAlerts => risk?.hasAlerts ?? false;

  /// The forecast is older than the refresh interval.
  bool isStale(DateTime now) =>
      forecast != null && forecast!.age(now) >= WeatherController.refreshEvery;

  WeatherState copyWith({
    Forecast? forecast,
    WeatherRisk? risk,
    bool? loading,
    String? error,
    bool clearError = false,
    DateTime? lastAttempt,
  }) =>
      WeatherState(
        forecast: forecast ?? this.forecast,
        risk: risk ?? this.risk,
        loading: loading ?? this.loading,
        error: clearError ? null : error ?? this.error,
        lastAttempt: lastAttempt ?? this.lastAttempt,
      );
}

/// Thresholds as set in the settings.
WeatherThresholds weatherThresholds(AppSettings s) => WeatherThresholds(
      gustWarnKn: s.gustWarnKn,
      windWarnKn: s.windWarnKn,
      waveWarnM: s.waveWarnM,
    );

final weatherControllerProvider =
    NotifierProvider<WeatherController, WeatherState>(WeatherController.new);

/// Keeps the forecast up to date and turns forecast alerts into
/// notifications.
///
/// * While watching: fetches for the anchor when the watch starts, then every
///   [refreshEvery] (retrying failures every [retryEvery]) and on app resume.
/// * Otherwise: fetches for the boat when the weather is looked at
///   ([ensureFresh], e.g. opening the weather sheet).
/// * The last forecast is cached, so offline the app shows it with its age.
/// * Forecast alerts are informational notifications ([notifyLead] before the
///   event, or at once when closer), each at most once — they never sound the
///   anchor alarm. Failures never reach the anchor watch.
class WeatherController extends Notifier<WeatherState> {
  static const refreshEvery = Duration(hours: 3);
  static const retryEvery = Duration(minutes: 30);
  static const tickEvery = Duration(minutes: 15);
  static const notifyLead = Duration(hours: 2);

  /// Alerts of the same kind closer than this are the same event (the
  /// forecast moves a little between updates).
  static const sameEvent = Duration(hours: 3);

  /// Forecasts older than this do not raise notifications any more.
  static const maxAlertAge = Duration(hours: 12);

  /// Fetch again when the forecast is for a place this far away.
  static const maxDistanceM = 5000.0;

  Timer? _timer;
  String? _watchId;
  bool _cacheLoaded = false;
  int _seq = 0;
  final List<WeatherAlert> _notified = [];

  @override
  WeatherState build() {
    ref.listen<String?>(watchControllerProvider.select((s) => s.session?.id), (prev, next) {
      _guard('watch listener', () {
        if (next != null && next != _watchId) {
          _onWatchStarted(next);
        } else if (next == null && _watchId != null) {
          _onWatchStopped();
        }
      });
    });
    ref.listen(
      settingsProvider.select((s) => (s.gustWarnKn, s.windWarnKn, s.waveWarnM, s.weatherAlerts)),
      (_, _) => _guard('settings', () {
        _recompute();
        _checkAlerts();
      }),
    );
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(_init);
    return const WeatherState();
  }

  DateTime _now() => clock.now();

  Future<void> _init() async {
    await _loadCache();
    if (!ref.mounted) return;
    final id = ref.read(watchControllerProvider).session?.id;
    if (id != null && _watchId == null) _onWatchStarted(id);
  }

  Future<void> _loadCache() async {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final cached = await ref.read(weatherRepositoryProvider).load();
      if (!ref.mounted || cached == null || state.forecast != null) return;
      state = state.copyWith(forecast: cached);
      _recompute();
    } catch (e, st) {
      _log('cache load', e, st);
    }
  }

  bool get _watching => ref.read(watchControllerProvider).watching;

  void _onWatchStarted(String id) {
    _watchId = id;
    _notified.clear();
    _timer?.cancel();
    _timer = Timer.periodic(tickEvery, (_) => _guard('tick', _onTick));
    unawaited(refresh());
  }

  void _onWatchStopped() {
    _watchId = null;
    _timer?.cancel();
    _timer = null;
    _notified.clear();
  }

  LatLng? _position() {
    final w = ref.read(watchControllerProvider);
    return w.session?.anchor ?? w.snapshot?.position ?? w.fix?.position;
  }

  bool _needsFetch(LatLng pos, Duration maxAge) {
    final f = state.forecast;
    if (f == null) return true;
    if (f.age(_now()) >= maxAge) return true;
    return distanceM(f.location, pos) > maxDistanceM;
  }

  bool get _mayRetry {
    final last = state.lastAttempt;
    return state.error == null || last == null || _now().difference(last) >= retryEvery;
  }

  void _onTick() {
    _recompute();
    if (_watching && !state.loading) {
      final pos = _position();
      if (pos != null && _needsFetch(pos, refreshEvery) && _mayRetry) {
        unawaited(refresh());
        return; // refresh() checks the alerts when done.
      }
    }
    _checkAlerts();
  }

  /// App came back to the foreground: refresh when due.
  void onAppResumed() {
    if (!_watching) return;
    _guard('resume', _onTick);
  }

  /// Fetches when the forecast is missing, older than [maxAge] or for another
  /// place (opening the weather sheet, the drop-anchor panel).
  Future<void> ensureFresh({Duration maxAge = const Duration(hours: 1)}) async {
    await _loadCache();
    if (!ref.mounted || state.loading) return;
    final pos = _position();
    if (pos == null) return;
    final last = state.lastAttempt;
    // After a failure, do not hammer the server from the UI.
    if (state.error != null &&
        last != null &&
        _now().difference(last) < const Duration(minutes: 5)) {
      return;
    }
    if (_needsFetch(pos, maxAge)) await refresh();
  }

  /// Fetches the forecast now: for the anchor while watching, otherwise for
  /// the boat (or [at]).
  Future<void> refresh({LatLng? at}) async {
    final pos = at ?? _position();
    if (pos == null) {
      state = state.copyWith(error: 'No position yet');
      return;
    }
    final seq = ++_seq;
    state = state.copyWith(loading: true, lastAttempt: _now());
    WeatherResult result;
    try {
      result = await ref.read(weatherServiceProvider).fetch(pos);
    } catch (e) {
      result = WeatherError('$e');
    }
    if (!ref.mounted || seq != _seq) return;
    switch (result) {
      case WeatherOk(:final forecast):
        state = state.copyWith(forecast: forecast, loading: false, clearError: true);
        _recompute();
        try {
          await ref.read(weatherRepositoryProvider).save(forecast);
        } catch (e, st) {
          _log('cache save', e, st);
        }
      case WeatherError(:final message):
        state = state.copyWith(loading: false, error: message);
    }
    if (ref.mounted) _guard('alerts', _checkAlerts);
  }

  void _recompute() {
    final f = state.forecast;
    if (f == null) return;
    state = state.copyWith(
      risk: analyzeWeather(f, _now(),
          thresholds: weatherThresholds(ref.read(settingsProvider))),
    );
  }

  bool _alreadyNotified(WeatherAlert a) => _notified.any((n) =>
      n.kind == a.kind &&
      n.time.difference(a.time).abs() < sameEvent &&
      a.value < n.value + _escalation(a.kind));

  /// How much worse an already notified alert must get to notify again.
  static double _escalation(WeatherAlertKind k) => switch (k) {
        WeatherAlertKind.strongGusts || WeatherAlertKind.strongWind => 8,
        WeatherAlertKind.highWaves => 1,
        WeatherAlertKind.pressureDrop => 3,
        WeatherAlertKind.windShift => double.infinity,
      };

  void _checkAlerts() {
    if (!_watching || !ref.read(settingsProvider).weatherAlerts) return;
    final f = state.forecast;
    final risk = state.risk;
    if (f == null || risk == null || f.age(_now()) > maxAlertAge) return;
    final now = _now();
    final due = [
      for (final a in risk.alerts)
        if (!now.isBefore(a.time.subtract(notifyLead)) && !_alreadyNotified(a)) a,
    ];
    if (due.isEmpty) return;
    _notified.addAll(due);
    final title = due.length == 1 ? weatherAlertTitle(due.single.kind) : 'Weather alerts';
    unawaited(ref
        .read(notificationServiceProvider)
        .showInfo(title: title, body: due.map((a) => a.message).join('\n'))
        .catchError((Object e) => _log('notify', e, StackTrace.current)));
  }

  void _guard(String what, void Function() f) {
    try {
      f();
    } catch (e, st) {
      _log(what, e, st);
    }
  }

  void _log(String what, Object e, StackTrace st) =>
      debugPrint('WeatherController $what failed: $e\n$st');
}

String weatherAlertTitle(WeatherAlertKind k) => switch (k) {
      WeatherAlertKind.strongGusts => 'Strong gusts forecast',
      WeatherAlertKind.strongWind => 'Strong wind forecast',
      WeatherAlertKind.windShift => 'Wind shift forecast',
      WeatherAlertKind.highWaves => 'High waves forecast',
      WeatherAlertKind.pressureDrop => 'Pressure falling fast',
    };
