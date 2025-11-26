# VLF Tunnel - AI Agent Guide

## Project Overview
Flutter VPN client for Windows managing VLESS connections via **Clash Meta (mihomo)** backend. Supports subscription URLs, TUN tunneling, Russian traffic routing modes, and domain/process exclusions.

## Architecture & Data Flow

### Core Components
- **`VlfCore`** (`lib/core/vlf_core.dart`): Main facade exposing `ConfigStore`, `ProfileManager`, `Exclusions`, `ClashManager`, and `Logger` to UI
- **`ClashManager`** (`lib/clash_manager.dart`): Manages `mihomo.exe` subprocess lifecycle, generates `config.yaml`, monitors stdout/stderr
- **`ConfigStore`** (`lib/config_store.dart`): JSON persistence for `vlf_gui_config.json` and `profiles.json`
- **`ProfileManager`** (`lib/profile_manager.dart`): In-memory profile list with CRUD operations
- **UI**: `lib/ui/home_screen.dart` + modular widgets in `lib/ui/widgets/`

### Configuration Pipeline
1. User adds VLESS subscription URL (or scans QR code via `qr_profile_loader.dart`)
2. `extractVlessFromAny()` in `subscription_decoder.dart` parses base64/plaintext to extract `vless://` URL
3. `buildClashConfig()` in `clash_config.dart` generates YAML configuration with:
   - VLESS outbound proxy (supports REALITY TLS)
   - TUN inbound with auto-routing
   - Rule-based routing: ru_mode GeoIP, domain exclusions, process exclusions
4. `ClashManager.start()` writes `config.yaml` and launches `mihomo.exe -f config.yaml`

### State Management
- **Profiles**: Stored in `vlf_gui_config.json` with fields: `name`, `url`, `ptype`, `address`, `remark`
- **Runtime config**: `config.yaml` generated on-the-fly (also `config_debug.yaml` for inspection)
- **Connection state**: `ClashManager.isRunningNotifier` (ValueNotifier<bool>) for UI reactivity
- **Current profile**: `VlfCore.currentProfileIndex` (ValueNotifier<int?>)

### Routing Modes
- **GLOBAL (ru_mode=false)**: All traffic → VPN, except local/exclusions (default)
- **RU-MODE (ru_mode=true)**: Russian GeoIP → DIRECT, rest → VPN (for banking/local services)

## Critical Workflows

### Building Production Binary
```powershell
# From project root
pwsh .\tools\build_and_package.ps1 -ProjectRoot (Get-Location).Path
# Optional: add -Zip to create archive
pwsh .\tools\build_and_package.ps1 -ProjectRoot (Get-Location).Path -Zip
```
**What it does:**
1. Runs `flutter pub get`
2. Executes `flutter build windows --release`
3. Copies output from `build\windows\x64\runner\Release` to `release\windows_x64_release`
4. Renames `vlf_dart.exe` → `VLF_VPN.exe`
5. Copies `mihomo.exe` and `wintun.dll` from project root (or fallback directories)
6. Optionally creates `release\vlf_windows_x64_release.zip`

### Development Run
```powershell
flutter run -d windows
# Or for release mode performance testing:
flutter run -d windows --release
```
**Requirements:** `mihomo.exe` and `wintun.dll` must be in project root (same dir as `pubspec.yaml`)

### Configuration Files
- **`vlf_gui_config.json`**: User profiles, ru_mode, exclusions (persisted to disk)
- **`config.yaml`**: Generated Clash config (runtime, ephemeral)
- **`config_debug.yaml`**: Debug copy of config for inspection
- **`profiles.json`**: Legacy/alternative profile storage (less common)

## Project-Specific Patterns

### Facade Pattern (VlfCore)
UI never directly accesses `ClashManager`, `ConfigStore`, etc. All operations go through `VlfCore`:
```dart
// Good:
await core.startTunnel(profileIndex);
core.setRuMode(true);
core.addProfile(profile);

// Bad (direct access):
await core.singboxManager.start(...); // Skip facade breaks encapsulation
```

