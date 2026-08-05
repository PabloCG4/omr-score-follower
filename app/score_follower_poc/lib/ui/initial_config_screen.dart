import 'package:flutter/material.dart';

import '../config/tracking_mode.dart';
import '../config/tracking_session_config.dart';
import 'tracking_screen.dart';

/// App entry point: select a [TrackingMode] and proceed to the score.
class InitialConfigScreen extends StatefulWidget {
  const InitialConfigScreen({super.key});

  @override
  State<InitialConfigScreen> createState() => InitialConfigScreenState();
}

class InitialConfigScreenState extends State<InitialConfigScreen> {
  TrackingMode selectedMode = TrackingMode.rubato;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Score Follower')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Practice mode',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how the cursor should follow your performance.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              SegmentedButton<TrackingMode>(
                segments: [
                  for (final mode in TrackingMode.values)
                    ButtonSegment<TrackingMode>(
                      value: mode,
                      label: Text(mode.displayLabel),
                    ),
                ],
                selected: {selectedMode},
                onSelectionChanged: (selection) {
                  setState(() {
                    selectedMode = selection.first;
                  });
                },
              ),
              const SizedBox(height: 16),
              Text(
                selectedMode.description,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  final config = TrackingSessionConfig(trackingMode: selectedMode);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => TrackingScreen(config: config),
                    ),
                  );
                },
                child: const Text('Proceed to Score'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
