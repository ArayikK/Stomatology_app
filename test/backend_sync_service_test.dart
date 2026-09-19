import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:stom/data/app_database.dart';
import 'package:stom/data/backend_sync_service.dart';
import 'package:stom/data/dental_repository.dart';

void main() {
  late DentalRepository repository;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    // Test files run in parallel; a private folder keeps this file's
    // database from being locked by another file's.
    await databaseFactory.setDatabasesPath(
      Directory.systemTemp.createTempSync('stom_test_').path,
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final dbPath = p.join(await databaseFactory.getDatabasesPath(), 'stom_dental.db');
    await AppDatabase.instance.close();
    await databaseFactory.deleteDatabase(dbPath);
    repository = DentalRepository(database: AppDatabase.instance);
    await repository.addPatient('Anna', 'Petrosyan');
  });

  test('a failed upload is retried once and then reported as synced', () async {
    var puts = 0;
    final sync = BackendSyncService(
      repository: repository,
      client: MockClient((request) async {
        puts++;
        return http.Response('{}', puts == 1 ? 503 : 200);
      }),
    );

    expect(await sync.pushAll(), isTrue);
    expect(puts, 2);
    expect(sync.status.value.state, SyncState.synced);
    expect(sync.status.value.lastSuccessAt, isNotNull);
  });

  test('an upload that keeps failing is reported as failed', () async {
    final sync = BackendSyncService(
      repository: repository,
      client: MockClient((_) async => http.Response('{}', 500)),
    );

    expect(await sync.pushAll(), isFalse);
    expect(sync.status.value.state, SyncState.failed);
    expect(sync.status.value.lastSuccessAt, isNull);
  });

  test('pushes requested during an upload collapse into one follow-up', () async {
    var puts = 0;
    final sync = BackendSyncService(
      repository: repository,
      client: MockClient((_) async {
        puts++;
        return http.Response('{}', 200);
      }),
    );

    final first = sync.pushAll();
    sync.pushAll();
    sync.pushAll();
    await first;

    expect(puts, 2);
  });

  test('the last backup time survives a restart', () async {
    final client = MockClient((_) async => http.Response('{}', 200));
    await BackendSyncService(repository: repository, client: client).pushAll();

    final restarted = BackendSyncService(repository: repository, client: client);
    await restarted.warmUp();

    expect(restarted.status.value.lastSuccessAt, isNotNull);
  });
}
