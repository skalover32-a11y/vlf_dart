import 'dart:io';
import 'platform_runner.dart';
import 'android_platform_runner.dart';
import 'dart:io' show Platform;
import 'windows_platform_runner.dart';

/// Factory to create platform-specific runner based on current platform
PlatformRunner createPlatformRunner() {
  if (Platform.isWindows) {
    return WindowsPlatformRunner();
  } else if (Platform.isAndroid) {
    return AndroidPlatformRunner();
  } else {
    throw UnsupportedError(
      'Platform ${Platform.operatingSystem} not yet supported. '
      'Currently only Windows and Android are available.',
    );
  }
}
