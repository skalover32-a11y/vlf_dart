# Android Platform Implementation - Technical Summary

## Overview
Implemented full `AndroidPlatformRunner` to enable VPN functionality on Android using mihomo (Clash Meta) binary subprocess, matching the architecture of the existing `WindowsPlatformRunner`.

## Implementation Date
26 ноября 2025

## Changes Made

### 1. AndroidPlatformRunner (lib/platform/android_platform_runner.dart)
**Status:** Complete implementation (274 lines)

**Key Features:**
- Asset extraction: Loads `mihomo-android-arm64` binary from app assets
- Runtime deployment: Extracts binary to `${appDocumentsDir}/core/mihomo`
- Permission management: Executes `chmod +x` to make binary executable
- Process lifecycle: Full `Process.start()` with stdout/stderr monitoring
- Graceful shutdown: SIGTERM → 3s timeout → SIGKILL pattern
- Startup validation: 12-second timeout waiting for success markers in logs
- Config generation: Uses `buildClashConfig()` or `buildClashConfigProxy()` from vlf_core

**Implementation Pattern:**
```dart
// Extract binary once
await _ensureMihomoBinary(); // rootBundle.load → writeAsBytes → chmod +x

// Generate config.yaml
final yamlContent = await buildClashConfigProxy(vless, ...);
await cfgPath.writeAsString(yamlContent);

// Start mihomo subprocess
_proc = await Process.start(_binaryPath!, ['-f', cfgPath.path]);

// Monitor output
_stdoutSub = _proc!.stdout.listen((data) {
  _logger.append(utf8.decode(data, allowMalformed: true));
});
```

**Architecture Detection:**
- Currently hardcoded to `arm64` (most modern Android devices)
- TODO: Implement `_getDeviceAbi()` for multi-ABI support (arm32/x86)

### 2. Dependencies (pubspec.yaml)
**Added:**
- `path_provider: ^2.1.0` - For `getApplicationDocumentsDirectory()`

**Updated Assets:**
```yaml
assets:
  - assets/tray_icon.ico
  - assets/core/  # Mihomo binaries directory
```

### 3. Binary Distribution (assets/core/)
**Created Structure:**
```
assets/core/
├── README.md                           # Installation instructions
└── mihomo-android-arm64.placeholder    # Placeholder with download links
```

**Binary Source:** https://github.com/MetaCubeX/mihomo/releases
- File format: `mihomo-android-arm64-v*.gz` (gzip compressed)
- Expected size: ~10-20 MB uncompressed
- Must be extracted and renamed to `mihomo-android-arm64`

**Security:** Added to `.gitignore` (large binaries not committed to repo)

### 4. Platform Locator (lib/platform/platform_locator.dart)
**Updated:** Removed "(stub)" comment from error message - Android is now fully implemented

### 5. Build Verification
**Tested:**
- ✅ `flutter pub get` - Installed path_provider successfully
- ✅ `flutter build windows --debug` - Windows build still works
- ✅ `flutter analyze` - No errors in platform code (130 issues are in legacy test files)

**Not Yet Tested:**
- ⏳ `flutter build apk --release` - Requires mihomo binary to be placed
- ⏳ `flutter run -d android` - Requires binary + Android device/emulator

## Technical Details

### Binary Extraction Flow
1. **First Run Detection:** Checks if `_binaryPath` exists and file is on disk
2. **Asset Loading:** `rootBundle.load('assets/core/mihomo-android-arm64')`
3. **File Writing:** Creates `${appDir}/core/` directory, writes binary bytes
4. **Permission:** `Process.run('chmod', ['+x', binaryPath])`
5. **Caching:** Stores `_binaryPath` in memory to avoid re-extraction

### Process Management
**Start Sequence:**
1. Extract VLESS config from subscription URL
2. Ensure mihomo binary exists (extract if needed)
3. Generate `config.yaml` (PROXY or TUN mode)
4. Launch `Process.start(binaryPath, ['-f', configPath])`
5. Setup stdout/stderr stream listeners
6. Wait for startup confirmation (success patterns in logs)

**Stop Sequence:**
1. Set `_stopping = true` (suppress error logs)
2. Cancel stdout/stderr subscriptions
3. Send `SIGTERM` (graceful shutdown)
4. Wait 3 seconds for process exit
5. If still running, send `SIGKILL` (force)
6. Cleanup: nullify process reference, reset `_stopping`

**Success Patterns (logs):**
- `'start http'` - HTTP proxy listening
- `'start mixed'` - Mixed port (SOCKS + HTTP)
- `'start socks'` - SOCKS5 proxy listening
- `'RESTful API listening'` - API server started

**Failure Patterns:**
- `'fatal'`, `'panic'`, `'cannot'`, `'failed to'`

