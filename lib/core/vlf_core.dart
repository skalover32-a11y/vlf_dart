import 'dart:async';
import 'dart:io';
import 'dart:convert';

import '../config_store.dart';
import '../profile_manager.dart';
import '../exclusions.dart';
import '../clash_manager.dart';
import '../logger.dart';
import '../clash_config.dart';
import 'package:flutter/foundation.dart';
import '../subscription_decoder.dart';
import 'vlf_work_mode.dart';

/// Фасад, объединяющий core-модули для UI.

class VlfCore {
  final ConfigStore configStore;
  final ProfileManager profileManager;
  final Exclusions exclusions;
  final ClashManager clashManager;
  final Logger logger;

  bool ruMode;
  // ValueNotifier для подписки UI на состояние подключения
  final ValueNotifier<bool> isConnected;

  // Work mode: TUN or PROXY
  final ValueNotifier<VlfWorkMode> workMode;

  /// Индекс текущего выбранного профиля в `profileManager.profiles`.
  final ValueNotifier<int?> currentProfileIndex = ValueNotifier<int?>(null);

  VlfCore._(
    this.configStore,
    this.profileManager,
    this.exclusions,
    this.clashManager,
    this.logger,
    this.ruMode,
    this.isConnected,
    this.workMode,
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

    final clashMgr = ClashManager();

    // logger: используем ClashManager.logger для единого потока логов
    final coreLogger = clashMgr.logger;

    // Load work mode from config (default to TUN for backward compatibility)
    final workModeStr = guiCfg['work_mode'] as String?;
    final initialWorkMode = workModeStr == 'proxy' ? VlfWorkMode.proxy : VlfWorkMode.tun;

    final core = VlfCore._(
      store,
      profileMgr,
      excl,
      clashMgr,
      coreLogger,
      guiCfg['ru_mode'] == true,
      clashMgr.isRunningNotifier,
      ValueNotifier<VlfWorkMode>(initialWorkMode),
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

  Future<void> setCurrentProfileByIndex(int? idx) async {
    final prev = currentProfileIndex.value;
    if (idx == prev) return;

    if (idx != null) {
      if (idx < 0 || idx >= profileManager.profiles.length) {
        throw RangeError('profileIdx out of range');
      }
    }

    final wasConnected = isConnected.value;
    if (wasConnected) {
      logger.append('Смена профиля: останавливаю текущий туннель...\n');
      try {
        await stopTunnel();
      } catch (e) {
        logger.append('Ошибка при остановке туннеля перед сменой профиля: $e\n');
        rethrow;
      }
    }

    currentProfileIndex.value = idx;
    _saveAll();

    if (wasConnected) {
      final name = idx != null ? profileManager.profiles[idx].name : 'не выбран';
      logger.append(
        'Профиль переключён на "$name". Запустите туннель вручную для применения.\n',
      );
    }

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
      final p = Profile(
        name,
        vless,
        source: text.trim(),
        lastUpdatedAt: DateTime.now().toUtc(),
      );
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
      clashManager.logger.dispose();
    } catch (_) {}
  }

  void editProfile(int idx, Profile p) {
    profileManager.editAt(idx, p);
    _saveAll();
  }

  Future<void> renameProfile(int index, String newName) async {
    if (index < 0 || index >= profileManager.profiles.length) {
      throw RangeError('profileIdx out of range');
    }
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw Exception('Название профиля не может быть пустым');
    }
    final profile = profileManager.profiles[index];
    profile.name = trimmed;
    profileManager.editAt(index, profile);
    _saveAll();
    if (currentProfileIndex.value == index) {
      currentProfileIndex.notifyListeners();
    }
  }

  Future<void> updateProfileFromText({
    required int index,
    required String name,
    required String rawText,
  }) async {
    if (index < 0 || index >= profileManager.profiles.length) {
      throw RangeError('profileIdx out of range');
    }
    final trimmedRaw = rawText.trim();
    if (trimmedRaw.isEmpty) {
      throw Exception('Пустой текст подписки');
    }
    final parsed = await extractVlessFromAny(trimmedRaw);
    final current = profileManager.profiles[index];
    final newName = name.trim().isEmpty ? current.name : name.trim();

    final updated = Profile(
      newName,
      parsed,
      ptype: current.ptype,
      address: current.address,
      remark: current.remark,
      source: trimmedRaw,
      lastUpdatedAt: DateTime.now().toUtc(),
    );

    profileManager.editAt(index, updated);
    _saveAll();
    await _generateConfigFiles(profile: updated);

    if (currentProfileIndex.value == index && isConnected.value) {
      logger.append(
        'Активный профиль обновлён — перезапустите туннель для применения новых параметров\n',
      );
    } else {
      logger.append('Профиль "$newName" обновлён\n');
    }
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
    _restartIfRunning(); // Перезапуск для применения изменений
  }

