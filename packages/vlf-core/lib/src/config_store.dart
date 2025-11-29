import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'profile_manager.dart';

/// Управление чтением/записью `vlf_gui_config.json` и `profiles.json`.
class ConfigStore {
  final Directory baseDir;
  final String guiConfigFileName;
  final String profilesFileName;

  ConfigStore(
    this.baseDir, {
    this.guiConfigFileName = 'vlf_gui_config.json',
    this.profilesFileName = 'profiles.json',
  }) {
    if (!baseDir.existsSync()) {
      baseDir.createSync(recursive: true);
      _log('Storage directory created at ${baseDir.path}');
    }
    _log('baseDir=${baseDir.path}');
  }

  File get _guiConfigFile =>
      File(p.join(baseDir.path, guiConfigFileName));
  File get _profilesFile =>
      File(p.join(baseDir.path, profilesFileName));

  /// Load GUI config; returns a Map with defaults when файл отсутствует/битый.
  ///
  /// Дефолты:
  /// - ru_mode: false (ГЛОБАЛЬНЫЙ режим — весь трафик через VPN)
  /// - mode: 'tun' (TUN-режим)
  Map<String, dynamic> loadGuiConfig() {
    final path = _guiConfigFile.path;
    _log('Loading GUI config from $path');
    if (!_guiConfigFile.existsSync()) {
      _log('GUI config not found at $path, returning defaults');
      return _defaultGuiConfig();
    }
    try {
      final txt = _guiConfigFile.readAsStringSync();
      final j = json.decode(txt) as Map<String, dynamic>;
      return j;
    } catch (e) {
      _log('Failed to load GUI config at $path: $e');
      return _defaultGuiConfig();
    }
  }

  void saveGuiConfig(Map<String, dynamic> cfg) {
    try {
      final txt = JsonEncoder.withIndent('  ').convert(cfg);
      final path = _guiConfigFile.path;
      _log('Saving GUI config to $path');
      if (!_guiConfigFile.parent.existsSync()) {
        _guiConfigFile.parent.createSync(recursive: true);
        _log('Created GUI config directory ${_guiConfigFile.parent.path}');
      }
      _guiConfigFile.writeAsStringSync(txt);
      _log('GUI config saved to $path (${txt.length} chars)');
    } catch (e) {
      final path = _guiConfigFile.path;
      _log('Failed to save GUI config at $path: $e');
    }
  }

  List<Profile> loadProfiles() {
    final path = _profilesFile.path;
    _log('Loading profiles from $path');
    if (!_profilesFile.existsSync()) {
      _log('Profiles file missing at $path, returning empty list');
      return [];
    }
    try {
      final txt = _profilesFile.readAsStringSync();
      final j = json.decode(txt);
      if (j is List) {
        final profiles = j
            .map((e) => Profile.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _log('Loaded ${profiles.length} profiles from $path');
        return profiles;
      }
    } catch (e) {
      _log('Loading profiles failed at $path: $e');
    }
    return [];
  }

  void saveProfiles(List<Profile> profiles) {
    try {
      final txt = JsonEncoder.withIndent(
        '  ',
      ).convert(profiles.map((p) => p.toJson()).toList());
      final path = _profilesFile.path;
      _log('Saving profiles to $path (count=${profiles.length})');
      if (!baseDir.existsSync()) {
        baseDir.createSync(recursive: true);
        _log('Re-created base directory at ${baseDir.path}');
      }
      if (!_profilesFile.parent.existsSync()) {
        _profilesFile.parent.createSync(recursive: true);
        _log('Created profiles directory ${_profilesFile.parent.path}');
      }
      _profilesFile.writeAsStringSync(txt);
      _log('Saved profiles to $path');
    } catch (e) {
      final path = _profilesFile.path;
      _log('Saving profiles failed at $path: $e');
    }
  }

  Map<String, dynamic> _defaultGuiConfig() {
    return {
      'profiles': [],
      'ru_mode': false,
      'mode': 'tun',
      'site_exclusions': [],
      'app_exclusions': [],
    };
  }

  void _log(String message) {
    print('VLF Profiles: $message');
  }
}
