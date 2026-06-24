import 'package:envied/envied.dart';

part 'env.g.dart';

/// Compile-time configuration bundled into the app.
///
/// Values come from the `.env` file at the project root and are XOR-obfuscated
/// at build time by `envied` so the raw token never appears as a plain string
/// in the compiled binary. Regenerate after editing `.env` with:
///
///   dart run build_runner build --delete-conflicting-outputs
///
/// Neither `.env` nor `env.g.dart` is committed; CI recreates both from build
/// secrets before building.
@Envied(path: '.env', obfuscate: true)
abstract final class Env {
  /// Default TMDB v4 Read Access Token used when the user has not enabled a
  /// custom API key in Settings → API Connections.
  @EnviedField(varName: 'TMDB_READ_ACCESS_TOKEN', obfuscate: true)
  static final String tmdbReadAccessToken = _Env.tmdbReadAccessToken;

  /// Public catalog of Sora modules used to resolve a short addon id (e.g.
  /// "Ag9V") typed in the Add Addon dialog to its manifest URL. Obfuscated so
  /// the endpoint is not a plain string in the source or compiled binary.
  @EnviedField(varName: 'MODULE_LIBRARY_URL', obfuscate: true)
  static final String moduleLibraryUrl = _Env.moduleLibraryUrl;

}
