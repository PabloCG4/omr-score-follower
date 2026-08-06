import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../domain/persisted_score_document.dart';
import '../score/score_library_controller.dart';

/// Full-screen / modal score library: Import PDF, Pending, and Ready lists.
///
/// Selecting a Ready score (or the bundled demo) persists [UserPreferences.scoreId]
/// via [ScoreLibraryController] and pops with the chosen preference id.
class ScoreLibraryModal extends StatefulWidget {
  const ScoreLibraryModal({super.key});

  /// Opens the library as a modal bottom sheet / dialog route.
  static Future<void> open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final sheetHeight = MediaQuery.sizeOf(sheetContext).height * 0.92;
        return SizedBox(
          height: sheetHeight,
          child: const ScoreLibraryModal(),
        );
      },
    );
  }

  @override
  State<ScoreLibraryModal> createState() => ScoreLibraryModalState();
}

class ScoreLibraryModalState extends State<ScoreLibraryModal> {
  ScoreLibraryController? libraryController;
  bool isPickingFile = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    libraryController ??= ScoreLibraryScope.of(context);
  }

  Future<void> importPdf() async {
    if (isPickingFile) {
      return;
    }
    setState(() {
      isPickingFile = true;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['pdf'],
        withData: false,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final pickedPath = result.files.single.path;
      if (pickedPath == null || pickedPath.isEmpty) {
        if (!mounted) {
          return;
        }
        await showScoreImportErrorDialog(
          context,
          'Could not access the selected PDF path on this platform.',
        );
        return;
      }

      if (!mounted) {
        return;
      }
      final controller = ScoreLibraryScope.of(context);
      // Non-blocking: pending row appears immediately; sheet stays usable.
      unawaited(runImportAndSurfaceErrors(controller, File(pickedPath)));
    } finally {
      if (mounted) {
        setState(() {
          isPickingFile = false;
        });
      }
    }
  }

  Future<void> runImportAndSurfaceErrors(
    ScoreLibraryController controller,
    File pdfFile,
  ) async {
    await controller.enqueuePdfImport(pdfFile);
    if (!mounted) {
      return;
    }
    final errorMessage = controller.lastUserFacingError;
    if (errorMessage == null) {
      return;
    }
    controller.clearLastUserFacingError();
    if (errorMessage.length > 160) {
      await showScoreImportErrorDialog(context, errorMessage);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  Future<void> onSelectDemo(ScoreLibraryController controller) async {
    await controller.selectDemoScore();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> onSelectReady(
    ScoreLibraryController controller,
    PersistedScoreDocument document,
  ) async {
    await controller.selectPersistedScore(document);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ScoreLibraryScope.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Score library'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Import a PDF to process it with the OMR service. '
                  'Tracking still uses the bundled demo until a later phase '
                  'loads ingested packs.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  onPressed: isPickingFile ? null : importPdf,
                  icon: isPickingFile
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(
                    isPickingFile ? 'Opening picker…' : 'Import PDF',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<List<PersistedScoreDocument>>(
                  stream: controller.watchReadyScores(),
                  builder: (context, snapshot) {
                    final readyScores =
                        snapshot.data ?? const <PersistedScoreDocument>[];
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          'Bundled',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        buildDemoTile(controller),
                        if (controller.pendingIngestions.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text(
                            'Processing',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          for (final pending in controller.pendingIngestions)
                            buildPendingTile(pending),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          'Ready',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (snapshot.connectionState == ConnectionState.waiting &&
                            !snapshot.hasData)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (readyScores.isEmpty)
                          Text(
                            'No imported scores yet. Use Import PDF to add one.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          )
                        else
                          for (final document in readyScores)
                            buildReadyTile(controller, document),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildDemoTile(ScoreLibraryController controller) {
    final isSelected =
        ScoreLibraryController.isDemoScoreId(controller.selectedScoreId);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.library_music_outlined),
        title: const Text('Demo: C - G - Am - F'),
        subtitle: const Text('Bundled pack — currently trackable'),
        trailing: isSelected
            ? const Icon(Icons.check_circle)
            : const Chip(label: Text('Ready')),
        selected: isSelected,
        onTap: controller.isBusySelecting
            ? null
            : () => onSelectDemo(controller),
      ),
    );
  }

  Widget buildPendingTile(PendingScoreIngestion pending) {
    return Card(
      child: ListTile(
        leading: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text(pending.displayTitle),
        subtitle: const Text('Processing via AI…'),
        trailing: Chip(
          avatar: Icon(
            Icons.auto_awesome,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          label: const Text('Processing'),
        ),
      ),
    );
  }

  Widget buildReadyTile(
    ScoreLibraryController controller,
    PersistedScoreDocument document,
  ) {
    final preferenceId =
        ScoreLibraryController.preferenceIdForPersistedDocument(document.id);
    final isSelected = controller.selectedScoreId == preferenceId;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf_outlined),
        title: Text(document.title),
        subtitle: const Text(
          'Ingested — Ready (tracking loader in a later phase)',
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle)
            : const Chip(label: Text('Ready')),
        selected: isSelected,
        onTap: controller.isBusySelecting
            ? null
            : () => onSelectReady(controller, document),
      ),
    );
  }
}

Future<void> showScoreImportErrorDialog(
  BuildContext context,
  String message,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Import failed'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
