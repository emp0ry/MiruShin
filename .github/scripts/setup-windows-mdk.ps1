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

# Extract the SDK ourselves so fvp's deps.cmake finds mdk-sdk/ already in place
# and skips its own extraction (it guards on mdk-sdk/lib/cmake/FindMDK.cmake
# existing). fvp extracts with `cmake -E tar`, whose libarchive enforces
# ARCHIVE_EXTRACT_SECURE_SYMLINKS and refuses to write into
# windows/flutter/ephemeral/.plugin_symlinks/fvp (a Flutter junction), failing
# on the windows-2025-vs2026 runner. 7-Zip has no such policy and writes through
# the junction fine, so we use it here.
$sevenZip = (Get-Command 7z -ErrorAction SilentlyContinue).Source
if (-not $sevenZip) {
  $candidate = Join-Path $env:ProgramFiles "7-Zip/7z.exe"
  if (Test-Path $candidate) { $sevenZip = $candidate }
}
if (-not $sevenZip) {
  throw "7-Zip (7z) is required to extract $archiveName but was not found."
}

& $sevenZip x $archivePath "-o$fvpWindowsDir" -y | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "7-Zip extraction failed with code $LASTEXITCODE"
}

$findMdk = Join-Path $sdkDir "lib/cmake/FindMDK.cmake"
if (-not (Test-Path $findMdk)) {
  throw "Extraction failed: $findMdk was not found."
}

# Drop the archive so fvp's md5/download paths stay inert; mdk-sdk/ is enough.
if (Test-Path $archivePath) { Remove-Item $archivePath -Force }

Write-Host "Extracted mdk-sdk to $sdkDir"
