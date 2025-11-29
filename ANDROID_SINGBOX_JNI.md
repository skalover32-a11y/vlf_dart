# Android sing-box JNI launcher

This module replaces the previous ProcessBuilder approach with a native launcher that
spawns `sing-box` inside the VPN process and keeps the child attached to the tunnel
file descriptor exposed by `VpnService`.

## Key pieces

| Component | Path | Responsibility |
|-----------|------|----------------|
| Kotlin bridge | `android/app/src/main/kotlin/com/example/vlf_dart/SingboxNative.kt` | Loads `libvlf_singbox.so`, exposes `start/stop`, and fans-out native log/exit callbacks to Kotlin listeners. |
| VPN service | `android/app/src/main/kotlin/com/example/vlf_dart/VlfVpnService.kt` | Creates the TUN interface, resolves binary/config paths prepared by Flutter, and calls `SingboxNative.start(...)`. On shutdown (user stop, revoke, destroy) it calls `SingboxNative.stop()` and tears down the foreground service. |
| Flutter plugin | `android/app/src/main/kotlin/com/example/vlf_dart/VlfAndroidEngine.kt` | Provides EventChannels (`status`, `logs`) that forward service updates and native log lines back to Dart so the existing log panel keeps working. |
| JNI layer | `android/app/src/main/cpp/singbox_jni.cpp` | Uses `fork()+exec` to run `sing-box run -c <config>`, passes `ANDROID_TUN_FD` to the child, redirects stdout/stderr via a pipe, and sends each log line back to Kotlin through `SingboxNative.handleNativeLog`. Exit codes propagate via `handleNativeExit`. |
| Build glue | `android/app/src/main/cpp/CMakeLists.txt` + `android/app/build.gradle.kts` | Builds `libvlf_singbox.so` for the configured ABIs and packages it with the Flutter APK. |

## Lifecycle overview

1. Dart calls `AndroidPlatformRunner.start()`. It prepares the sing-box JSON, saves it under
   `/files/vlf_tunnel/config_singbox.json`, makes sure the binary exists under
   `/files/vlf_tunnel/core/sing-box`, and sends both paths to `VlfAndroidEngine`.
2. `VlfAndroidEngine.startTunnel()` starts `VlfVpnService` with those paths and registers
   status/log callbacks.
3. `VlfVpnService` builds the TUN interface. After `Builder.establish()` succeeds it calls
   `SingboxNative.start(binPath, configPath, tunFd)`. The native layer forks, redirects
   stdout/stderr, exports `ANDROID_TUN_FD=<fd>`, and runs `sing-box run -c <config>`.
4. Native stdout/stderr lines are logged via `VLF-SINGBOX` tag and sent back to Kotlin.
   The service forwards them through the log EventChannel so Flutter’s `Logger` stream
   receives the same data.
5. When the user stops the tunnel (or Android revokes VPN permission) the service calls
   `SingboxNative.stop()`. The JNI layer sends SIGTERM to the child, waits for it to exit,
   and notifies Kotlin via `handleNativeExit(0)`.
6. If `sing-box` crashes or exits unexpectedly, the JNI layer still reports the exit code.
   `VlfVpnService` translates this into `notifyStatus("error:...")` and shuts down the VPN.

## Notes for development

- The JNI layer currently injects `ANDROID_TUN_FD=<fd>` before launching `sing-box`. Keep
  this in sync with the sing-box CLI expectations if they change.
- Native logs appear both in Logcat (`tag=VLF-SINGBOX`) and in Flutter’s log panel.
- To rebuild just the Android shared library run `flutter build apk --release` (Gradle will
  trigger the `externalNativeBuild` step automatically).
- `SingboxNative` allows multiple log/exit listeners; `VlfVpnService` registers during
  `onCreate()` and unregisters in `onDestroy()` to avoid leaking references.
