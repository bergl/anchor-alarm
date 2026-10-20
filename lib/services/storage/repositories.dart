import '../../app/app_settings.dart';
import '../../domain/models.dart';
import '../../domain/weather.dart';

abstract class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);

  /// Custom (non built-in) profiles.
  Future<List<AlarmProfile>> loadCustomProfiles();
  Future<void> saveCustomProfiles(List<AlarmProfile> profiles);
}

/// Sessions (active and finished) and their tracks.
abstract class SessionRepository {
  /// Inserts or replaces the session.
  Future<void> save(AnchorSession session);

  /// The session with no end time, if any (used to resume after restart).
  Future<AnchorSession?> loadActive();

  /// Finished sessions, newest first.
  Future<List<AnchorSession>> history();
  Future<AnchorSession?> get(String id);
  Future<void> delete(String id);

  Future<void> appendTrack(String sessionId, List<TrackPoint> points);
  Future<List<TrackPoint>> track(String sessionId);
}

/// The last fetched weather forecast, so it can be shown offline.
abstract class WeatherRepository {
  Future<Forecast?> load();
  Future<void> save(Forecast forecast);
}

/// Keeps the forecast in memory only (tests, and when storage is unavailable).
class MemoryWeatherRepository implements WeatherRepository {
  MemoryWeatherRepository([this.forecast]);
  Forecast? forecast;
  int saves = 0;

  @override
  Future<Forecast?> load() async => forecast;

  @override
  Future<void> save(Forecast f) async {
    saves++;
    forecast = f;
  }
}
