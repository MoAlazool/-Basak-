# Builds the signed release APKs (for direct install) and the Play Store App
# Bundle. Run from anywhere:
#   powershell -ExecutionPolicy Bypass -File mobile_app\tool\build_release.ps1
# -ApkOnly builds a single APK for every phone instead (no per-CPU split, no AAB);
# add -Arm64 for a smaller APK that installs on 64-bit phones only.
#
# Why a copy: Flutter's AOT compiler (gen_snapshot) cannot read files under a
# non-ASCII path such as "باصك (Basak)", and Gradle resolves junctions back to
# the real path; Kotlin also fails when sources and build output are on
# different drives (so a subst drive does not work either). The project is
# mirrored to an ASCII folder on C: and built there. The signing key is NOT
# copied: the copy's key.properties points at the original keystore.
param(
  [string]$BuildDir = "C:\basak_build\mobile_app",
  [string]$Flutter = "C:\src\flutter\bin\flutter.bat",
  [switch]$ApkOnly,
  [switch]$Arm64
)
$ErrorActionPreference = "Stop"
$src = Split-Path -Parent $PSScriptRoot          # ...\mobile_app
$keyProps = Join-Path $src "android\key.properties"
if (-not (Test-Path $keyProps)) { throw "android\key.properties is missing: release builds must be signed with the upload key." }
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr" }

# The Firebase client values (lib/core/constants/firebase_config.dart): without
# them the app still builds, but has no push notifications at all.
$defines = @()
if (Test-Path (Join-Path $src "firebase.defines.json")) {
  $defines = @("--dart-define-from-file=firebase.defines.json")
} else {
  Write-Warning "firebase.defines.json is missing: this build will have no push notifications."
}

robocopy $src $BuildDir /MIR /XD build .dart_tool .gradle .kotlin .idea ephemeral `
  /XF key.properties *.jks *.keystore local.properties /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }

# key.properties for the copy: same values, storeFile = absolute original path.
$props = Get-Content $keyProps -Encoding UTF8 | Where-Object { $_ -notmatch '^storeFile=' }
$storeFile = ((Get-Content $keyProps -Encoding UTF8 | Where-Object { $_ -match '^storeFile=' }) -replace '^storeFile=', '').Trim()
if (-not [IO.Path]::IsPathRooted($storeFile)) { $storeFile = Join-Path $src "android\app\$storeFile" }
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllLines("$BuildDir\android\key.properties", @($props + "storeFile=$($storeFile -replace '\\', '/')"), $utf8)
Copy-Item (Join-Path $src "android\local.properties") "$BuildDir\android\local.properties" -ErrorAction SilentlyContinue

Push-Location $BuildDir
try {
  & $Flutter pub get
  if ($ApkOnly -and $Arm64) {
    # 64-bit phones only, about half the size; 32-bit phones cannot install it.
    # (A split build: a plain one would still carry other CPUs' plugin libraries.)
    & $Flutter build apk --release --split-per-abi --target-platform android-arm64 `
      "--android-project-arg=force-version-code-ignoring-abi=true" @defines
    if ($LASTEXITCODE -ne 0) { throw "APK build failed" }
    return
  }
  if ($ApkOnly) {
    # One file for every phone: 32- and 64-bit ARM in the same APK.
    & $Flutter build apk --release --target-platform android-arm,android-arm64 @defines
    if ($LASTEXITCODE -ne 0) { throw "APK build failed" }
    return
  }
  # One APK per CPU type, all with the pubspec versionCode (no ABI offset), so
  # a device-tested APK never blocks the Play Store update of the same version.
  & $Flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 `
    "--android-project-arg=force-version-code-ignoring-abi=true" @defines
  if ($LASTEXITCODE -ne 0) { throw "APK build failed" }
  & $Flutter build appbundle --release @defines
  if ($LASTEXITCODE -ne 0) { throw "App Bundle build failed" }
} finally {
  Pop-Location
  # The copy's key.properties holds the keystore passwords: never leave it behind.
  Remove-Item "$BuildDir\android\key.properties" -ErrorAction SilentlyContinue
}
Write-Host "APKs: $BuildDir\build\app\outputs\flutter-apk\"
Write-Host "AAB : $BuildDir\build\app\outputs\bundle\release\app-release.aab"
