import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../clash_config.dart';
import '../logger.dart';
import '../subscription_decoder.dart';
import '../vlf_work_mode.dart';

part 'platform_runner_windows.dart';
part 'platform_runner_stub.dart';

/// Configuration bundle passed into the platform runner.
class VlfConfig {
  final String profileUrl;
  final Directory baseDir;
  final bool ruMode;
  final List<String> siteExclusions;
  final List<String> appExclusions;
  final VlfWorkMode workMode;
  final RoutingRulesPlan? routingPlan;

  const VlfConfig({
    required this.profileUrl,
    required this.baseDir,
    required this.ruMode,
    required this.siteExclusions,
    required this.appExclusions,
    required this.workMode,
    this.routingPlan,
  });
}

/// Platform abstraction around mihomo subprocess handling.
abstract class PlatformRunner {
  Future<void> start(VlfConfig config);
  Future<void> stop();
  Stream<String> get logs;
  Future<bool> get isRunning;
  Future<void> restart(VlfConfig config);
  Future<void> dispose();
}

PlatformRunner createPlatformRunner() {
  if (Platform.isWindows) {
    return PlatformRunnerWindows();
  }
  return PlatformRunnerStub();
}