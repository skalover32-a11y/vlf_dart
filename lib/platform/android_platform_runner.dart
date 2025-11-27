import 'dart:async';

import 'package:vlf_core/vlf_core.dart';
import 'platform_runner.dart';

/// Android stub implementation (not yet implemented)
class AndroidPlatformRunner implements PlatformRunner {
  final Logger _logger = Logger();
  bool _isRunning = false;

  @override
  Stream<String> get logStream => _logger.stream;

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> start(PlatformConfig config) async {
    _logger.append('🤖 Android runner: VPN start requested\n');
    _logger.append('Profile: ${config.profileUrl.substring(0, 20)}...\n');
    _logger.append('Mode: ${config.workMode.displayName} / ${config.ruMode ? "RU" : "GLOBAL"}\n');
    _logger.append('⚠️  Android VPN implementation not yet available\n');
    _logger.append('📱 Will use VpnService API in future release\n');
    
    // Simulate successful "start" for UI testing
    _isRunning = true;
    
    // Fake connection after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (_isRunning) {
        _logger.append('✓ Mock tunnel established (Android stub)\n');
      }
    });
  }

  @override
  Future<void> stop() async {
    _logger.append('🤖 Android runner: VPN stop requested\n');
    _isRunning = false;
    _logger.append('✓ Mock tunnel stopped\n');
  }

  @override
  Future<void> quickStop() async {
    _isRunning = false;
  }

  @override
  Future<bool> isElevated() async {
    // Android apps don't need root for VpnService
    return true;
  }

  @override
  Future<void> relaunchElevated() async {
    throw UnsupportedError('Android apps use VpnService, no elevation needed');
  }

  @override
  Future<void> dispose() async {
    await stop();
    _logger.dispose();
  }
}
