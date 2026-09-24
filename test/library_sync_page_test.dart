import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/domain/canonical_library_models.dart';
import 'package:mirushin/features/library/presentation/library_sync_page.dart';

void main() {
  test('Library Log summarizes more than four fields without throwing', () {
    final LibraryActivityEvent event = LibraryActivityEvent(
      operationId: 'operation-1',
      localId: 'media-1',
      deviceId: 'device-1',
      originKind: LibraryOriginKind.user,
      intent: LibraryMutationIntent.edit,
      fields: const <String>{'status', 'progress', 'score', 'notes', 'repeat'},
      before: const <String, dynamic>{
        'status': 'planning',
        'progress': 0,
        'score': 0,
        'notes': '',
        'repeat': 0,
      },
      after: const <String, dynamic>{
        'status': 'current',
        'progress': 1,
        'score': 85,
        'notes': 'Started',
        'repeat': 1,
      },
      targets: const <String>{'drive', 'anilist'},
      occurredAt: DateTime.utc(2026, 9, 23),
      deliveryStates: const <String, String>{
        'drive': 'pending',
        'anilist': 'pending',
      },
    );

    final String summary = libraryChangeSummary(event);

    expect(summary, contains('status: planning → current'));
    expect(summary, contains('+1'));
  });

  test('Library Log reads values from canonical state snapshots', () {
    final LibraryActivityEvent event = LibraryActivityEvent(
      operationId: 'operation-2',
      localId: 'media-2',
      deviceId: 'device-1',
      originKind: LibraryOriginKind.player,
      intent: LibraryMutationIntent.progress,
      fields: const <String>{'status', 'progress', 'membership'},
      before: const <String, dynamic>{
        'state': <String, dynamic>{'status': 'current', 'progress': 3},
      },
      after: const <String, dynamic>{
        'state': <String, dynamic>{'status': 'completed', 'progress': 4},
      },
      targets: const <String>{'drive', 'anilist'},
      occurredAt: DateTime.utc(2026, 9, 24),
      deliveryStates: const <String, String>{},
    );

    final String summary = libraryChangeSummary(event);

    expect(summary, contains('status: current → completed'));
    expect(summary, contains('progress: 3 → 4'));
    expect(summary, contains('membership: true → true'));
  });

  test('Library Log identifies the exact tracker source', () {
    final LibraryActivityEvent event = LibraryActivityEvent(
      operationId: 'operation-3',
      localId: 'media-3',
      deviceId: 'device-1',
      originKind: LibraryOriginKind.provider,
      originId: 'mal:42',
      intent: LibraryMutationIntent.remoteImport,
      fields: const <String>{'score'},
      before: const <String, dynamic>{},
      after: const <String, dynamic>{'score': 8},
      targets: const <String>{'drive', 'anilist'},
      occurredAt: DateTime.utc(2026, 9, 24),
      deliveryStates: const <String, String>{},
    );

    expect(libraryEventSourceTarget(event), 'mal');
    expect(libraryEventSourceLabel(event), 'MyAnimeList');
  });

  test('Library Log keeps provider-specific values separate', () {
    final LibraryActivityEvent event = LibraryActivityEvent(
      operationId: 'operation-4',
      localId: 'media-4',
      deviceId: 'device-1',
      originKind: LibraryOriginKind.user,
      intent: LibraryMutationIntent.edit,
      fields: const <String>{'priority', 'malPriority'},
      before: const <String, dynamic>{
        'state': <String, dynamic>{
          'providerStates': <String, dynamic>{
            'anilist': <String, dynamic>{
              'data': <String, dynamic>{'priority': 1},
            },
            'mal': <String, dynamic>{
              'data': <String, dynamic>{'priority': 0},
            },
          },
        },
      },
      after: const <String, dynamic>{
        'state': <String, dynamic>{
          'providerStates': <String, dynamic>{
            'anilist': <String, dynamic>{
              'data': <String, dynamic>{'priority': 3},
            },
            'mal': <String, dynamic>{
              'data': <String, dynamic>{'priority': 2},
            },
          },
        },
      },
      targets: const <String>{'anilist', 'mal'},
      occurredAt: DateTime.utc(2026, 9, 24),
      deliveryStates: const <String, String>{},
    );

    final String summary = libraryChangeSummary(event);

    expect(summary, contains('priority: 1 → 3'));
    expect(summary, contains('malPriority: 0 → 2'));
  });
}
