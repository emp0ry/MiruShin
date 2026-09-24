import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';

class GoogleDriveAccountProfile {
  const GoogleDriveAccountProfile({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
  });

  factory GoogleDriveAccountProfile.fromJson(Map<String, dynamic> json) {
    final Object? rawUser = json['user'];
    final Map<String, dynamic> user = rawUser is Map<String, dynamic>
        ? rawUser
        : rawUser is Map<dynamic, dynamic>
        ? rawUser.map(
            (dynamic key, dynamic value) =>
                MapEntry<String, dynamic>('$key', value),
          )
        : const <String, dynamic>{};
    return GoogleDriveAccountProfile(
      id: '${user['permissionId'] ?? ''}'.trim(),
      email: '${user['emailAddress'] ?? ''}'.trim(),
      displayName: '${user['displayName'] ?? ''}'.trim(),
      avatarUrl: _optionalString(user['photoLink']),
    );
  }

  factory GoogleDriveAccountProfile.fromStoredJson(Map<String, dynamic> json) =>
      GoogleDriveAccountProfile(
        id: '${json['id'] ?? ''}'.trim(),
        email: '${json['email'] ?? ''}'.trim(),
        displayName: '${json['displayName'] ?? ''}'.trim(),
        avatarUrl: _optionalString(json['avatarUrl']),
      );

  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;

  String get title => displayName.isNotEmpty
      ? displayName
      : email.isNotEmpty
      ? email
      : 'Google Drive';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'email': email,
    'displayName': displayName,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
  };

  static String? _optionalString(Object? value) {
    final String result = '${value ?? ''}'.trim();
    return result.isEmpty ? null : result;
  }
}

class GoogleDriveAccountClient {
  GoogleDriveAccountClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<GoogleDriveAccountProfile> fetchProfile(String accessToken) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '${AppConstants.googleDriveApiBaseUrl}/about',
      queryParameters: const <String, String>{
        'fields': 'user(displayName,emailAddress,photoLink,permissionId)',
      },
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer ${accessToken.trim()}',
        },
      ),
    );
    final Object? body = response.data;
    final Map<String, dynamic> json = body is Map<String, dynamic>
        ? body
        : body is Map<dynamic, dynamic>
        ? body.map(
            (dynamic key, dynamic value) =>
                MapEntry<String, dynamic>('$key', value),
          )
        : const <String, dynamic>{};
    final GoogleDriveAccountProfile profile =
        GoogleDriveAccountProfile.fromJson(json);
    if (profile.id.isEmpty &&
        profile.email.isEmpty &&
        profile.displayName.isEmpty) {
      throw StateError('Google Drive did not return account information.');
    }
    return profile;
  }
}
