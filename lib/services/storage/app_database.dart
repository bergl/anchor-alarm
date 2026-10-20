import 'package:sembast/sembast_memory.dart';

import 'database_factory_io.dart'
    if (dart.library.js_interop) 'database_factory_web.dart';
import 'repositories.dart';
import 'sembast_repositories.dart';

/// The app's local database and the repositories built on it.
class AppDatabase {
  AppDatabase(this.db)
      : settings = SembastSettingsRepository(db),
        sessions = SembastSessionRepository(db);

  final Database db;
  final SettingsRepository settings;
  final SessionRepository sessions;

  Future<void> close() => db.close();
}

/// Database file name (mobile) / IndexedDB name (web).
const appDatabaseName = 'anchor_alarm.db';

/// Opens the app database: a sembast file in the application documents
/// directory on mobile, IndexedDB on the web, or a fresh in-memory database
/// when [inMemory] is true (tests).
Future<AppDatabase> openAppDatabase({bool inMemory = false}) async {
  final db = inMemory
      ? await newDatabaseFactoryMemory().openDatabase(appDatabaseName)
      : await openPlatformDatabase(appDatabaseName);
  return AppDatabase(db);
}
