import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('host can copy the complete invite link again', (
    WidgetTester tester,
  ) async {
    MethodCall? clipboardCall;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') clipboardCall = call;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          watchPartyProvider.overrideWith(_HostWatchPartyController.new),
        ],
        child: const _PermissionTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('copy-watch-party-invite')));
    await tester.pump();

    expect(clipboardCall?.method, 'Clipboard.setData');
    expect(
      (clipboardCall?.arguments as Map<Object?, Object?>?)?['text'],
      _HostWatchPartyController.inviteUrl,
    );
    expect(find.text('Invite link copied'), findsOneWidget);
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
  static const String inviteUrl =
      'mirushin:///watch-party/join?room=RelayRoom123456&transport=relay'
      '&relay=https%3A%2F%2Frelay.example.com&token=guest-token';
  static bool? lastStreamPermission;

  @override
  WatchPartyRoomState build() {
    return const WatchPartyRoomState(
      role: WatchPartyRole.host,
      status: WatchPartyConnectionStatus.connected,
      peerConnected: true,
      roomCode: 'RelayRoom123456',
      inviteUrl: inviteUrl,
    );
  }

  @override
  void setGuestStreamChangeAllowed(bool allowed) {
    lastStreamPermission = allowed;
  }
}
