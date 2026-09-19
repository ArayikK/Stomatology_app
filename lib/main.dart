import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'data/backend_sync_service.dart';
import 'data/dental_repository.dart';
import 'data/sample_xray.dart';
import 'screens/home_screen.dart';
import 'tour/app_tour.dart';
import 'tour/intro_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = DentalRepository();
  await repository.seedSampleDataIfEmpty();
  await seedSampleXrayIfMissing(repository);
  final syncService = BackendSyncService(repository: repository);
  unawaited(syncService.warmUp());
  final showIntro = !await AppTour.introSeen();
  runApp(
    StomApp(
      repository: repository,
      syncService: syncService,
      showIntro: showIntro,
    ),
  );
}

class StomApp extends StatelessWidget {
  factory StomApp({
    Key? key,
    DentalRepository? repository,
    BackendSyncService? syncService,
    bool showIntro = false,
  }) {
    final resolvedRepository = repository ?? DentalRepository();
    return StomApp._(
      key: key,
      repository: resolvedRepository,
      syncService:
          syncService ?? BackendSyncService(repository: resolvedRepository),
      showIntro: showIntro,
    );
  }

  const StomApp._({
    super.key,
    required this.repository,
    required this.syncService,
    required this.showIntro,
  });

  final DentalRepository repository;
  final BackendSyncService syncService;

  /// First launch: open on the welcome page instead of the dashboard.
  final bool showIntro;

  Widget _home() =>
      HomeScreen(repository: repository, syncService: syncService);

  Future<void> _leaveIntro(
    BuildContext context, {
    required bool takeTour,
  }) async {
    await AppTour.completeIntro(takeTour: takeTour);
    if (!context.mounted) return;
    await Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, _, _) => _home(),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stom',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kStomSeedColor),
      ),
      home: showIntro
          ? Builder(
              builder: (context) => IntroScreen(
                onTakeTour: () => _leaveIntro(context, takeTour: true),
                onSkip: () => _leaveIntro(context, takeTour: false),
              ),
            )
          : _home(),
    );
  }
}
