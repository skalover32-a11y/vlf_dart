import 'platform_runner.dart';
import 'windows/windows_platform_runner.dart';

/// Simple locator that keeps a single [PlatformRunner] instance for the UI.
class PlatformLocator {
  PlatformLocator._();

  static final PlatformRunner _runner = WindowsPlatformRunner();

  static PlatformRunner get runner => _runner;
}
