import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/presentation/google_drive_login_flow.dart';

void main() {
  group('Google Drive login routing', () {
    test('uses native sign-in on supported phones and tablets', () {
      expect(
        chooseGoogleDriveLoginRoute(isAndroidTv: false, nativeSupported: true),
        GoogleDriveLoginRoute.native,
      );
    });

    test('keeps Android TV on the Worker device flow', () {
      expect(
        chooseGoogleDriveLoginRoute(isAndroidTv: true, nativeSupported: true),
        GoogleDriveLoginRoute.device,
      );
    });

    test('uses desktop PKCE when native sign-in is unavailable', () {
      expect(
        chooseGoogleDriveLoginRoute(isAndroidTv: false, nativeSupported: false),
        GoogleDriveLoginRoute.desktop,
      );
    });
  });
}