  void removeSiteExclusion(int idx) {
    exclusions.removeSite(idx);
    _saveAll();
    _restartIfRunning(); // Перезапуск для применения изменений
  }

  void addAppExclusion(String procName) {
    exclusions.addApp(procName);
    _saveAll();
    _restartIfRunning(); // Перезапуск для применения изменений
  }

  void removeAppExclusion(int idx) {
    exclusions.removeApp(idx);
    _saveAll();
    _restartIfRunning(); // Перезапуск для применения изменений
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
    _restartIfRunning(); // Перезапуск для применения изменений режима
  }

  // --- Work mode (TUN / PROXY) ---
  /// Switch between TUN and PROXY modes.
  /// If tunnel is running, it will be restarted with new mode.
  Future<void> setWorkMode(VlfWorkMode mode) async {
    if (workMode.value == mode) return;

    final wasConnected = isConnected.value;
    final profileIdx = currentProfileIndex.value;

    workMode.value = mode;
    _saveAll();

    if (wasConnected && profileIdx != null) {
      logger.append('Переключение режима: останавливаю туннель...\n');
      await stopTunnel();
      await Future.delayed(const Duration(milliseconds: 500));
      logger.append('Запускаю туннель в режиме ${mode.displayName}...\n');
      await startTunnel(profileIdx);
    } else {
      logger.append('Режим изменён на ${mode.displayName}\n');
    }
  }

  // --- Clash control ---
  /// Start Clash Meta using profile at `profileIdx` (must be valid index in profiles list).
  /// Automatically uses current work mode (TUN or PROXY).
  Future<void> startTunnel(int profileIdx) async {
    if (profileIdx < 0 || profileIdx >= profileManager.profiles.length) {
      throw RangeError('profileIdx out of range');
    }

    final p = profileManager.profiles[profileIdx];
    await clashManager.start(
      p.url,
      Directory(configStore.baseDir.path),
      ruMode: ruMode,
      siteExcl: exclusions.siteExclusions,
      appExcl: exclusions.appExclusions,
      workMode: workMode.value, // Pass current work mode to ClashManager
    );
  }

  Future<void> stopTunnel() async {
    await clashManager.stop();
  }

  Future<String> getIp() => clashManager.updateIp();

