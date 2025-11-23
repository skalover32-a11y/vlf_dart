import 'dart:async';
import 'dart:io';

import '../config_store.dart';
import '../profile_manager.dart';
import '../exclusions.dart';
import '../singbox_manager.dart';
import '../logger.dart';
import 'package:flutter/foundation.dart';

/// Фасад, объединяющий core-модули для UI.
class VlfCore {
  final ConfigStore configStore;
  final ProfileManager profileManager;
  final Exclusions exclusions;
  final SingboxManager singboxManager;
  final Logger logger;

  bool ruMode;
  // ValueNotifier для подписки UI на состояние подключения
  final ValueNotifier<bool> isConnected;

  VlfCore._(
    this.configStore,
    this.profileManager,
    this.exclusions,
    this.singboxManager,
    this.logger,
    this.ruMode,
    this.isConnected,
  );

  /// Инициализация фасада. `baseDir` — директория рядом с которой лежат
  /// `vlf_gui_config.json`, `profiles.json` и `sing-box.exe`.
  static Future<VlfCore> init({required String baseDir}) async {
    final dir = Directory(baseDir);
    final store = ConfigStore(dir);

    final guiCfg = store.loadGuiConfig();

    // profiles: ConfigStore.loadProfiles уже возвращает List<Profile>
    final profileMgr = ProfileManager();
    final loadedProfiles = store.loadProfiles();
    profileMgr.profiles = List<Profile>.from(loadedProfiles);

    final excl = Exclusions.fromJson({
      'site_exclusions': guiCfg['site_exclusions'] ?? [],
      'app_exclusions': guiCfg['app_exclusions'] ?? [],
    });

    final singMgr = SingboxManager();

    // logger: используем singboxManager.logger для единого потока логов
    final coreLogger = singMgr.logger;

    final core = VlfCore._(store, profileMgr, excl, singMgr, coreLogger, guiCfg['ru_mode'] == true, singMgr.isRunningNotifier);

    return core;
  }

  // --- Config / Profiles helpers ---
  List<Profile> getProfiles() => profileManager.profiles;

  void addProfile(Profile p) {
    profileManager.add(p);
    _saveAll();
  }

  void editProfile(int idx, Profile p) {
    profileManager.editAt(idx, p);
    _saveAll();
  }

  void removeProfile(int idx) {
    profileManager.removeAt(idx);
    _saveAll();
  }

  // --- Exclusions ---
  Exclusions getExclusions() => exclusions;

  void addSiteExclusion(String domain) {
    exclusions.addSite(domain);
    _saveAll();
  }

  void removeSiteExclusion(int idx) {
    exclusions.removeSite(idx);
    _saveAll();
  }

  void addAppExclusion(String procName) {
    exclusions.addApp(procName);
    _saveAll();
  }

  void removeAppExclusion(int idx) {
    exclusions.removeApp(idx);
    _saveAll();
  }

  // --- RU mode ---
  void setRuMode(bool enabled) {
    ruMode = enabled;
    _saveAll();
  }

  // --- Singbox control ---
  /// Start sing-box using profile at `profileIdx` (must be valid index in profiles list).
  Future<void> startTunnel(int profileIdx) async {
    if (profileIdx < 0 || profileIdx >= profileManager.profiles.length) {
      throw RangeError('profileIdx out of range');
    }

    final p = profileManager.profiles[profileIdx];
    await singboxManager.start(
      p.url,
      Directory(configStore.baseDir.path),
      ruMode: ruMode,
      siteExcl: exclusions.siteExclusions,
      appExcl: exclusions.appExclusions,
    );
  }

  Future<void> stopTunnel() async {
    await singboxManager.stop();
  }

  Future<String> getIp() => singboxManager.updateIp();

  /// Convenience: connect by Profile object (will add profile if not present)
  Future<void> connectWithProfile(Profile p) async {
    var idx = profileManager.profiles.indexWhere((e) => e.url == p.url && e.name == p.name);
    if (idx == -1) {
      addProfile(p);
      idx = profileManager.profiles.length - 1;
    }
    await startTunnel(idx);
  }

  Future<void> disconnect() async {
    await stopTunnel();
  }

  Stream<String> get logStream => logger.stream;

  int get logLines => logger.lines;

  bool get isRunning => singboxManager.isRunning;

  // Save current config and profiles to disk
  void _saveAll() {
    final cfg = {
      'profiles': profileManager.toJson()['profiles'],
      'ru_mode': ruMode,
      'site_exclusions': exclusions.siteExclusions,
      'app_exclusions': exclusions.appExclusions,
    };
    configStore.saveGuiConfig(cfg);
    configStore.saveProfiles(profileManager.profiles);
  }
}
