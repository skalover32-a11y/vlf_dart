import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Manages mihomo binary extraction and permissions across platforms
class MihomoBinary {
  static String? _cachedPath;

  /// Ensures mihomo binary is available and executable.
  /// 
  /// On Android: extracts from assets/core/mihomo-android-arm64 to app directory,
  /// sets chmod 700 for execution permissions.
  /// 
  /// On Windows: returns path to mihomo.exe in the base directory.
  /// 
  /// Returns the full path to the executable binary.
  static Future<String> ensureMihomoBinary({required Directory baseDir}) async {
    // Return cached path if already extracted
    if (_cachedPath != null && File(_cachedPath!).existsSync()) {
      return _cachedPath!;
    }

    if (Platform.isAndroid) {
      return await _extractAndroidBinary();
    } else if (Platform.isWindows) {
      return _getWindowsBinaryPath(baseDir);
    } else {
      throw UnsupportedError(
        'Platform ${Platform.operatingSystem} not supported for mihomo binary',
      );
    }
  }

  /// Extract mihomo binary from assets on Android
  static Future<String> _extractAndroidBinary() async {
    // Get app directory
    final appDir = await getApplicationSupportDirectory();
    final coreDir = Directory(p.join(appDir.path, 'core'));
    if (!coreDir.existsSync()) {
      coreDir.createSync(recursive: true);
    }

    final targetPath = p.join(coreDir.path, 'mihomo');
    final targetFile = File(targetPath);

    // Check if already extracted and executable
    if (targetFile.existsSync()) {
      // Verify permissions
      try {
        final statResult = await Process.run('stat', ['-c', '%a', targetPath]);
        if (statResult.exitCode == 0 && statResult.stdout.toString().trim().startsWith('7')) {
          _cachedPath = targetPath;
          return targetPath;
        }
      } catch (_) {
        // stat failed, re-extract
      }
    }

    // Extract binary from assets
    final abi = _getDeviceAbi();
    final assetPath = 'assets/core/mihomo-android-$abi';

    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      await targetFile.writeAsBytes(bytes, flush: true);

      // Make executable with chmod 700 (rwx------)
      final chmodResult = await Process.run('chmod', ['700', targetPath]);
      
      if (chmodResult.exitCode != 0) {
        throw Exception('chmod failed (exit ${chmodResult.exitCode}): ${chmodResult.stderr}');
      }

      _cachedPath = targetPath;
      return targetPath;
    } catch (e) {
      throw Exception('Failed to extract mihomo binary: $e');
    }
  }

  /// Get mihomo.exe path on Windows
  static String _getWindowsBinaryPath(Directory baseDir) {
    final exePath = p.join(baseDir.path, 'mihomo.exe');
    final exeFile = File(exePath);

    if (!exeFile.existsSync()) {
      throw FileSystemException('mihomo.exe not found', exePath);
    }

    _cachedPath = exePath;
    return exePath;
  }

  /// Detect device ABI architecture on Android
  static String _getDeviceAbi() {
    // Default to arm64 (most modern Android devices)
    // TODO: Implement proper ABI detection via platform channel
    return 'arm64';
  }

  /// Clear cached binary path (useful for testing)
  static void clearCache() {
    _cachedPath = null;
  }
}
