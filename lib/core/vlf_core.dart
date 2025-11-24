import 'dart:async';
import 'dart:io';
import 'dart:convert';

import '../config_store.dart';
import '../profile_manager.dart';
import '../exclusions.dart';
import '../singbox_manager.dart';
import '../logger.dart';
import 'package:flutter/foundation.dart';
import '../subscription_decoder.dart';
import '../singbox_config_clean.dart';

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

  /// Индекс текущего выбранного профиля в `profileManager.profiles`.
  final ValueNotifier<int?> currentProfileIndex = ValueNotifier<int?>(null);

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

    final core = VlfCore._(
      store,
      profileMgr,
      excl,
      singMgr,
      coreLogger,
      guiCfg['ru_mode'] == true,
      singMgr.isRunningNotifier,
    );

    // set default current profile index
    if (profileMgr.profiles.isNotEmpty) {
      core.currentProfileIndex.value = 0;
    }

    return core;
  }

  // --- Config / Profiles helpers ---
  List<Profile> getProfiles() => profileManager.profiles;

  void addProfile(Profile p) {
    profileManager.add(p);
    _saveAll();
    // Make newly added profile the current selection.
    currentProfileIndex.value = profileManager.profiles.length - 1;
  }

  Profile? getCurrentProfile() {
    final idx = currentProfileIndex.value;
    if (idx == null) return null;
    if (idx < 0 || idx >= profileManager.profiles.length) return null;
    return profileManager.profiles[idx];
  }

  void setCurrentProfileByIndex(int? idx) {
    if (idx == null) {
      currentProfileIndex.value = null;
      return;
    }
    if (idx < 0 || idx >= profileManager.profiles.length) return;
    currentProfileIndex.value = idx;
  }

  /// Parse arbitrary text (clipboard contents or user input) and add profile.
  /// Uses `subscription_decoder` to extract first `vless://` URL.
  Future<Profile> addProfileFromText(String text) async {
    final t = text.trim();
    if (t.isEmpty) throw Exception('Пустой текст подписки');
    try {
      final vless = await extractVlessFromAny(t);
      // try to extract name from vless fragment (#name)
      var name = extractNameFromVless(vless);
      if (name.isEmpty) {
        final idx = profileManager.profiles.length + 1;
        name = 'Профиль $idx';
      }
      final p = Profile(name, vless);
      addProfile(p);
      return p;
    } catch (e) {
      throw Exception('Не удалось распарсить подписку: $e');
    }
  }

  /// Dispose core resources (stop running tunnel and dispose logger)
  Future<void> dispose() async {
    try {
      await stopTunnel();
    } catch (_) {}
    try {
      singboxManager.logger.dispose();
    } catch (_) {}
  }

  void editProfile(int idx, Profile p) {
    profileManager.editAt(idx, p);
    _saveAll();
  }

  void removeProfile(int idx) {
    profileManager.removeAt(idx);
    _saveAll();
    // adjust currentProfileIndex if needed
    final cur = currentProfileIndex.value;
    if (cur == null) return;
    if (profileManager.profiles.isEmpty) {
      currentProfileIndex.value = null;
      return;
    }
    if (idx == cur) {
      // choose previous if possible, else 0
      final newIdx = (cur - 1) >= 0 ? (cur - 1) : 0;
      currentProfileIndex.value = newIdx;
    } else if (idx < cur) {
      currentProfileIndex.value = cur - 1;
    }
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

  // Convenience async API for UI
  Future<List<String>> getSiteExclusions() async =>
      List<String>.from(exclusions.siteExclusions);

  Future<List<String>> getAppExclusions() async =>
      List<String>.from(exclusions.appExclusions);

  Future<void> addSiteExclusionAsync(String domain) async {
    addSiteExclusion(domain);
  }

  Future<void> addAppExclusionAsync(String appPathOrName) async {
    addAppExclusion(appPathOrName);
  }

  Future<void> removeSiteExclusionValue(String domain) async {
    final idx = exclusions.siteExclusions.indexOf(domain);
    if (idx != -1) removeSiteExclusion(idx);
  }

  Future<void> removeAppExclusionValue(String appPathOrName) async {
    final idx = exclusions.appExclusions.indexOf(appPathOrName);
    if (idx != -1) removeAppExclusion(idx);
  }

  Future<void> updateSiteExclusion({
    required String oldValue,
    required String newValue,
  }) async {
    final idx = exclusions.siteExclusions.indexOf(oldValue);
    if (idx != -1) {
      exclusions.editSite(idx, newValue);
      _saveAll();
    }
  }

  Future<void> updateAppExclusion({
    required String oldValue,
    required String newValue,
  }) async {
    final idx = exclusions.appExclusions.indexOf(oldValue);
    if (idx != -1) {
      exclusions.editApp(idx, newValue);
      _saveAll();
    }
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

  /// Получить строковое представление геолокации по текущему IP.
  /// Возвращает '-' при ошибке или если информации нет.
  Future<String> getIpLocation() async {
    try {
      final ip = await getIp();
      if (ip == '-' || ip.trim().isEmpty) return '-';
      final client = HttpClient();
      try {
        final uri = Uri.parse('http://ip-api.com/json/$ip?fields=status,country,regionName,city');
        final req = await client.getUrl(uri);
        final resp = await req.close();
        if (resp.statusCode != 200) return '-';
        final txt = await resp.transform(utf8.decoder).join();
        final j = json.decode(txt) as Map<String, dynamic>;
        if (j['status'] != 'success') return '-';
        final city = (j['city'] ?? '').toString();
        final region = (j['regionName'] ?? '').toString();
        final country = (j['country'] ?? '').toString();
        final parts = <String>[];
        if (city.isNotEmpty) parts.add(city);
        if (region.isNotEmpty) parts.add(region);
        if (country.isNotEmpty) parts.add(country);
        if (parts.isEmpty) return '-';
        return parts.join(', ');
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return '-';
    }
  }

  /// Convenience: connect by Profile object (will add profile if not present)
  Future<void> connectWithProfile(Profile p) async {
    var idx = profileManager.profiles.indexWhere(
      (e) => e.url == p.url && e.name == p.name,
    );
    if (idx == -1) {
      addProfile(p);
      idx = profileManager.profiles.length - 1;
    }
    await startTunnel(idx);
  }

  /// Generate and write `config.json` (and `config_debug.json`) for the
  /// currently selected profile without starting sing-box.
  Future<void> writeConfigForCurrentProfile() async {
    final idx = currentProfileIndex.value;
    if (idx == null) throw Exception('No profile selected');
    await writeConfigForProfileIndex(idx);
  }

  /// Generate and write `config.json` and `config_debug.json` for a specific profile index.
  Future<void> writeConfigForProfileIndex(int idx) async {
    if (idx < 0 || idx >= profileManager.profiles.length) throw Exception('Profile index out of range');
    final p = profileManager.profiles[idx];

    // build config using existing generator
    final cfg = await buildSingboxConfig(
      p.url,
      ruMode,
      exclusions.siteExclusions,
      exclusions.appExclusions,
    );

    final encoder = const JsonEncoder.withIndent('  ');
    final jsonText = encoder.convert(cfg);

    try {
      final cfgPath = File('${configStore.baseDir.path}${Platform.pathSeparator}config.json');
      await cfgPath.writeAsString(jsonText, flush: true);
      logger.append('config.json сгенерирован для профиля "${p.name}".\n');
      final debugFile = File('${configStore.baseDir.path}${Platform.pathSeparator}config_debug.json');
      await debugFile.writeAsString(jsonText, flush: true);
      logger.append('config_debug.json записан для проверки.\n');
    } catch (e) {
      logger.append('Ошибка при записи config.json: $e\n');
      rethrow;
    }
  }

  /// Ensure config for profile exists and open it in the platform default editor.
  Future<void> openConfigForProfileIndex(int idx) async {
    await writeConfigForProfileIndex(idx);
    final cfgPath = File('${configStore.baseDir.path}${Platform.pathSeparator}config.json');
    try {
      if (Platform.isWindows) {
        await Process.start('notepad.exe', [cfgPath.path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [cfgPath.path]);
      } else {
        await Process.start('xdg-open', [cfgPath.path]);
      }
      logger.append('Открыл config.json для профиля ${profileManager.profiles[idx].name}\n');
    } catch (e) {
      logger.append('Не удалось открыть редактор: $e\n');
      rethrow;
    }
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
      // mode removed (always TUN)
      'site_exclusions': exclusions.siteExclusions,
      'app_exclusions': exclusions.appExclusions,
    };
    configStore.saveGuiConfig(cfg);
    configStore.saveProfiles(profileManager.profiles);
  }
  
}
