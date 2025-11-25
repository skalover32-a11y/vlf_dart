param(
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$Zip
)

Write-Host "Project root: $ProjectRoot"

# Ensure we run from project root
Set-Location -LiteralPath $ProjectRoot

Write-Host "Running: flutter pub get"
flutter pub get

Write-Host "Building Flutter Windows release..."
flutter build windows --release

$buildOutput = Join-Path $ProjectRoot 'build\\windows\\x64\\runner\\Release'
$releaseDir = Join-Path $ProjectRoot 'release\\windows_x64_release'

if (-not (Test-Path -LiteralPath $buildOutput)) {
    Write-Error "Build output not found: $buildOutput"
    exit 1
}

if (-not (Test-Path -LiteralPath $releaseDir)) {
    New-Item -ItemType Directory -Path $releaseDir | Out-Null
}

Write-Host "Copying build output to: $releaseDir"
Copy-Item -Path (Join-Path $buildOutput '*') -Destination $releaseDir -Recurse -Force

# Rename the built exe to the user-facing name `VLF_VPN.exe` in both build output and release folder
$originalExe = Join-Path $buildOutput 'vlf_dart.exe'
$newExeName = 'VLF_VPN.exe'
$newExeInBuild = Join-Path $buildOutput $newExeName
if (Test-Path -LiteralPath $originalExe) {
    try {
        if (Test-Path -LiteralPath $newExeInBuild) { Remove-Item -LiteralPath $newExeInBuild -Force }
        Rename-Item -Path $originalExe -NewName $newExeName -ErrorAction Stop
        Write-Host "Renamed $originalExe -> $newExeInBuild"
    } catch {
        Write-Warning "Failed to rename exe in build folder: $_"
    }
}
# also rename in release folder if present
$origInRelease = Join-Path $releaseDir 'vlf_dart.exe'
$newInRelease = Join-Path $releaseDir $newExeName
if (Test-Path -LiteralPath $origInRelease) {
    try {
        if (Test-Path -LiteralPath $newInRelease) { Remove-Item -LiteralPath $newInRelease -Force }
        Rename-Item -Path $origInRelease -NewName $newExeName -ErrorAction Stop
        Write-Host "Renamed $origInRelease -> $newInRelease"
    } catch {
        Write-Warning "Failed to rename exe in release folder: $_"
    }
}

$filesToInclude = @('mihomo.exe','wintun.dll')

# Copy mihomo.exe and wintun.dll from project root (where they should be placed)
foreach ($file in $filesToInclude) {
    $src = Join-Path $ProjectRoot $file
    if (Test-Path -LiteralPath $src) {
        Write-Host "Copying $src -> $releaseDir"
        Copy-Item -Path $src -Destination $releaseDir -Force
        Write-Host "Also copying $src -> $buildOutput"
        Copy-Item -Path $src -Destination $buildOutput -Force
    } else {
        Write-Warning "Required file not found: $src"
    }
}

# Also check candidate directories for backwards compatibility
$candidateDirs = @(
    "$ProjectRoot\..\client\_internal",
    "$ProjectRoot\..\client",
    "$ProjectRoot\..\client\_internal\pyzbar"
)

foreach ($dir in $candidateDirs) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($file in $filesToInclude) {
        $src = Join-Path $dir $file
        if (Test-Path -LiteralPath $src) {
            Write-Host "Copying $src -> $releaseDir"
            Copy-Item -Path $src -Destination $releaseDir -Force
            Write-Host "Also copying $src -> $buildOutput"
            Copy-Item -Path $src -Destination $buildOutput -Force
        }
    }
}

Write-Host "Files in release folder:"
Get-ChildItem -Path $releaseDir | ForEach-Object { Write-Host " - $($_.Name)" }

if ($Zip) {
    $zipPath = Join-Path (Join-Path $ProjectRoot 'release') 'vlf_windows_x64_release.zip'
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Write-Host "Creating zip: $zipPath"
    Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zipPath -Force
}

Write-Host "Done. Release: $releaseDir"
