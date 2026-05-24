import '../models/addon_info.dart';

abstract final class MockAddons {
  static const List<AddonInfo> installed = <AddonInfo>[
    AddonInfo(
      id: 'metadata-companion',
      name: 'Metadata Companion',
      description:
          'Prepares richer metadata panels and related-title suggestions.',
      version: '0.1.0',
      author: 'Miru Labs',
      enabled: true,
      permissions: <String>['Read metadata', 'Suggest collections'],
      category: 'Metadata',
    ),
    AddonInfo(
      id: 'calendar-bridge',
      name: 'Calendar Bridge',
      description: 'Release reminders and external calendar export planning.',
      version: '0.1.0',
      author: 'Miru Labs',
      enabled: false,
      permissions: <String>['Read calendar entries'],
      category: 'Calendar',
    ),
  ];

  static const List<AddonInfo> featured = <AddonInfo>[
    AddonInfo(
      id: 'tracker-health',
      name: 'Tracker Health',
      description:
          'Concept addon for tracking service diagnostics and sync summaries.',
      version: 'Preview',
      author: 'Community Concept',
      enabled: false,
      permissions: <String>['Read tracking status'],
      category: 'Tracking',
    ),
    AddonInfo(
      id: 'library-curator',
      name: 'Library Curator',
      description:
          'Concept addon for organizing local entries into smart collections.',
      version: 'Preview',
      author: 'Community Concept',
      enabled: false,
      permissions: <String>['Read local library'],
      category: 'Library',
    ),
  ];
}
