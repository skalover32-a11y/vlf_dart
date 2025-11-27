import 'dart:async';
import 'dart:io';
import 'package:vlf_core/vlf_core.dart';

/// Configuration bundle for platform runner
class PlatformConfig {
  final String profileUrl;
  final Directory baseDir;
  final bool ruMode;
  final List<String> siteExclusions;
  final List<String> appExclusions;
  final VlfWorkMode workMode;

  const PlatformConfig({
    required this.profileUrl,
    required this.baseDir,
    required this.ruMode,
    required this.siteExclusions,
    required this.appExclusions,
    required this.workMode,
  });
}

/// Platform-agnostic interface for VPN tunnel management
abstract class PlatformRunner {
  /// Start VPN tunnel with given configuration
  Future<void> start(PlatformConfig config);

  /// Stop VPN tunnel
  Future<void> stop();

  /// Quick stop with minimal cleanup (for app exit)
  Future<void> quickStop();

  /// Check if tunnel is currently running
  bool get isRunning;

  /// Stream of log messages from the tunnel
  Stream<String> get logStream;

  /// Stream of status updates: 'running', 'stopped', 'error:<message>'
  Stream<String> get statusStream;

  /// Check admin/root privileges (platform-specific)
  Future<bool> isElevated();

  /// Restart app with elevated privileges (platform-specific)
  Future<void> relaunchElevated();

  /// Dispose resources
  Future<void> dispose();
}
