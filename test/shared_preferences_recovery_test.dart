import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/persistence/shared_preferences_recovery.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesStorePlatform originalStore;

  setUp(() {
    originalStore = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    MiruShinPreferences.resetForTesting();
    MiruShinPreferences.quarantineForTesting = () async => false;
  });

  tearDown(() {
    MiruShinPreferences.resetForTesting();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = originalStore;
  });

  test('loads valid persistent preferences without recovery', () async {
    final _TestPreferencesStore store = _TestPreferencesStore(<String, Object>{
      'flutter.settings.startupPage': 'library',
    });
    SharedPreferencesStorePlatform.instance = store;

    final SharedPreferences preferences =
        await MiruShinPreferences.initialize();

    expect(preferences.getString('settings.startupPage'), 'library');
    expect(store.clearCalls, 0);
    expect(store.loadCalls, 1);
  });

  test('clears corrupt platform data and retries loading', () async {
    final _TestPreferencesStore store = _TestPreferencesStore(
      <String, Object>{'flutter.settings.startupPage': 'library'},
      loadError: const FormatException('Unexpected character'),
      recoverWhenCleared: true,
    );
    SharedPreferencesStorePlatform.instance = store;

    final SharedPreferences preferences =
        await MiruShinPreferences.initialize();

    expect(preferences.getKeys(), isEmpty);
    expect(store.clearCalls, 1);
    expect(store.loadCalls, 2);

    await preferences.setString('settings.startupPage', 'board');
    expect(store.values['flutter.settings.startupPage'], 'board');
  });

  test(
    'uses a writable in-memory store when persistence is unavailable',
    () async {
      final _TestPreferencesStore store = _TestPreferencesStore(
        <String, Object>{},
        loadError: StateError('Storage is unavailable'),
      );
      SharedPreferencesStorePlatform.instance = store;

      final SharedPreferences preferences =
          await MiruShinPreferences.initialize();

      expect(preferences.getKeys(), isEmpty);
      expect(store.clearCalls, 0);
      await preferences.setBool('session.value', true);
      expect(preferences.getBool('session.value'), isTrue);
      expect(store.values, isEmpty);
    },
  );
}

final class _TestPreferencesStore extends SharedPreferencesStorePlatform {
  _TestPreferencesStore(
    Map<String, Object> values, {
    this.loadError,
    this.recoverWhenCleared = false,
  }) : values = Map<String, Object>.from(values);

  final Map<String, Object> values;
  final Object? loadError;
  final bool recoverWhenCleared;
  bool _recovered = false;
  int clearCalls = 0;
  int loadCalls = 0;

  @override
  Future<Map<String, Object>> getAll() async {
    loadCalls += 1;
    if (loadError != null && !_recovered) throw loadError!;
    return Map<String, Object>.from(values)
      ..removeWhere((String key, Object value) => !key.startsWith('flutter.'));
  }

  @override
  Future<bool> clear() async {
    clearCalls += 1;
    values.removeWhere(
      (String key, Object value) => key.startsWith('flutter.'),
    );
    if (recoverWhenCleared) _recovered = true;
    return recoverWhenCleared;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    values[key] = value;
    return true;
  }
}
