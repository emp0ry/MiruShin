import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../domain/update_models.dart';
import 'desktop_update_installer_base.dart';

DesktopUpdateInstaller createDesktopUpdateInstaller() =>
    _IoDesktopUpdateInstaller();

class _IoDesktopUpdateInstaller implements DesktopUpdateInstaller {
  _IoDesktopUpdateInstaller()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 10),
          followRedirects: true,
          maxRedirects: 8,
        ),
      );

  final Dio _dio;

  @override
  DesktopUpdatePlatform? get platform {
    if (Platform.isWindows) return DesktopUpdatePlatform.windows;
    if (Platform.isMacOS) return DesktopUpdatePlatform.macos;
    if (Platform.isLinux) return DesktopUpdatePlatform.linux;
    return null;
  }

  @override
  bool get isSupported {
    if (Platform.isWindows) return true;
    if (Platform.isMacOS) return _currentMacAppBundle() != null;
    if (Platform.isLinux) return _currentLinuxAppImage() != null;
    return false;
  }

  @override
  Future<void> prepareAndLaunch({
    required UpdateInfo update,
    required UpdateAsset asset,
    required DesktopUpdateProgressCallback onProgress,
  }) async {
    final String? expectedDigest = asset.sha256Digest;
    if (expectedDigest == null) {
      throw const DesktopUpdateException(
        'The release asset has no valid SHA-256 digest.',
      );
    }

    final Directory workingDirectory = await Directory.systemTemp.createTemp(
      'mirushin-update-',
    );
    try {
      final File downloaded = await _downloadAsset(
        asset,
        workingDirectory,
        onProgress,
      );
      await _verifyDigest(downloaded, expectedDigest);
      onProgress(
        DesktopUpdatePreparationPhase.preparing,
        asset.size,
        asset.size,
      );

      if (Platform.isWindows) {
        await _launchWindowsUpdater(downloaded, workingDirectory);
        return;
      }
      if (Platform.isMacOS) {
        await _launchMacUpdater(downloaded, workingDirectory);
        return;
      }
      if (Platform.isLinux) {
        await _launchLinuxUpdater(downloaded, workingDirectory);
        return;
      }
      throw const DesktopUpdateException(
        'Automatic updates are unavailable on this platform.',
      );
    } catch (error) {
      await _deleteDirectoryBestEffort(workingDirectory);
      if (error is DesktopUpdateException) rethrow;
      if (error is DioException) {
        final int? statusCode = error.response?.statusCode;
        throw DesktopUpdateException(
          statusCode == null
              ? 'Could not download the update.'
              : 'The update server returned HTTP $statusCode.',
        );
      }
      if (error is FileSystemException) {
        throw DesktopUpdateException(
          'Could not prepare the update: ${error.message}',
        );
      }
      if (error is ProcessException) {
        throw DesktopUpdateException(
          'Could not start the system updater: ${error.message}',
        );
      }
      throw const DesktopUpdateException('Could not prepare the update.');
    }
  }

  Future<File> _downloadAsset(
    UpdateAsset asset,
    Directory workingDirectory,
    DesktopUpdateProgressCallback onProgress,
  ) async {
    final Uri? uri = Uri.tryParse(asset.downloadUrl);
    if (uri == null || uri.scheme != 'https') {
      throw const DesktopUpdateException('The update URL is not secure.');
    }

    final String safeName = p
        .basename(asset.name)
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (safeName.isEmpty || safeName == '.' || safeName == '..') {
      throw const DesktopUpdateException('The update asset name is invalid.');
    }
    final File destination = File(p.join(workingDirectory.path, safeName));
    final Response<ResponseBody> response = await _dio.get<ResponseBody>(
      asset.downloadUrl,
      options: Options(
        responseType: ResponseType.stream,
        headers: const <String, String>{'Accept': 'application/octet-stream'},
      ),
    );
    final ResponseBody? body = response.data;
    if (body == null) {
      throw const DesktopUpdateException('The update download was empty.');
    }

    final int totalBytes = asset.size > 0 ? asset.size : body.contentLength;
    int receivedBytes = 0;
    final IOSink sink = destination.openWrite();
    try {
      await for (final List<int> chunk in body.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress(
          DesktopUpdatePreparationPhase.downloading,
          receivedBytes,
          totalBytes,
        );
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (receivedBytes <= 0) {
      throw const DesktopUpdateException('The update download was empty.');
    }
    if (asset.size > 0 && receivedBytes != asset.size) {
      throw DesktopUpdateException(
        'The update download was incomplete ($receivedBytes of ${asset.size} bytes).',
      );
    }
    return destination;
  }

  Future<void> _verifyDigest(File file, String expectedDigest) async {
    final Digest actual = await sha256.bind(file.openRead()).first;
    if (actual.toString().toLowerCase() != expectedDigest) {
      throw const DesktopUpdateException(
        'The downloaded update failed its SHA-256 verification.',
      );
    }
  }

  Future<void> _launchWindowsUpdater(
    File installer,
    Directory workingDirectory,
  ) async {
    final File helper = File(p.join(workingDirectory.path, 'install.ps1'));
    await helper.writeAsString(_windowsUpdaterScript, flush: true);
    final File bootstrap = File(p.join(workingDirectory.path, 'bootstrap.ps1'));
    await bootstrap.writeAsString(_windowsUpdaterBootstrapScript, flush: true);
    final bool isMsi = installer.path.toLowerCase().endsWith('.msi');
    final String logRoot =
        (Platform.environment['LOCALAPPDATA'] ?? '').trim().isNotEmpty
        ? Platform.environment['LOCALAPPDATA']!.trim()
        : Directory.systemTemp.path;
    final Directory logDirectory = Directory(p.join(logRoot, 'MiruShin'));
    await logDirectory.create(recursive: true);
    final File logFile = File(p.join(logDirectory.path, 'updater.log'));

    // A process created directly by a debug-launched Flutter app is assigned
    // to the IDE's process job and is terminated when the app exits. The short
    // bootstrap asks the Windows process service to create the real updater,
    // making its lifetime independent from both MiruShin and the IDE.
    final ProcessResult result = await Process.run('powershell.exe', <String>[
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      bootstrap.path,
      helper.path,
      '$pid',
      installer.path,
      Platform.resolvedExecutable,
      workingDirectory.path,
      isMsi ? 'msi' : 'exe',
      logFile.path,
    ]);
    if (result.exitCode != 0) {
      throw DesktopUpdateException(
        'Windows could not detach the updater: ${result.stderr}',
      );
    }
  }

  Future<void> _launchMacUpdater(
    File diskImage,
    Directory workingDirectory,
  ) async {
    final Directory? currentApp = _currentMacAppBundle();
    if (currentApp == null) {
      throw const DesktopUpdateException(
        'The running macOS app is not inside an app bundle.',
      );
    }
    await _verifyDirectoryIsWritable(currentApp.parent);

    final Directory mountPoint = Directory(
      p.join(workingDirectory.path, 'mount'),
    );
    await mountPoint.create();
    final ProcessResult mount = await Process.run('/usr/bin/hdiutil', <String>[
      'attach',
      '-nobrowse',
      '-readonly',
      '-mountpoint',
      mountPoint.path,
      diskImage.path,
    ]);
    if (mount.exitCode != 0) {
      throw DesktopUpdateException(
        'Could not open the update disk image: ${mount.stderr}',
      );
    }

    final Directory stagedApp = Directory(
      '${currentApp.path}.update-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      final Directory? sourceApp = await _firstAppBundleIn(mountPoint);
      if (sourceApp == null) {
        throw const DesktopUpdateException(
          'The update disk image contains no app bundle.',
        );
      }
      final ProcessResult copy = await Process.run('/usr/bin/ditto', <String>[
        sourceApp.path,
        stagedApp.path,
      ]);
      if (copy.exitCode != 0 || !await stagedApp.exists()) {
        throw DesktopUpdateException(
          'Could not stage the macOS update: ${copy.stderr}',
        );
      }
    } catch (_) {
      await _deleteDirectoryBestEffort(stagedApp);
      rethrow;
    } finally {
      await Process.run('/usr/bin/hdiutil', <String>[
        'detach',
        mountPoint.path,
        '-force',
      ]);
    }

    final String backupPath =
        '${currentApp.path}.previous-${DateTime.now().microsecondsSinceEpoch}';
    final File helper = File(p.join(workingDirectory.path, 'install.sh'));
    await helper.writeAsString(_unixBundleUpdaterScript, flush: true);
    try {
      await _makeExecutable(helper, mode: '700');
      await Process.start('/bin/sh', <String>[
        helper.path,
        '$pid',
        currentApp.path,
        stagedApp.path,
        backupPath,
        workingDirectory.path,
        'macos',
      ], mode: ProcessStartMode.detached);
    } catch (_) {
      await _deleteDirectoryBestEffort(stagedApp);
      rethrow;
    }
  }

  Future<void> _launchLinuxUpdater(
    File downloaded,
    Directory workingDirectory,
  ) async {
    final File? currentAppImage = _currentLinuxAppImage();
    if (currentAppImage == null) {
      throw const DesktopUpdateException(
        'Automatic Linux updates require the AppImage build.',
      );
    }
    await _verifyDirectoryIsWritable(currentAppImage.parent);

    final File staged = File(
      '${currentAppImage.path}.update-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await downloaded.copy(staged.path);
      await _makeExecutable(staged, mode: '755');

      final String backupPath =
          '${currentAppImage.path}.previous-${DateTime.now().microsecondsSinceEpoch}';
      final File helper = File(p.join(workingDirectory.path, 'install.sh'));
      await helper.writeAsString(_unixBundleUpdaterScript, flush: true);
      await _makeExecutable(helper, mode: '700');
      await Process.start('/bin/sh', <String>[
        helper.path,
        '$pid',
        currentAppImage.path,
        staged.path,
        backupPath,
        workingDirectory.path,
        'linux',
      ], mode: ProcessStartMode.detached);
    } catch (_) {
      try {
        if (await staged.exists()) await staged.delete();
      } on FileSystemException {
        // A later update can safely replace this uniquely named staging file.
      }
      rethrow;
    }
  }

  Directory? _currentMacAppBundle() {
    if (!Platform.isMacOS) return null;
    Directory current = File(Platform.resolvedExecutable).parent;
    while (current.path != current.parent.path) {
      if (current.path.toLowerCase().endsWith('.app')) return current;
      current = current.parent;
    }
    return null;
  }

  File? _currentLinuxAppImage() {
    if (!Platform.isLinux) return null;
    final String value = (Platform.environment['APPIMAGE'] ?? '').trim();
    if (value.isEmpty) return null;
    try {
      final File file = File(File(value).resolveSymbolicLinksSync());
      return file.existsSync() ? file : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<Directory?> _firstAppBundleIn(Directory directory) async {
    await for (final FileSystemEntity entity in directory.list(
      followLinks: false,
    )) {
      if (entity is Directory && entity.path.toLowerCase().endsWith('.app')) {
        return entity;
      }
    }
    return null;
  }

  Future<void> _verifyDirectoryIsWritable(Directory directory) async {
    final File marker = File(
      p.join(
        directory.path,
        '.mirushin-update-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      await marker.writeAsString('update-check', flush: true);
      await marker.delete();
    } on FileSystemException {
      throw const DesktopUpdateException(
        'The app installation directory is not writable.',
      );
    }
  }

  Future<void> _makeExecutable(File file, {required String mode}) async {
    final ProcessResult result = await Process.run('/bin/chmod', <String>[
      mode,
      file.path,
    ]);
    if (result.exitCode != 0) {
      throw DesktopUpdateException(
        'Could not make an update helper executable: ${result.stderr}',
      );
    }
  }

  Future<void> _deleteDirectoryBestEffort(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // The operating system may still be releasing an update file handle.
    }
  }
}

const String _windowsUpdaterBootstrapScript = r'''
param(
  [string]$UpdaterScript,
  [string]$TargetPid,
  [string]$InstallerPath,
  [string]$FallbackExecutable,
  [string]$WorkingDirectory,
  [string]$InstallerKind,
  [string]$LogPath
)

$ErrorActionPreference = 'Stop'

function Quote-ProcessArgument([string]$Value) {
  return '"' + $Value + '"'
}

$powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$commandParts = @(
  (Quote-ProcessArgument $powershellPath),
  '-NoLogo',
  '-NoProfile',
  '-NonInteractive',
  '-ExecutionPolicy',
  'Bypass',
  '-WindowStyle',
  'Hidden',
  '-File',
  (Quote-ProcessArgument $UpdaterScript),
  (Quote-ProcessArgument $TargetPid),
  (Quote-ProcessArgument $InstallerPath),
  (Quote-ProcessArgument $FallbackExecutable),
  (Quote-ProcessArgument $WorkingDirectory),
  (Quote-ProcessArgument $InstallerKind),
  (Quote-ProcessArgument $LogPath)
)
$commandLine = $commandParts -join ' '

$startupConfig = ([wmiclass]'Win32_ProcessStartup').CreateInstance()
$startupConfig.ShowWindow = 0
$createResult = ([wmiclass]'Win32_Process').Create(
  $commandLine,
  $WorkingDirectory,
  $startupConfig
)
if ($createResult.ReturnValue -ne 0) {
  throw "Win32_Process.Create failed with code $($createResult.ReturnValue)."
}
''';

const String _windowsUpdaterScript = r'''
param(
  [int]$TargetPid,
  [string]$InstallerPath,
  [string]$FallbackExecutable,
  [string]$WorkingDirectory,
  [string]$InstallerKind,
  [string]$LogPath
)

$ErrorActionPreference = 'Stop'
function Write-UpdateLog([string]$Message) {
  Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) $Message" -ErrorAction SilentlyContinue
}

Set-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) Updater started. targetPid=$TargetPid" -ErrorAction SilentlyContinue
for ($attempt = 0; $attempt -lt 180; $attempt++) {
  if (-not (Get-Process -Id $TargetPid -ErrorAction SilentlyContinue)) { break }
  Start-Sleep -Seconds 1
}
if (Get-Process -Id $TargetPid -ErrorAction SilentlyContinue) {
  Write-UpdateLog 'The app did not exit within 180 seconds. Update aborted.'
  exit 2
}
Write-UpdateLog 'The app exited. Starting installer.'

$succeeded = $false
try {
  if ($InstallerKind -eq 'msi') {
    $arguments = @('/i', $InstallerPath, '/passive', '/norestart')
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru
    $succeeded = $process.ExitCode -in @(0, 1641, 3010)
    Write-UpdateLog "MSI installer exited with code $($process.ExitCode)."
  } else {
    # Updating the running directory also keeps portable ZIP installations on
    # the same executable path instead of silently creating a second install.
    $installDirectory = Split-Path -Parent $FallbackExecutable
    $arguments = @(
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      ('/DIR="' + $installDirectory + '"')
    )
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru
    $succeeded = $process.ExitCode -eq 0
    Write-UpdateLog "Setup installer exited with code $($process.ExitCode)."
  }
} catch {
  $succeeded = $false
  Write-UpdateLog "Installer failed: $($_.Exception.Message)"
}

# Silent installers intentionally do not launch the app. Restart it here after
# both success and failure; a cancelled installer leaves the old app intact.
$restartStarted = $false
if (Test-Path -LiteralPath $FallbackExecutable) {
  try {
    Start-Process -FilePath $FallbackExecutable -WorkingDirectory (Split-Path -Parent $FallbackExecutable)
    $restartStarted = $true
    Write-UpdateLog "Restarted $FallbackExecutable. installSucceeded=$succeeded"
  } catch {
    Write-UpdateLog "Could not restart the original executable: $($_.Exception.Message)"
  }
} else {
  $restartCandidates = @(
    (Join-Path $env:ProgramFiles 'MiruShin\mirushin.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\MiruShin\mirushin.exe')
  )
  if (${env:ProgramFiles(x86)}) {
    $restartCandidates += Join-Path ${env:ProgramFiles(x86)} 'MiruShin\mirushin.exe'
  }
  foreach ($candidate in $restartCandidates) {
    if (Test-Path -LiteralPath $candidate) {
      try {
        Start-Process -FilePath $candidate -WorkingDirectory (Split-Path -Parent $candidate)
        $restartStarted = $true
        Write-UpdateLog "Restarted fallback $candidate. installSucceeded=$succeeded"
      } catch {
        Write-UpdateLog "Could not restart fallback ${candidate}: $($_.Exception.Message)"
      }
      break
    }
  }
}

if ($restartStarted) {
  Start-Sleep -Seconds 2
  Remove-Item -LiteralPath $WorkingDirectory -Recurse -Force -ErrorAction SilentlyContinue
} else {
  Write-UpdateLog "No executable could be restarted. Update files remain at $WorkingDirectory"
  exit 3
}
''';

const String _unixBundleUpdaterScript = r'''#!/bin/sh
target_pid="$1"
current="$2"
staged="$3"
backup="$4"
working="$5"
platform="$6"

attempt=0
while kill -0 "$target_pid" 2>/dev/null && [ "$attempt" -lt 180 ]; do
  sleep 1
  attempt=$((attempt + 1))
done

if kill -0 "$target_pid" 2>/dev/null; then
  exit 1
fi

if mv -- "$current" "$backup" && mv -- "$staged" "$current"; then
  if [ "$platform" = "macos" ]; then
    nohup /usr/bin/open "$current" >/dev/null 2>&1 &
  else
    chmod 755 "$current"
    nohup "$current" >/dev/null 2>&1 &
  fi
  sleep 2
  rm -rf -- "$backup"
  rm -rf -- "$working"
  exit 0
fi

if [ ! -e "$current" ] && [ -e "$backup" ]; then
  mv -- "$backup" "$current"
fi
if [ "$platform" = "macos" ]; then
  nohup /usr/bin/open "$current" >/dev/null 2>&1 &
else
  nohup "$current" >/dev/null 2>&1 &
fi
exit 1
''';
