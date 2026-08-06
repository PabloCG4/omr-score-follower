import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/tracking_mode.dart';
import '../config/tracking_session_config.dart';
import '../domain/instrument.dart';
import '../domain/user_preferences.dart';
import '../persistence/app_database_provider.dart';
import '../persistence/repositories/instrument_repository.dart';
import '../persistence/repositories/user_preferences_repository.dart';
import 'tracking_screen.dart';

/// App entry point: restore practice mode + instrument from local SQLite,
/// edit configuration, and proceed to the score.
class InitialConfigScreen extends StatefulWidget {
  const InitialConfigScreen({super.key});

  @override
  State<InitialConfigScreen> createState() => InitialConfigScreenState();
}

class InitialConfigScreenState extends State<InitialConfigScreen> {
  late final InstrumentRepository instrumentRepository;
  late final UserPreferencesRepository preferencesRepository;

  TrackingMode selectedMode = TrackingMode.rubato;
  List<Instrument> instruments = const [];
  Instrument? selectedInstrument;
  bool isLoading = true;
  bool isSaving = false;
  String? errorMessage;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController frequencyController = TextEditingController();
  final TextEditingController transpositionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final database = AppDatabaseProvider.requireDatabase;
    instrumentRepository = InstrumentRepository(database);
    preferencesRepository = UserPreferencesRepository(database);
    loadInitialState();
  }

  @override
  void dispose() {
    nameController.dispose();
    frequencyController.dispose();
    transpositionController.dispose();
    super.dispose();
  }

  Future<void> loadInitialState() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final preferences = await preferencesRepository.loadOrCreateDefaults();
      final loadedInstruments = await instrumentRepository.listAll();
      final active = loadedInstruments
          .where((instrument) => instrument.id == preferences.activeInstrumentId)
          .firstOrNull;
      final resolvedActive = active ??
          (loadedInstruments.isEmpty ? null : loadedInstruments.first);

      if (!mounted) {
        return;
      }
      setState(() {
        selectedMode = preferences.trackingMode;
        instruments = loadedInstruments;
        selectedInstrument = resolvedActive;
        isLoading = false;
      });
      populateInstrumentFields(resolvedActive);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isLoading = false;
        errorMessage = error.toString();
      });
    }
  }

  void populateInstrumentFields(Instrument? instrument) {
    if (instrument == null) {
      nameController.text = '';
      frequencyController.text = '440.0';
      transpositionController.text = '0';
      return;
    }
    nameController.text = instrument.name;
    frequencyController.text = instrument.baseFrequencyHz.toString();
    transpositionController.text = instrument.transpositionSemitones.toString();
  }

  Future<void> saveInstrumentEdits() async {
    final current = selectedInstrument;
    if (current == null) {
      return;
    }
    final parsedFrequency = double.tryParse(frequencyController.text.trim());
    final parsedTransposition = int.tryParse(transpositionController.text.trim());
    final trimmedName = nameController.text.trim();
    if (trimmedName.isEmpty || parsedFrequency == null || parsedFrequency <= 0 ||
        parsedTransposition == null) {
      setState(() {
        errorMessage =
            'Enter a non-empty name, a positive A4 frequency (Hz), and an integer transposition.';
      });
      return;
    }

    setState(() {
      isSaving = true;
      errorMessage = null;
    });
    try {
      final updated = await instrumentRepository.upsert(
        current.copyWith(
          name: trimmedName,
          baseFrequencyHz: parsedFrequency,
          transpositionSemitones: parsedTransposition,
        ),
      );
      final preferences = UserPreferences(
        trackingMode: selectedMode,
        activeInstrumentId: updated.id,
      );
      await preferencesRepository.save(preferences);
      final refreshed = await instrumentRepository.listAll();
      if (!mounted) {
        return;
      }
      setState(() {
        instruments = refreshed;
        selectedInstrument = updated;
        isSaving = false;
      });
      populateInstrumentFields(updated);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSaving = false;
        errorMessage = error.toString();
      });
    }
  }

  Future<void> createInstrument() async {
    setState(() {
      isSaving = true;
      errorMessage = null;
    });
    try {
      final created = await instrumentRepository.upsert(
        const Instrument(
          id: 0,
          name: 'New instrument',
          baseFrequencyHz: 440.0,
          transpositionSemitones: 0,
        ),
      );
      final preferences = UserPreferences(
        trackingMode: selectedMode,
        activeInstrumentId: created.id,
      );
      await preferencesRepository.save(preferences);
      final refreshed = await instrumentRepository.listAll();
      if (!mounted) {
        return;
      }
      setState(() {
        instruments = refreshed;
        selectedInstrument = created;
        isSaving = false;
      });
      populateInstrumentFields(created);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSaving = false;
        errorMessage = error.toString();
      });
    }
  }

  /// Deletes the currently selected instrument when it is not the seeded Piano.
  /// Repository reassigns [UserPreferences] to Piano if the deleted row was
  /// active; the UI then selects that fallback.
  Future<void> deleteSelectedInstrument() async {
    final current = selectedInstrument;
    if (current == null) {
      return;
    }
    if (InstrumentRepository.isProtectedDefaultInstrument(current.id)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete instrument'),
          content: Text('Delete "${current.name}" permanently?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      isSaving = true;
      errorMessage = null;
    });
    try {
      await instrumentRepository.deleteInstrument(current.id);
      final preferences = await preferencesRepository.loadOrCreateDefaults();
      final refreshed = await instrumentRepository.listAll();
      final active = refreshed
          .where((instrument) => instrument.id == preferences.activeInstrumentId)
          .firstOrNull;
      final resolvedActive = active ??
          (refreshed.isEmpty ? null : refreshed.first);

      if (!mounted) {
        return;
      }
      setState(() {
        instruments = refreshed;
        selectedInstrument = resolvedActive;
        selectedMode = preferences.trackingMode;
        isSaving = false;
      });
      populateInstrumentFields(resolvedActive);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSaving = false;
        errorMessage = error.toString();
      });
    }
  }

  Future<void> proceedToScore() async {
    final instrument = selectedInstrument;
    if (instrument == null) {
      setState(() {
        errorMessage = 'Select an instrument before proceeding.';
      });
      return;
    }

    setState(() {
      isSaving = true;
      errorMessage = null;
    });
    try {
      // Persist any in-progress field edits before navigating.
      final parsedFrequency =
          double.tryParse(frequencyController.text.trim()) ?? instrument.baseFrequencyHz;
      final parsedTransposition =
          int.tryParse(transpositionController.text.trim()) ?? instrument.transpositionSemitones;
      final trimmedName =
          nameController.text.trim().isEmpty ? instrument.name : nameController.text.trim();
      final savedInstrument = await instrumentRepository.upsert(
        instrument.copyWith(
          name: trimmedName,
          baseFrequencyHz: parsedFrequency,
          transpositionSemitones: parsedTransposition,
        ),
      );
      await preferencesRepository.save(
        UserPreferences(
          trackingMode: selectedMode,
          activeInstrumentId: savedInstrument.id,
        ),
      );

      if (!mounted) {
        return;
      }
      final config = TrackingSessionConfig(
        trackingMode: selectedMode,
        instrumentId: savedInstrument.id,
        baseFrequencyHz: savedInstrument.baseFrequencyHz,
        transpositionSemitones: savedInstrument.transpositionSemitones,
      );
      setState(() {
        isSaving = false;
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => TrackingScreen(config: config),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSaving = false;
        errorMessage = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Score Follower')),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
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
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 8),
                    Text(
                      selectedMode.description,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Instrument',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Saved offline. Changes persist across app restarts.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    if (instruments.isNotEmpty)
                      DropdownButtonFormField<int>(
                        key: ValueKey<int?>(selectedInstrument?.id),
                        initialValue: selectedInstrument?.id,
                        decoration: const InputDecoration(
                          labelText: 'Active instrument',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final instrument in instruments)
                            DropdownMenuItem<int>(
                              value: instrument.id,
                              child: Text(instrument.name),
                            ),
                        ],
                        onChanged: (instrumentId) {
                          if (instrumentId == null) {
                            return;
                          }
                          final match = instruments.firstWhere(
                            (instrument) => instrument.id == instrumentId,
                          );
                          setState(() {
                            selectedInstrument = match;
                          });
                          populateInstrumentFields(match);
                        },
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: frequencyController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'A4 base frequency (Hz)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: transpositionController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'-?[0-9]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Transposition (semitones)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSaving ? null : createInstrument,
                            child: const Text('Add instrument'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: isSaving ? null : saveInstrumentEdits,
                            child: const Text('Save instrument'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        final current = selectedInstrument;
                        final canDelete = current != null &&
                            !InstrumentRepository.isProtectedDefaultInstrument(
                              current.id,
                            );
                        return OutlinedButton.icon(
                          onPressed: (isSaving || !canDelete)
                              ? null
                              : deleteSelectedInstrument,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(
                            canDelete
                                ? 'Delete instrument'
                                : 'Default Piano cannot be deleted',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: canDelete
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        );
                      },
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        errorMessage!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: isSaving ? null : proceedToScore,
                      child: Text(isSaving ? 'Saving…' : 'Proceed to Score'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
