# Mihomo Android Binaries

## Required Files

Place the following mihomo binaries in this directory:

- `mihomo-android-arm64` - For arm64-v8a devices (most modern Android phones)
- `mihomo-android-arm32` - For armeabi-v7a devices (older 32-bit ARM)
- `mihomo-android-x86_64` - For x86_64 emulators/devices
- `mihomo-android-x86` - For x86 32-bit emulators

## Where to Get Mihomo Binaries

Download from official Clash Meta (mihomo) releases:
https://github.com/MetaCubeX/mihomo/releases

Look for Android builds (e.g., `mihomo-android-arm64-v1.18.0.gz`)

## Installation Steps

1. Download the appropriate `.gz` archive for each architecture
2. Extract the binary: `gunzip mihomo-android-arm64-v1.18.0.gz`
3. Rename to remove version: `mv mihomo-android-arm64-v1.18.0 mihomo-android-arm64`
4. Place in this directory (`assets/core/`)
5. Ensure file is executable: `chmod +x mihomo-android-arm64`

## Current Implementation

Currently, `AndroidPlatformRunner` expects `mihomo-android-arm64` only.
Multi-ABI support (arm32/x86) will be added in future versions.

## Verification

After placing binaries, run:
```powershell
flutter pub get
flutter build apk --release
```

Binary will be extracted to app's documents directory at runtime and made executable.
