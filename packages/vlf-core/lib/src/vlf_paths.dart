import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Centralized path management for VLF configuration files
class VlfPaths {
  /// Base directory (application support directory on every platform)
  static Future<Directory> getBaseDir() async {
    return _resolveBaseDirectory();
  }

  /// Core directory that hosts configs/binaries (…/vlf_tunnel)
  static Future<Directory> getCoreDir() async {
    final base = await _resolveBaseDirectory();
    final core = Directory(p.join(base.path, 'vlf_tunnel'));
    await _ensureDirectory(core);
    _logSuspiciousPath('coreDir', core.path);
    return core;
  }

  /// Explicit helper for callers that want tightened validation
  static Future<Directory> getSafeCoreDir() => getCoreDir();

  /// Backward-compatible alias for legacy code
  static Future<Directory> getVlfDirectory() => getCoreDir();

  /// Path to primary config.yaml
  static Future<String> getConfigPath() async {
    final dir = await getCoreDir();
    final path = p.join(dir.path, 'config.yaml');
    _logSuspiciousPath('configYaml', path);
    return path;
  }

  /// Path to config_debug.yaml
  static Future<String> getDebugConfigPath() async {
    final dir = await getCoreDir();
    final path = p.join(dir.path, 'config_debug.yaml');
    _logSuspiciousPath('configDebug', path);
    return path;
  }

  /// Sing-box JSON config path
  static Future<String> getSingboxConfigPath() async {
    final dir = await getCoreDir();
    final path = p.join(dir.path, 'config_singbox.json');
    _logSuspiciousPath('singboxConfig', path);
    return path;
  }

  /// Get base directory path (legacy string helper)
  static Future<String> getBasePath() async {
    final dir = await getCoreDir();
    return dir.path;
  }

  static void _logSuspiciousPath(String label, String path) {
    if ((Platform.isAndroid || Platform.isIOS) && path.startsWith('/') && !path.contains('com.')) {
      stderr.writeln('VlfPaths warning: $label path looks suspicious: $path');
    }
  }

  static Future<Directory> _resolveBaseDirectory() async {
    Directory? candidate;
    dynamic lastError;
    for (final resolver in [
      getApplicationSupportDirectory,
      getApplicationDocumentsDirectory,
      getTemporaryDirectory,
    ]) {
      try {
        candidate = await resolver();
        break;
      } catch (e) {
        lastError = e;
      }
    }
    candidate ??= Directory.current;
    if (_isInvalidPath(candidate.path)) {
      stderr.writeln('VlfPaths warning: baseDir resolved to "${candidate.path}" (lastError=$lastError)');
      if (Platform.isAndroid) {
        final pkg = Platform.environment['ANDROID_APP_PACKAGE'] ?? 'com.example.vlf_dart';
        candidate = Directory('/data/user/0/$pkg/files');
      } else {
        candidate = Directory.systemTemp;
      }
    }
    await _ensureDirectory(candidate);
    return candidate;
  }

  static bool _isInvalidPath(String path) {
    if (path.isEmpty) return true;
    final normalized = path.replaceAll('\\', '/');
    return normalized == '/' || normalized == '.';
  }

  static Future<void> _ensureDirectory(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }
}
