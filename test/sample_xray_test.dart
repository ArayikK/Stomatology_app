import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:stom/data/app_database.dart';
import 'package:stom/data/dental_repository.dart';
import 'package:stom/data/sample_xray.dart';

/// path_provider has no desktop-test implementation, so the documents
/// directory is answered from a temp folder.
void _mockDocumentsDirectory(Directory dir) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async =>
        call.method == 'getApplicationDocumentsDirectory' ? dir.path : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;
  late DentalRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await databaseFactory.setDatabasesPath(
      Directory.systemTemp.createTempSync('stom_xray_test_').path,
    );
  });

  setUp(() async {
    final dbPath = p.join(
      await databaseFactory.getDatabasesPath(),
      'stom_dental.db',
    );
    await AppDatabase.instance.close();
    await databaseFactory.deleteDatabase(dbPath);
    repository = DentalRepository(database: AppDatabase.instance);
    docsDir = Directory.systemTemp.createTempSync('stom_xray_docs_');
    _mockDocumentsDirectory(docsDir);
  });

  tearDown(() {
    if (docsDir.existsSync()) docsDir.deleteSync(recursive: true);
  });

  test('the bundled x-ray lands on the sample patient on first launch', () async {
    await repository.seedSampleDataIfEmpty();
    await seedSampleXrayIfMissing(repository);

    final anna = (await repository.getPatients()).firstWhere(
      (patient) => patient.firstName == 'Anna',
    );
    final images = await repository.getImages(anna.id!, 14);
    expect(images, hasLength(1));

    final image = images.single;
    expect(File(image.filePath).existsSync(), isTrue);
    expect(File(image.filePath).lengthSync(), greaterThan(0));
    expect(image.originalDicomPath, isNotNull);
    expect(File(image.originalDicomPath!).existsSync(), isTrue);
    expect(p.extension(image.filePath), '.png');
  });

  test('a second launch does not import it again', () async {
    await repository.seedSampleDataIfEmpty();
    await seedSampleXrayIfMissing(repository);
    await seedSampleXrayIfMissing(repository);

    final anna = (await repository.getPatients()).firstWhere(
      (patient) => patient.firstName == 'Anna',
    );
    expect(await repository.getImages(anna.id!, 14), hasLength(1));
  });
}
