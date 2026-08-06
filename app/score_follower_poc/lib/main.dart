// Phase 5.5.1 entry: open local SQLite, seed defaults, then show config UI.
import 'package:flutter/material.dart';

import 'persistence/app_database_provider.dart';
import 'ui/initial_config_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabaseProvider.initialize();
  runApp(const ScoreFollowerPocApp());
}

class ScoreFollowerPocApp extends StatelessWidget {
  const ScoreFollowerPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Score Follower',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const InitialConfigScreen(),
    );
  }
}
