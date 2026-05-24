import 'discord_rpc_models.dart';

export 'discord_rpc_models.dart';

class DiscordRpcService {
  DiscordRpcService._();

  static bool get isSupported => false;

  static Future<void> configure({
    required bool appEnabled,
    required bool playerEnabled,
  }) async {}

  static Future<void> updatePresence(DiscordRpcPresence presence) async {}

  static Future<void> clearActivity() async {}

  static Future<void> dispose() async {}
}
