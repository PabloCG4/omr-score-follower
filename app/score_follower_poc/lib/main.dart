// Phase 5.4 entry point: InitialConfigScreen routes into TrackingScreen
// with a typed TrackingSessionConfig (practice mode + thresholds).
import 'package:flutter/material.dart';

import 'ui/initial_config_screen.dart';

void main() {
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
