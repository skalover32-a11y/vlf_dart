import 'dart:async';
import 'dart:io';

import 'package:vlf_core/vlf_core.dart' show RoutingRulesPlan, VlfWorkMode;

/// Encapsulates everything the runner needs to (re)generate configs.
class PlatformRunnerConfig {
  final String profileUrl;
  final Directory baseDir;
  final bool ruMode;
  final List<String> siteExclusions;
  final List<String> appExclusions;
  final VlfWorkMode workMode;
  final RoutingRulesPlan? routingPlan;

  const PlatformRunnerConfig({
    required this.profileUrl,
    required this.baseDir,
    required this.ruMode,
    required this.siteExclusions,
    required this.appExclusions,
    required this.workMode,
    this.routingPlan,
  });
}

/// Platform-specific controller for the Clash Meta (mihomo) runtime.
///
/// Concrete implementations (Windows, macOS, etc.) live outside of this file
/// and encapsulate process management plus config generation via `vlf_core`.
abstract class PlatformRunner {
  /// Start or restart the tunnel using the supplied [config].
  Future<void> startTunnel(PlatformRunnerConfig config);

  /// Stop the running tunnel if any.
  Future<void> stopTunnel();

  /// Whether the underlying mihomo process is alive.
  bool get isRunning;

  /// Live log feed coming from the subprocess.
  Stream<String> get logs;

  /// Trigger a config reload (stop/start by default).
  Future<void> reloadConfig(PlatformRunnerConfig config);

  /// Dispose all resources owned by the runner.
  Future<void> dispose();
}
