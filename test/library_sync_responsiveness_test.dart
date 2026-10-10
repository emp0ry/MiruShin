import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/features/library/domain/canonical_library_models.dart';
import 'package:mirushin/features/library/presentation/library_sync_page.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/features/tracking/application/tracker_sync_coordinator.dart';
import 'package:mirushin/features/tracking/domain/tracker_models.dart';

class _Settings extends SettingsController {
  @override
  SettingsState build() => const SettingsState();
}

class _Repository extends CanonicalLibraryRepository {
  _Repository(super.database);
  final choices = <String>[];
  final saves = <Completer<String?>>[];

  @override
  Future<String?> resolveConflict({
    required String conflictId,
    required bool takeIncoming,
    required Set<TrackerSource> trackerTargets,
  }) {
    choices.add(conflictId);
    final save = Completer<String?>();
    saves.add(save);
    return save.future;
  }
}

class _StalledSync extends TrackerSyncCoordinator {
  _StalledSync(super.ref);
  final network = Completer<void>();
  int requests = 0;

  @override
  Future<void> flushPending() => network.future;

  @override
  void requestDelivery() {
    requests++;
    unawaited(flushPending());
  }
}

void main() {
  testWidgets(
    'conflict choices never wait for another card or a stalled sync',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      await tester.runAsync(() => AppLocalizations.load(const Locale('en')));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = CanonicalLibraryDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = _Repository(database);
      late _StalledSync sync;
      final conflicts = [
        for (final id in ['first', 'second'])
          CanonicalLibraryConflict(
            conflictId: id,
            localId: id,
            fieldName: 'score',
            localValue: const {
              'state': {'score': 8.5},
            },
            incomingValue: const {
              'state': {'score': 0},
            },
            createdAt: DateTime.utc(2026, 10, 10),
            state: 'open',
            title: id,
          ),
      ];
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          canonicalLibraryRepositoryProvider.overrideWithValue(repository),
          libraryActivityProvider.overrideWith((ref) => Stream.value([])),
          libraryConflictsProvider.overrideWith(
            (ref) => Stream.value(conflicts),
          ),
          pendingProviderAccountPreviewsProvider.overrideWith(
            (ref) async => [],
          ),
          trackerSyncCoordinatorProvider.overrideWith(
            (ref) => sync = _StalledSync(ref),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: [AppLocalizations.delegate],
            home: Scaffold(body: LibrarySyncPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final choices = find.widgetWithText(FilledButton, 'Keep local value');
      expect(choices, findsNWidgets(2));
      await tester.tap(choices.first);
      await tester.pump();
      expect(tester.widget<FilledButton>(choices.first).onPressed, isNull);
      expect(tester.widget<FilledButton>(choices.last).onPressed, isNotNull);
      repository.saves.first.complete('first-saved');
      await tester.pumpAndSettle();
      expect(sync.requests, 1);
      expect(sync.network.isCompleted, isFalse);
      expect(tester.widget<FilledButton>(choices.last).onPressed, isNotNull);
      await tester.tap(choices.last);
      await tester.pump();
      expect(repository.choices, ['first', 'second']);
      repository.saves.last.complete('second-saved');
      await tester.pumpAndSettle();
      expect(sync.requests, 2);
      expect(sync.network.isCompleted, isFalse);
      expect(tester.takeException(), isNull);
      sync.network.complete();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
