import 'desktop_update_installer_base.dart';
import 'desktop_update_installer_stub.dart'
    if (dart.library.io) 'desktop_update_installer_io.dart'
    as implementation;

export 'desktop_update_installer_base.dart';

DesktopUpdateInstaller createDesktopUpdateInstaller() =>
    implementation.createDesktopUpdateInstaller();
