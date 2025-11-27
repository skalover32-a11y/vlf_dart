import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Centralized path management for VLF configuration files
class VlfPaths {
  /// Base directory for VLF application data
  static Future<Directory> getVlfDirectory() async {
    final Directory appSupportDir;
    
    if (Platform.isAndroid || Platform.isIOS) {
      // Mobile: use getApplicationSupportDirectory()
      appSupportDir = await getApplicationSupportDirectory();
    } else {
      // Desktop: use current directory (legacy compatibility)
      appSupportDir = Directory.current;
    }
    
    final vlfDir = Directory(p.join(appSupportDir.path, 'vlf_tunnel'));
    if (!vlfDir.existsSync()) {
      vlfDir.createSync(recursive: true);
    }
    
    return vlfDir;
  }
  
  /// Get path to main config.yaml file
  static Future<String> getConfigPath() async {
    final dir = await getVlfDirectory();
    return p.join(dir.path, 'config.yaml');
  }
  
  /// Get path to debug config_debug.yaml file
  static Future<String> getDebugConfigPath() async {
    final dir = await getVlfDirectory();
    return p.join(dir.path, 'config_debug.yaml');
  }
  
  /// Get base directory path (for legacy compatibility)
  static Future<String> getBasePath() async {
    final dir = await getVlfDirectory();
    return dir.path;
  }
}