### VPN Modes
**PROXY Mode (Recommended for Android):**
- Uses `buildClashConfigProxy()` from vlf_core
- HTTP/SOCKS5 proxy on localhost
- No root required
- Apps must support proxy settings (or use system proxy)

**TUN Mode (Future):**
- Uses `buildClashConfig()` from vlf_core
- Requires Android VpnService API integration
- Full traffic interception (like VPN)
- TODO: Implement VpnService connection

### Routing Logic
Identical to Windows implementation:
- **GLOBAL mode (`ruMode=false`)**: All traffic → VPN except local/exclusions
- **RU mode (`ruMode=true`)**: Russian GeoIP → DIRECT, rest → VPN
- **Exclusions**: Domain-based (site list) + package-based (app list)

## Known Limitations

### 1. Single ABI Support
- Currently only `arm64-v8a` architecture supported
- TODO: Detect device ABI and load correct binary:
  - `mihomo-android-arm64` - arm64-v8a (64-bit ARM)
  - `mihomo-android-arm32` - armeabi-v7a (32-bit ARM)
  - `mihomo-android-x86_64` - x86_64
  - `mihomo-android-x86` - x86 32-bit

### 2. VpnService Integration
- Current implementation uses PROXY mode (apps must support proxies)
- TUN mode requires Android VpnService API:
  - Request VPN permission via `VpnService.prepare()`
  - Create VPN interface with `VpnService.Builder`
  - Route traffic through mihomo TUN interface
  - TODO: Add VpnService wrapper class

### 3. Binary Distribution
- Binaries not included in repo (large files)
- Developers must manually download from MetaCubeX releases
- Production apps should bundle binaries in APK
- TODO: Create automated download script or GitHub Actions workflow

### 4. Permissions
- No special permissions required for PROXY mode
- TUN mode will require:
  - `android.permission.INTERNET`
  - `android.permission.FOREGROUND_SERVICE`
  - `android.permission.POST_NOTIFICATIONS` (Android 13+)
  - VpnService system permission (user approval dialog)

## Testing Checklist

### Before First Test
- [ ] Download `mihomo-android-arm64` from MetaCubeX releases
- [ ] Extract gzip: `gunzip mihomo-android-arm64-v*.gz`
- [ ] Place in `assets/core/mihomo-android-arm64`
- [ ] Run `flutter pub get`

### Build Tests
- [ ] `flutter build apk --debug` - Debug APK with binary
- [ ] `flutter build apk --release` - Release APK (production)
- [ ] Verify APK size (should be ~50 MB with binary included)

### Runtime Tests
- [ ] Install on Android device/emulator
- [ ] Add VLESS subscription URL
- [ ] Start tunnel in PROXY mode
- [ ] Check logs for "start mixed" success message
- [ ] Verify mihomo process running: `ps | grep mihomo`
- [ ] Test connectivity via proxy (HTTP/SOCKS5 on localhost)
- [ ] Stop tunnel gracefully
- [ ] Verify process terminated

### Edge Cases
- [ ] Cold start (binary not extracted yet)
- [ ] Restart after crash (binary already exists)
- [ ] Low storage space (extraction fails)
- [ ] chmod failure (permission denied)
- [ ] mihomo startup timeout (12s limit)
- [ ] Network interruption during subscription fetch

## Next Steps

### Short-term (v1.0)
1. ✅ Implement AndroidPlatformRunner (DONE)
2. 🔄 Test on physical Android device (Pixel 6a)
3. 🔄 Verify proxy mode functionality
4. 🔄 Test exclusions (app packages + domains)
5. 🔄 Validate ru_mode switching

### Medium-term (v1.1)
1. Implement multi-ABI support (arm32/x86)
2. Add automated binary download script
3. Improve error messages (Russian translations)
4. Add network connectivity detection
5. Implement background service for persistent tunnel

### Long-term (v2.0)
1. VpnService API integration for TUN mode
2. Foreground service with notification
3. Auto-start on boot (optional)
4. Split tunneling UI (per-app VPN)
5. Connection statistics (bandwidth/latency)

## Related Documentation
- `MIGRATION.md` - Architecture history (sing-box → Clash Meta)
- `CONFIG.md` - Configuration format and routing rules
- `CRITICAL_FIX_DNS_TUN.md` - TUN mode DNS resolution fixes
- `USER_GUIDE_RULES_FIX.md` - User-facing rule priority documentation

## References
- Mihomo (Clash Meta): https://github.com/MetaCubeX/mihomo
- Android VpnService API: https://developer.android.com/reference/android/net/VpnService
- path_provider: https://pub.dev/packages/path_provider
- Process Management: https://api.dart.dev/stable/dart-io/Process-class.html

---
*Document version: 1.0*
*Last updated: 26 ноября 2025*
*Author: AI Assistant (GitHub Copilot)*
