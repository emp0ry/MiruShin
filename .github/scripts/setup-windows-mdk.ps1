$ErrorActionPreference = "Stop"

$archiveName = "mdk-sdk-windows-x64.7z"
$fvpWindowsDir = Join-Path $PWD "windows/flutter/ephemeral/.plugin_symlinks/fvp/windows"

if (-not (Test-Path $fvpWindowsDir)) {
  throw "FVP Windows plugin directory not found: $fvpWindowsDir. Run flutter pub get before this script."
}

$archivePath = Join-Path $fvpWindowsDir $archiveName
$sdkDir = Join-Path $fvpWindowsDir "mdk-sdk"
$urls = @(
  "https://github.com/wang-bin/mdk-sdk/releases/download/v0.36.0/$archiveName",
  "https://sourceforge.net/projects/mdk-sdk/files/nightly/$archiveName/download"
)

if (Test-Path $archivePath) { Remove-Item $archivePath -Force }
if (Test-Path $sdkDir) { Remove-Item $sdkDir -Recurse -Force }

$downloaded = $false
foreach ($url in $urls) {
  Write-Host "Downloading $archiveName from $url"
  try {
    & curl.exe -L --fail --retry 3 --retry-delay 2 -o $archivePath $url
    if ($LASTEXITCODE -ne 0) {
      throw "curl exited with code $LASTEXITCODE"
    }

    $size = (Get-Item $archivePath).Length
    if ($size -lt 1MB) {
      throw "downloaded file is too small ($size bytes)"
    }

    $downloaded = $true
    break
  } catch {
    Write-Warning "MDK SDK download failed from ${url}: $_"
    if (Test-Path $archivePath) { Remove-Item $archivePath -Force }
  }
}

if (-not $downloaded) {
  throw "Unable to download a valid $archiveName archive."
}

if (Get-Command cmake -ErrorAction SilentlyContinue) {
  $tempBase = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
  $checkDir = Join-Path $tempBase "mirushin-mdk-windows-check"
  if (Test-Path $checkDir) { Remove-Item $checkDir -Recurse -Force }
  New-Item -ItemType Directory -Path $checkDir | Out-Null

  Push-Location $checkDir
  try {
    & cmake -E tar xvf $archivePath | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "cmake archive validation failed with code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }

  $findMdk = Join-Path $checkDir "mdk-sdk/lib/cmake/FindMDK.cmake"
  if (-not (Test-Path $findMdk)) {
    throw "Archive validation failed: $findMdk was not found."
  }
  Remove-Item $checkDir -Recurse -Force
}

Write-Host "Prepared $archiveName at $archivePath"