  /// Получить строковое представление геолокации по текущему IP.
  /// Возвращает '-' при ошибке или если информации нет.
  Future<String> getIpLocation() async {
    try {
      final ip = await getIp();
      if (ip == '-' || ip.trim().isEmpty) return '-';
      
      // Use PowerShell via system stack to ensure traffic goes through TUN
      if (Platform.isWindows) {
        try {
          final url = 'http://ip-api.com/json/$ip?fields=status,country,regionName,city';
          final result = await Process.run(
            'powershell',
            [
              '-NoProfile',
              '-Command',
              '(Invoke-WebRequest -Uri "$url" -UseBasicParsing).Content',
            ],
            runInShell: false,
          ).timeout(const Duration(seconds: 10));
          if (result.exitCode == 0) {
            final txt = (result.stdout?.toString() ?? '').trim();
            if (txt.isNotEmpty) {
              final j = json.decode(txt) as Map<String, dynamic>;
              if (j['status'] == 'success') {
                final city = (j['city'] ?? '').toString();
                final region = (j['regionName'] ?? '').toString();
                final country = (j['country'] ?? '').toString();
                final parts = <String>[];
                if (city.isNotEmpty) parts.add(city);
                if (region.isNotEmpty) parts.add(region);
                if (country.isNotEmpty) parts.add(country);
                if (parts.isNotEmpty) return parts.join(', ');
              }
            }
          }
        } catch (_) {}
      }
      
      // Fallback to direct HttpClient
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
  /// Запись конфигурации для профиля (для Clash не требуется — генерируется при старте)
  Future<void> writeConfigForProfileIndex(int idx) async {
    if (idx < 0 || idx >= profileManager.profiles.length) {
      throw RangeError('profileIdx out of range');
    }
    final profile = profileManager.profiles[idx];
    await _generateConfigFiles(profile: profile);
    logger.append(
      'config.yaml обновлён для профиля "${profile.name}" (ручное обновление)\n',
    );
  }

  Future<void> refreshCurrentProfile() async {
    final idx = currentProfileIndex.value;
    if (idx == null) {
      throw Exception('Нет активного профиля');
    }
    await refreshProfileByIndex(idx);
  }

  Future<void> refreshProfileByIndex(int idx) async {
    if (idx < 0 || idx >= profileManager.profiles.length) {
      throw RangeError('profileIdx out of range');
    }

    var profile = profileManager.profiles[idx];
    final source = profile.source.trim();
    final timestamp = DateTime.now().toUtc();

    if (source.isNotEmpty) {
      logger.append('Обновляю подписку профиля "${profile.name}"...\n');
      final updatedVless = await extractVlessFromAny(source);
      if (updatedVless != profile.url) {
        profile = Profile(
          profile.name,
          updatedVless,
          ptype: profile.ptype,
          address: profile.address,
          remark: profile.remark,
          source: profile.source,
          lastUpdatedAt: timestamp,
        );
        profileManager.editAt(idx, profile);
        logger.append('Новая конфигурация подписки сохранена\n');
      } else {
        profile.lastUpdatedAt = timestamp;
        profileManager.editAt(idx, profile);
        logger.append('Подписка уже актуальна\n');
      }
    } else {
      logger.append(
        'Профиль "${profile.name}" создан без подписки — перегенерирую только конфиг\n',
      );
      profile.lastUpdatedAt = timestamp;
      profileManager.editAt(idx, profile);
    }

    _saveAll();
    await _generateConfigFiles(profile: profile);
    logger.append('config.yaml обновлён для профиля "${profile.name}"\n');
  }

  Future<void> _generateConfigFiles({required Profile profile}) async {
    final routingPlan = buildRoutingRulesPlan(
      ruMode: ruMode,
      siteExcl: exclusions.siteExclusions,
      appExcl: exclusions.appExclusions,
    );

    // Generate config based on current work mode
    final configYaml = workMode.value == VlfWorkMode.proxy
        ? await buildClashConfigProxy(
            profile.url,
            ruMode,
            exclusions.siteExclusions,
            exclusions.appExclusions,
            routingPlan: routingPlan,
          )
        : await buildClashConfig(
            profile.url,
            ruMode,
            exclusions.siteExclusions,
            exclusions.appExclusions,
            routingPlan: routingPlan,
          );

    final basePath = configStore.baseDir.path;
    final cfgPath = File('$basePath${Platform.pathSeparator}config.yaml');
    await cfgPath.writeAsString(configYaml, flush: true);

    try {
      final debugPath = File('$basePath${Platform.pathSeparator}config_debug.yaml');
      await debugPath.writeAsString(configYaml, flush: true);
    } catch (e) {
      logger.append('Не удалось записать config_debug.yaml: $e\n');
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

  /// История логов для предзагрузки в UI (не очищается при рестарте туннеля).
  List<String> get logHistory => logger.history;

  /// Очистить логи по явной команде пользователя.
  void clearLogs() => logger.clear();

  bool get isRunning => clashManager.isRunning;

  // Save current config and profiles to disk
  void _saveAll() {
    final cfg = {
      'profiles': profileManager.toJson()['profiles'],
      'ru_mode': ruMode,
      'work_mode': workMode.value == VlfWorkMode.proxy ? 'proxy' : 'tun',
      'site_exclusions': exclusions.siteExclusions,
      'app_exclusions': exclusions.appExclusions,
    };
    configStore.saveGuiConfig(cfg);
    configStore.saveProfiles(profileManager.profiles);
  }

  /// Перезапуск туннеля при изменении конфигурации (режим, исключения)
  void _restartIfRunning() {
    if (isConnected.value) {
      final idx = currentProfileIndex.value;
      if (idx != null && idx >= 0 && idx < profileManager.profiles.length) {
        // Асинхронный перезапуск (fire-and-forget)
        Future(() async {
          try {
            final mode = ruMode ? 'RU' : 'GLOBAL';
            logger.append('========== tunnel restarting ($mode) =========='"\n");
            await stopTunnel();
            await Future.delayed(const Duration(milliseconds: 500));
            await startTunnel(idx);
            logger.append('========== tunnel restarted ($mode) =========='"\n");
          } catch (e) {
            logger.append('Ошибка при перезапуске туннеля: $e\n');
          }
        });
      }
    }
  }
  
}