### ValueNotifier-Heavy UI
State changes propagate via ValueNotifier for reactive updates:
```dart
ValueListenableBuilder<bool>(
  valueListenable: core.isConnected,
  builder: (context, isConnected, _) => Text(isConnected ? 'Connected' : 'Disconnected'),
)
```

### Threading & Async Safety
- **Process management**: Runs in background, UI updates via `logger.append()` (synchronous)
- **Stream processing**: stdout/stderr → UTF-8 decode → logger → UI listens on `logStream`
- **No explicit locks**: Single-threaded Dart event loop, async/await for coordination

### Subscription Parsing
`extractVlessFromAny()` handles:
- Direct `vless://` URLs
- HTTP(S) subscription endpoints returning base64
- Base64-encoded plaintext containing `vless://`
- Extracts server/port/uuid/flow/security/fingerprint/sni from URL query params

### Startup Detection
`ClashManager.start()` waits for log markers (12s timeout):
```dart
// Success indicators:
'start http', 'start mixed', 'start tun', 'tun mode enabled'

// Failure indicators:
'fatal', 'panic', 'cannot', 'failed to'
```

### Window Sizing (Desktop)
`main.dart` uses `window_manager` package to set fixed 480x980 window (non-resizable). UI scales mobile design (430px width) via `AppWindowWrapper` transform.

## Common Pitfalls

### Clash Process Lifecycle
1. **Graceful shutdown sequence**: SIGINT → wait 3s → SIGKILL
2. Must set `_stopping = true` before kill to suppress error logs
3. Cancel stream subscriptions BEFORE nulling `_proc` to avoid leaks
4. Always check `_proc != null` before operations

### Config Generation Timing
- `config.yaml` generated **only on `ClashManager.start()`**, not ahead of time
- `writeConfigForProfileIndex()` is a no-op (config not needed until start)
- Debug configs written to `config_debug.yaml` for manual inspection

### Binary Dependencies
- **`mihomo.exe`**: Clash Meta binary (NOT sing-box)
- **`wintun.dll`**: Windows TUN/TAP driver (required for TUN mode)
- Both must be in same directory as app executable

### PowerShell for IP/Location Queries
Uses PowerShell `Invoke-WebRequest` to ensure traffic routes through TUN interface:
```dart
// Windows-specific bypass for Dart HttpClient (might skip TUN)
Process.run('powershell', ['-Command', 'Invoke-WebRequest ...']);
```

### ru_mode Confusion
- **false = GLOBAL** (все через VPN) — это дефолт
- **true = RU-MODE** (российский трафик напрямую)
- Смена режима триггерит `_restartIfRunning()` для применения

## Key Files by Concern
- **Architecture**: `lib/core/vlf_core.dart` (facade), `lib/clash_manager.dart` (process manager)
- **Config generation**: `lib/clash_config.dart` (YAML builder)
- **Subscription parsing**: `lib/subscription_decoder.dart`
- **UI entry point**: `lib/main.dart`, `lib/ui/home_screen.dart`
- **Build automation**: `tools/build_and_package.ps1`
- **Window setup**: `lib/main.dart` (window_manager integration)

## Dependencies
- **Runtime**: Flutter 3.x, Dart SDK 3.9.2+
- **Packages**: `window_manager`, `window_size`, `http`, `file_picker`, `image`, `zxing2`
- **Bundled**: Clash Meta (mihomo.exe), wintun.dll

## Testing & Debugging
- **No unit tests present** — manual testing via UI
- **Log inspection**: Check `config_debug.yaml` for generated config
- **Process monitoring**: Watch for "start tun" in logs (confirms TUN activation)
- **IP verification**: Use in-app IP display (fetches via ipify.org)
- **Common error**: "mihomo.exe не найден" → check binary is in correct directory

## Документация по изменениям
См. также: `MIGRATION.md`, `CONFIG.md`, `CRITICAL_FIX_DNS_TUN.md` для истории архитектурных решений и миграций.

---
*Обновлено: 26.11.2025. Обновите при изменении ClashManager API, конфигурационного формата или процесса сборки.*
