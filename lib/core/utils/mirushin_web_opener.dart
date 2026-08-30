import '../constants/app_constants.dart';

final Uri _mirushinWebOpener = Uri.parse(
  AppConstants.appWebsiteUrl,
).resolve('open.html');

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
  if (uri.scheme.toLowerCase() != _mirushinWebOpener.scheme ||
      uri.host.toLowerCase() != _mirushinWebOpener.host ||
      uri.port != _mirushinWebOpener.port ||
      uri.path != _mirushinWebOpener.path ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return null;
  }
  final Map<String, List<String>> parameters = uri.queryParametersAll;
  if (parameters.length != 1 || parameters['target']?.length != 1) return null;
  final Uri? target = Uri.tryParse(parameters['target']!.single);
  return target?.scheme.toLowerCase() == 'mirushin' ? target : null;
}
