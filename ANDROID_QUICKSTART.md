# Quick Start: Testing Android Implementation

## Prerequisites
1. Android device or emulator (arm64-v8a architecture)
2. Flutter SDK 3.x installed
3. Android SDK with API level 21+ (Android 5.0+)

## Setup Steps

### 1. Download Mihomo Binary
```bash
# Visit: https://github.com/MetaCubeX/mihomo/releases
# Download: mihomo-android-arm64-v*.gz (latest version)

# Extract (Linux/macOS):
gunzip mihomo-android-arm64-v*.gz
mv mihomo-android-arm64-v* mihomo-android-arm64

# Extract (Windows PowerShell):
# Use 7-Zip or WinRAR to extract .gz file
# Rename extracted file to: mihomo-android-arm64
```

### 2. Place Binary
```bash
# Copy binary to assets directory
cp mihomo-android-arm64 d:\vlf\vlf_dart\assets\core\

# Verify placement
ls d:\vlf\vlf_dart\assets\core\
# Should show: mihomo-android-arm64 (10-20 MB file)
```

### 3. Install Dependencies
```powershell
cd d:\vlf\vlf_dart
flutter pub get
```

### 4. Build APK
```powershell
# Debug build (faster, includes debugging symbols)
flutter build apk --debug

# Release build (optimized, smaller size)
flutter build apk --release

# Output location:
# build\app\outputs\flutter-apk\app-debug.apk
# build\app\outputs\flutter-apk\app-release.apk
```

### 5. Install on Device
```powershell
# Connect Android device via USB (enable USB debugging)
# OR start Android emulator

# Install debug APK
flutter install

# OR manually install
adb install build\app\outputs\flutter-apk\app-debug.apk
```

### 6. Test VPN Connection
1. Launch VLF VPN app on Android device
2. Add VLESS subscription URL (or scan QR code)
3. Select profile from list
4. Tap "Запустить туннель" (Start Tunnel)
5. Check logs for success message: "start mixed"
6. Verify mihomo process: `adb shell ps | grep mihomo`
7. Test connectivity (open browser, check IP)

## Quick Test Commands

### Run on Emulator
```powershell
# List available devices
flutter devices

# Run on Android emulator (hot reload enabled)
flutter run -d emulator-5554

# Run on specific device
flutter run -d <device-id>
```

### Debug Logs
```powershell
# View Android logcat (Flutter logs)
flutter logs

# View mihomo process logs (in-app log viewer)
# Check "Логи" section in VLF app UI

# ADB shell debugging
adb shell
ps | grep mihomo                    # Check if mihomo running
ls /data/data/com.example.vlf_dart/app_flutter/core/  # Verify binary extracted
cat /data/data/com.example.vlf_dart/app_flutter/config.yaml  # View config
```

### Kill Process (if stuck)
```powershell
# Find mihomo PID
adb shell ps | grep mihomo

# Kill process
adb shell kill -9 <PID>

# OR stop from app UI
# Tap "Остановить туннель" button
```

## Expected Results

### Successful Start
```
📱 Android VLESS: vless://uuid@server:port?...
📦 Extracting mihomo binary from assets...
📱 Device ABI: arm64
📂 Target path: /data/data/.../app_flutter/core/mihomo
✅ Binary made executable
✅ Mihomo binary extracted successfully
📝 Config written to .../config.yaml
🚀 Starting mihomo: .../mihomo -f .../config.yaml
time="..." level=info msg="Start initial provider default"
time="..." level=info msg="Mixed(http+socks) proxy listening at: 127.0.0.1:7890"
✅ Mihomo started successfully
```

### Common Errors

**Binary not found:**
```
❌ Failed to extract binary: Unable to load asset: assets/core/mihomo-android-arm64
```
→ Solution: Download and place binary in `assets/core/`

**Permission denied:**
```
⚠️ chmod failed: chmod: .../mihomo: Operation not permitted
```
→ Solution: Check Android storage permissions (should auto-fix on retry)

**Startup timeout:**
```
⏱️ Startup timeout (12s)
❌ Mihomo не запустился за 12 секунд
```
→ Solution: Check config.yaml syntax, verify VLESS URL validity

**Process crash:**
```
❌ Ошибка запуска mihomo: Process exited with code 1
```
→ Solution: Check logs for fatal errors, verify architecture (arm64)

## Performance Benchmarks

### Expected Metrics
- **APK size:** ~50 MB (with mihomo binary included)
- **First start:** 2-5 seconds (binary extraction)
- **Subsequent starts:** 1-2 seconds (binary cached)
- **Memory usage:** 30-50 MB (mihomo process)
- **Battery impact:** Low (no TUN polling, proxy mode)

### Comparison with Windows
| Feature | Windows | Android |
|---------|---------|---------|
| Binary size | 10 MB (mihomo.exe) | 12 MB (mihomo-android-arm64) |
| Startup time | 1-2s | 2-5s (first run), 1-2s (cached) |
| VPN mode | TUN + PROXY | PROXY (TUN requires VpnService) |
| Elevation | Admin required (TUN) | No root required |
| Tray icon | Yes | No (Android doesn't have system tray) |

## Troubleshooting

### Binary Architecture Mismatch
```bash
# Check device architecture
adb shell getprop ro.product.cpu.abi
# Output: arm64-v8a (supported)
#         armeabi-v7a (need arm32 binary)
#         x86_64 (need x86 binary)
```

### Storage Space
```bash
# Check free space
adb shell df -h
# Mihomo binary requires ~20 MB free space
```

### Network Connectivity
```bash
# Test VLESS server reachability
adb shell ping <server-ip>
adb shell nc -zv <server-ip> <port>
```

### Config Validation
```bash
# Pull config from device
adb pull /data/data/com.example.vlf_dart/app_flutter/config.yaml
adb pull /data/data/com.example.vlf_dart/app_flutter/config_debug.yaml

# Validate YAML syntax
# Use online validator or: python -c "import yaml; yaml.safe_load(open('config.yaml'))"
```

## Next Steps After Testing

1. **If working:** Test exclusions (apps + domains), ru_mode switching
2. **If issues:** Check ANDROID_IMPLEMENTATION.md for detailed troubleshooting
3. **Production:** Remove debug logging, optimize binary size
4. **Future:** Implement VpnService for TUN mode

---
*For detailed technical documentation, see: ANDROID_IMPLEMENTATION.md*
