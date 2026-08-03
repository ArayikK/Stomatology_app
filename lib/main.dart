import 'package:flutter/material.dart';

import 'data/backend_sync_service.dart';
import 'data/dental_repository.dart';
import 'screens/patient_list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = DentalRepository();
  await repository.seedSampleDataIfEmpty();
  final syncService = BackendSyncService(repository: repository);
  runApp(StomApp(repository: repository, syncService: syncService));
}

class StomApp extends StatelessWidget {
  factory StomApp({Key? key, DentalRepository? repository, BackendSyncService? syncService}) {
    final resolvedRepository = repository ?? DentalRepository();
    return StomApp._(
      key: key,
      repository: resolvedRepository,
      syncService: syncService ?? BackendSyncService(repository: resolvedRepository),
    );
  }

  const StomApp._({super.key, required this.repository, required this.syncService});

  final DentalRepository repository;
  final BackendSyncService syncService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stom',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: PatientListScreen(repository: repository, syncService: syncService),
    );
  }
}
