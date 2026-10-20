import 'package:sembast_web/sembast_web.dart';

/// Opens [name] as an IndexedDB-backed sembast database.
Future<Database> openPlatformDatabase(String name) =>
    databaseFactoryWeb.openDatabase(name);
