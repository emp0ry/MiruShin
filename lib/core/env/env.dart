import 'package:envied/envied.dart';

part 'env.g.dart';

/// Compile-time secrets bundled into the app.
///
/// Values come from the `.env` file at the project root and are XOR-obfuscated
/// at build time by `envied` so the raw token never appears as a plain string
/// in the compiled binary. Regenerate after editing `.env` with:
///
///   dart run build_runner build --delete-conflicting-outputs
///
/// Neither `.env` nor `env.g.dart` is committed; CI recreates both from the
/// `TMDB_READ_ACCESS_TOKEN` repository secret before building.
@Envied(path: '.env', obfuscate: true)
abstract final class Env {
  /// Default TMDB v4 Read Access Token used when the user has not enabled a
  /// custom API key in Settings → API Connections.
  @EnviedField(varName: 'TMDB_READ_ACCESS_TOKEN', obfuscate: true)
  static final String tmdbReadAccessToken = _Env.tmdbReadAccessToken;
}
