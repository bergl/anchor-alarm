import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// Opens [name] as a sembast file in the application documents directory.
Future<Database> openPlatformDatabase(String name) async {
  final dir = await getApplicationDocumentsDirectory();
  return databaseFactoryIo.openDatabase(p.join(dir.path, name));
}
