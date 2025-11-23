import 'dart:convert';
import 'dart:io';

import 'profile_manager.dart';
import 'exclusions.dart';

/// Управление чтением/записью `vlf_gui_config.json` и `profiles.json`.
class ConfigStore {
  final Directory baseDir;
  final String guiConfigFileName;
  final String profilesFileName;

  ConfigStore(this.baseDir,
      {this.guiConfigFileName = 'vlf_gui_config.json', this.profilesFileName = 'profiles.json'});

  File get _guiConfigFile => File('${baseDir.path}${Platform.pathSeparator}$guiConfigFileName');
  File get _profilesFile => File('${baseDir.path}${Platform.pathSeparator}$profilesFileName');

  /// Load GUI config; returns a Map with defaults when файл отсутствует/битый.
  Map<String, dynamic> loadGuiConfig() {
    if (!_guiConfigFile.existsSync()) {
      return {
        'profiles': [],
        'ru_mode': true,
        'site_exclusions': [],
        'app_exclusions': []
      };
    }
    try {
      final txt = _guiConfigFile.readAsStringSync();
      final j = json.decode(txt) as Map<String, dynamic>;
      return j;
    } catch (_) {
      return {
        'profiles': [],
        'ru_mode': true,
        'site_exclusions': [],
        'app_exclusions': []
      };
    }
  }

  void saveGuiConfig(Map<String, dynamic> cfg) {
    try {
      final txt = JsonEncoder.withIndent('  ').convert(cfg);
      _guiConfigFile.writeAsStringSync(txt);
    } catch (_) {
      // ignore write errors for now
    }
  }

  List<Profile> loadProfiles() {
    if (!_profilesFile.existsSync()) return [];
    try {
      final txt = _profilesFile.readAsStringSync();
      final j = json.decode(txt);
      if (j is List) {
        return j.map((e) => Profile.fromJson(Map<String, dynamic>.from(e))).toList();
      }
    } catch (_) {}
    return [];
  }

  void saveProfiles(List<Profile> profiles) {
    try {
      final txt = JsonEncoder.withIndent('  ').convert(profiles.map((p) => p.toJson()).toList());
      _profilesFile.writeAsStringSync(txt);
    } catch (_) {}
  }
}
