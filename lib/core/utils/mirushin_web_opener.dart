import '../constants/app_constants.dart';

final Uri _mirushinWebsiteOrigin = Uri.parse(AppConstants.appWebsiteUrl);
final Uri _mirushinWebOpener = _mirushinWebsiteOrigin.resolve('open.html');

/// Builds an absolute URL on MiruShin's public website.
Uri mirushinWebsiteUri(Iterable<String> pathSegments) {
  final List<String> segments = pathSegments.toList(growable: false);
  if (segments.any((String segment) => segment.isEmpty)) {
    throw ArgumentError.value(
      segments,
      'pathSegments',
      'Path segments must not be empty.',
    );
  }
  return _mirushinWebsiteOrigin.replace(pathSegments: segments);
}

/// Whether [uri] has the exact trusted MiruShin website origin.
bool isMirushinWebsiteUri(Uri uri) =>
    uri.scheme.toLowerCase() == _mirushinWebsiteOrigin.scheme &&
    uri.host.toLowerCase() == _mirushinWebsiteOrigin.host &&
    uri.port == _mirushinWebsiteOrigin.port &&
    uri.userInfo.isEmpty;

/// Wraps an internal MiruShin URI in the public HTTPS app opener.
Uri mirushinWebOpenUri(Uri target) {
  if (target.scheme.toLowerCase() != 'mirushin') {
    throw ArgumentError.value(
      target,
      'target',
      'Must use the mirushin scheme.',
    );
  }
  return _mirushinWebOpener.replace(
    queryParameters: <String, String>{'target': target.toString()},
  );
}

/// Returns the internal target only for the canonical MiruShin HTTPS opener.
Uri? tryUnwrapMirushinWebOpenUri(Uri uri) {
  if (!isMirushinWebsiteUri(uri) ||
      uri.path != _mirushinWebOpener.path ||
      uri.hasFragment) {
    return null;
  }
  final Map<String, List<String>> parameters = uri.queryParametersAll;
  if (parameters.length != 1 || parameters['target']?.length != 1) return null;
  final Uri? target = Uri.tryParse(parameters['target']!.single);
  return target?.scheme.toLowerCase() == 'mirushin' ? target : null;
}
