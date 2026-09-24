class GoogleDriveNativeAuthService {
  const GoogleDriveNativeAuthService();

  static bool get isSupported => false;

  Future<String> signIn() {
    throw UnsupportedError('Native Google authorization is not available.');
  }

  Future<String?> restoreAccessToken() async => null;

  Future<void> signOut() async {}
}
