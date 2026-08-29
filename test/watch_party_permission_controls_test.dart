import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/features/watch_party/application/watch_party_controller.dart';
import 'package:mirushin/features/watch_party/domain/watch_party_models.dart';
import 'package:mirushin/features/watch_party/presentation/watch_party_permission_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('host can grant the change stream permission', (
    WidgetTester tester,
  ) async {
    _HostWatchPartyController.lastStreamPermission = null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          watchPartyProvider.overrideWith(_HostWatchPartyController.new),
        ],
        child: const _PermissionTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Change stream'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Change stream'));

    expect(_HostWatchPartyController.lastStreamPermission, isTrue);
  });

  testWidgets('guest sees change stream in the granted controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: _PermissionTestApp(
          party: WatchPartyRoomState(
            role: WatchPartyRole.guest,
            status: WatchPartyConnectionStatus.connected,
            peerConnected: true,
            permissions: WatchPartyPermissions(canChangeStream: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your controls'), findsOneWidget);
    expect(find.text('Change stream'), findsOneWidget);
    expect(find.byIcon(Icons.dns_rounded), findsOneWidget);
  });
}

class _PermissionTestApp extends ConsumerWidget {
  const _PermissionTestApp({this.party});

  final WatchPartyRoomState? party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WatchPartyRoomState current = party ?? ref.watch(watchPartyProvider);
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        _TestLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: WatchPartyPermissionControls(party: current)),
    );
  }
}

class _TestLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _TestLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(
      AppLocalizations(
        locale,
        const <String, String>{},
        const <String, String>{},
      ),
    );
  }

  @override
  bool shouldReload(_TestLocalizationsDelegate old) => false;
}

class _HostWatchPartyController extends WatchPartyController {
  static bool? lastStreamPermission;

  @override
  WatchPartyRoomState build() {
    return const WatchPartyRoomState(
      role: WatchPartyRole.host,
      status: WatchPartyConnectionStatus.connected,
      peerConnected: true,
    );
  }

  @override
  void setGuestStreamChangeAllowed(bool allowed) {
    lastStreamPermission = allowed;
  }
}
