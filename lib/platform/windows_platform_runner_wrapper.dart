import 'dart:io';
import '../clash_manager.dart';
import '../logger.dart' as app_logger;
import '../exclusions.dart';
import '../config_store.dart';
import '../core/system_proxy.dart';
import 'platform_runner.dart';
import 'package:vlf_core/vlf_core.dart';

/// Адаптер для текущей Windows-логики (ClashManager + SystemProxy)
class WindowsPlatformRunnerWrapper implements PlatformRunner {
  final ClashManager clashManager;
  final app_logger.Logger logger;
  final Exclusions exclusions;
  final ConfigStore configStore;

  VlfWorkMode _mode = VlfWorkMode.tun;
  @override
  VlfWorkMode get currentMode => _mode;

  WindowsPlatformRunnerWrapper({
    required this.clashManager,
    required this.logger,
    required this.exclusions,
    required this.configStore,
  });

  @override
  Future<void> startTunnel({
    required int profileIndex,
    required String configYaml,
    required VlfWorkMode mode,
    Map<String, String>? debugPaths,
  }) async {
    _mode = mode;
    await clashManager.start(
      // Профиль URL будет передан извне — сам YAML уже записан
      '',
      Directory(configStore.baseDir.path),
      ruMode: configStore.loadGuiConfig()['ru_mode'] == true,
      siteExcl: exclusions.siteExclusions,
      appExcl: exclusions.appExclusions,
      workMode: mode,
    );

    if (mode == VlfWorkMode.proxy) {
      try {
        await SystemProxy.enableProxy(httpPort: 7890, socksPort: 7891);
        logger.append('Системный прокси включён (HTTP 7890 / SOCKS 7891)\n');
      } catch (e) {
        logger.append('Ошибка включения системного прокси: $e\n');
        await clashManager.stop();
        rethrow;
      }
    } else {
      try {
        await SystemProxy.disableProxy();
      } catch (e) {
        logger.append('Ошибка отключения системного прокси: $e\n');
      }
    }
  }

  @override
  Future<void> stopTunnel() async {
    await clashManager.stop();
    try {
      await SystemProxy.disableProxy();
    } catch (e) {
      logger.append('Ошибка отключения системного прокси: $e\n');
    }
  }

  @override
  Future<String> getStatus() async => clashManager.isRunning ? 'running' : 'stopped';
}
