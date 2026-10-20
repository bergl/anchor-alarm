import '../../app/app_settings.dart';
import '../../domain/models.dart';

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
