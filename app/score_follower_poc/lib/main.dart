// Phase 5.2 entry point: thin shell around FollowingSessionController and
// ScoreViewport. Engine lifecycle, timeline mapping, and cursor interpolation
// live in lib/session and lib/score; this file only wires the widget tree.
import 'package:flutter/material.dart';

import 'session/alignment_snapshot.dart';
import 'session/cursor_display_model.dart';
import 'session/following_session_controller.dart';
import 'ui/score_viewport.dart';

void main() {
  runApp(const ScoreFollowerPocApp());
}

class ScoreFollowerPocApp extends StatelessWidget {
  const ScoreFollowerPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Score Follower PoC',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const ScoreFollowerHomePage(),
    );
  }
}

class ScoreFollowerHomePage extends StatefulWidget {
  const ScoreFollowerHomePage({super.key});

  @override
  State<ScoreFollowerHomePage> createState() => ScoreFollowerHomePageState();
}

class ScoreFollowerHomePageState extends State<ScoreFollowerHomePage>
    with SingleTickerProviderStateMixin {
  late final CursorDisplayModel cursorDisplayModel;
  late final FollowingSessionController sessionController;
  bool showFrameScrubber = false;

  @override
  void initState() {
    super.initState();
    cursorDisplayModel = CursorDisplayModel(tickerProvider: this);
    sessionController = FollowingSessionController(
      cursorDisplayModel: cursorDisplayModel,
    );
    sessionController.loadScore();
  }

  @override
  void dispose() {
    sessionController.dispose();
    cursorDisplayModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sessionController,
      builder: (context, child) {
        final document = sessionController.scoreDocument;
        final maxFrame = document == null
            ? 0.0
            : document.anchors.last.frameIndex.toDouble();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Score Follower PoC'),
            actions: [
              IconButton(
                tooltip: 'Toggle frame scrubber',
                onPressed: () {
                  setState(() {
                    showFrameScrubber = !showFrameScrubber;
                  });
                },
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ScoreViewport(
                    sessionController: sessionController,
                    cursorDisplayModel: cursorDisplayModel,
                  ),
                ),
              ),
              if (showFrameScrubber && document != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    children: [
                      const Text('Scrub'),
                      Expanded(
                        child: Slider(
                          min: 0.0,
                          max: maxFrame,
                          value: cursorDisplayModel.targetFrameIndex
                              .clamp(0.0, maxFrame)
                              .toDouble(),
                          onChanged: sessionController.isRunning
                              ? null
                              : (value) {
                                  sessionController.scrubToFrameIndex(value);
                                  setState(() {});
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 8.0),
                child: ValueListenableBuilder<AlignmentSnapshot>(
                  valueListenable: sessionController.alignmentSnapshot,
                  builder: (context, snapshot, child) {
                    return Text(
                      'frame=${snapshot.referenceFrameIndex.toStringAsFixed(2)}  '
                      'conf=${snapshot.alignmentConfidence.toStringAsFixed(3)}  '
                      'cost=${snapshot.cumulativeDistortionCost.toStringAsFixed(3)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    );
                  },
                ),
              ),
              if (sessionController.lastErrorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    sessionController.lastErrorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0, top: 8.0),
                child: ElevatedButton(
                  onPressed: sessionController.isLoadingScore
                      ? null
                      : () {
                          if (sessionController.isRunning) {
                            sessionController.stop();
                          } else {
                            sessionController.start();
                          }
                        },
                  child: Text(
                    sessionController.isRunning
                        ? 'Stop'
                        : (sessionController.isLoadingScore ? 'Loading…' : 'Start'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
