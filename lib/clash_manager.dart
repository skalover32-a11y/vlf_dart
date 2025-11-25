import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'clash_config.dart';
import 'subscription_decoder.dart';
import 'logger.dart';
import 'package:flutter/foundation.dart';

/// Менеджер процесса Clash Meta (mihomo) для управления VPN-туннелем.
/// API аналогичен SingboxManager для упрощения интеграции.
class ClashManager {
  Process? _proc;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  final Logger logger = Logger();
  
  /// Notifier для состояния работы mihomo (подписывайтесь из UI)
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier<bool>(false);

  /// Флаг преднамеренной остановки (чтобы не считать exitCode != 0 крешом)
  bool _stopping = false;

  bool get isRunning => _proc != null;

  /// Запуск Clash Meta (mihomo) с генерацией конфигурации.
  ///
  /// [profileUrl] — VLESS-подписка (строка vless://, URL или base64)
  /// [baseDir] — рабочая директория (где будет config.yaml и откуда запускается mihomo.exe)
  /// [ruMode] — режим работы:
  ///   * false (ГЛОБАЛЬНЫЙ): весь трафик через VPN, кроме локального
  ///   * true (РФ-РЕЖИМ): российский трафик (RU GeoIP) в обход VPN, остальное через VPN
  /// [siteExcl] — список доменов для исключения из VPN (DIRECT)
  /// [appExcl] — список процессов для исключения из VPN (DIRECT)
  Future<void> start(
    String profileUrl,
    Directory baseDir, {
    bool ruMode = false, // ГЛОБАЛЬНЫЙ режим по умолчанию
    List<String> siteExcl = const [],
    List<String> appExcl = const [],
  }) async {
    // 1. Извлекаем VLESS из подписки
    String vless = '';
    try {
      vless = await extractVlessFromAny(profileUrl);
      logger.append('VLESS: $vless\n');
    } catch (e) {
      final msg = 'Ошибка при получении подписки: $e';
      logger.append('$msg\n');
      throw Exception(msg);
    }

    if (_proc != null) {
      throw Exception('Clash уже запущен');
    }

    // 2. Проверяем наличие mihomo.exe
    final mihomoExe = File('${baseDir.path}${Platform.pathSeparator}mihomo.exe');
    if (!mihomoExe.existsSync()) {
      throw FileSystemException('mihomo.exe не найден', mihomoExe.path);
    }

    // 3. Генерируем config.yaml
    final cfgPath = File('${baseDir.path}${Platform.pathSeparator}config.yaml');
    final yamlContent = await buildClashConfig(
      vless,
      ruMode,
      siteExcl,
      appExcl,
    );
    
    await cfgPath.writeAsString(yamlContent, flush: true);
    logger.append('config.yaml сгенерирован\n');

    // Debug: сохраняем копию для проверки
    try {
      final debugFile = File('${baseDir.path}${Platform.pathSeparator}config_debug.yaml');
      await debugFile.writeAsString(yamlContent, flush: true);
      logger.append('config_debug.yaml записан для проверки\n');
    } catch (_) {}

    // 4. Запускаем mihomo.exe -f config.yaml
    final env = Map<String, String>.from(Platform.environment);

    _proc = await Process.start(
      mihomoExe.path,
      ['-f', cfgPath.path],
      environment: env,
      runInShell: false,
      workingDirectory: baseDir.path,
    );

    isRunningNotifier.value = true;
    logger.append('Запускаю Clash Meta (mihomo)...\n');

    // 5. Слушаем stdout и stderr
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    final startupCompleter = Completer<bool>();
    bool hasSeenOutput = false;
    bool startupError = false;

    _stdoutSub = _proc!.stdout.listen(
      (data) {
        hasSeenOutput = true;
        try {
          final text = utf8.decode(data);
          logger.append(text);
          // Clash обычно выводит INFO/WARN/ERROR в stdout
          // Подтверждение старта — любая активность без явных ошибок
          if (!startupCompleter.isCompleted) {
            final lower = text.toLowerCase();
            if (lower.contains('start http') ||
                lower.contains('start mixed') ||
                lower.contains('start tun') ||
                lower.contains('tun mode enabled')) {
              startupCompleter.complete(true);
            }
          }
        } catch (_) {
          logger.append(String.fromCharCodes(data));
        }
      },
      onDone: () {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
    );

    _stderrSub = _proc!.stderr.listen(
      (data) {
        hasSeenOutput = true;
        try {
          final text = utf8.decode(data);
          final lower = text.toLowerCase();
          
          // Фильтруем шумные сообщения
          if (lower.contains('deprecated') || lower.contains('warning:')) {
            logger.append('[WARN] $text');
          } else {
            logger.append('[ERR] $text');
          }

          if (!startupCompleter.isCompleted) {
            // Явная ошибка при старте
            if (lower.contains('fatal') ||
                lower.contains('panic') ||
                lower.contains('cannot') ||
                lower.contains('failed to')) {
              startupError = true;
              startupCompleter.complete(false);
            }
          }
        } catch (_) {
          logger.append('[ERR] ${String.fromCharCodes(data)}');
        }
      },
      onDone: () {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
    );

    // 6. Мониторим завершение процесса в фоне
    unawaited(
      Future(() async {
        try {
          final rc = await _proc!.exitCode;
          await Future.wait([
            stdoutDone.future.catchError((_) {}),
            stderrDone.future.catchError((_) {}),
          ]).timeout(const Duration(seconds: 5), onTimeout: () => <void>[]);
          
          if (_stopping) {
            logger.append('\nClash остановлен пользователем (exitCode=$rc)\n');
          } else {
            logger.append('\nClash завершился с кодом $rc\n');
          }
        } catch (e) {
          logger.append('\nClash завершился с ошибкой: $e\n');
        } finally {
          _stopping = false;
          _proc = null;
          isRunningNotifier.value = false;
        }
      }),
    );

    // 7. Ждём подтверждения старта или таймаута
    try {
      final result = await Future.any([
        startupCompleter.future,
        Future.delayed(const Duration(seconds: 12), () => null),
      ]);

      if (result is bool) {
        if (result == false) {
          // Явный провал старта
          try {
            await stop();
          } catch (_) {}
          throw Exception('Clash не смог запуститься (ошибка в логах)');
        }
        // result == true => успешный старт
      } else {
        // Таймаут — проверяем состояние
        final exited = _proc == null;
        if (exited) {
          throw Exception('Clash завершился сразу после запуска');
        } else {
          if (startupError) {
            try {
              await stop();
            } catch (_) {}
            throw Exception('Clash сообщил об ошибке при старте');
          }
          // Процесс жив и нет явных ошибок
          if (hasSeenOutput) {
            logger.append('Clash запущен (подтверждение по активности логов)\n');
          } else {
            logger.append('Clash запущен (без явной стартовой строки)\n');
          }
        }
      }
    } catch (e) {
      final exited = _proc == null;
      if (exited) {
        throw Exception('Clash завершился сразу после запуска');
      }
      logger.append('Предупреждение: ошибка при подтверждении запуска: $e\n');
    }
  }

  /// Остановка Clash
  Future<void> stop() async {
    await stopClashGracefully();
  }

  /// Мягкая остановка Clash: SIGINT -> ждём 3с -> SIGKILL
  Future<void> stopClashGracefully() async {
    final p = _proc;
    if (p == null) return;

    _stopping = true;

    try {
      // Попытка мягкой остановки
      try {
        p.kill(ProcessSignal.sigint);
      } catch (_) {
        try {
          p.kill(ProcessSignal.sigterm);
        } catch (_) {}
      }

      try {
        await p.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        // Принудительное завершение
        try {
          p.kill(ProcessSignal.sigkill);
        } catch (_) {}
        try {
          await p.exitCode.timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
    } catch (_) {}

    // Очистка подписок и состояния
    try {
      await _stdoutSub?.cancel();
    } catch (_) {}
    _stdoutSub = null;
    
    try {
      await _stderrSub?.cancel();
    } catch (_) {}
    _stderrSub = null;
    
    _proc = null;
    isRunningNotifier.value = false;
    logger.append('Clash процесс полностью остановлен\n');
  }

  /// Освобождение ресурсов (алиас для stop)
  Future<void> dispose() async {
    await stop();
  }

  /// Получение текущего внешнего IP через системный стек
  /// (используется PowerShell для прохождения через TUN)
  Future<String> updateIp() async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-Command',
            r'(Invoke-WebRequest -Uri "https://api.ipify.org?format=text" -UseBasicParsing).Content.Trim()',
          ],
          runInShell: false,
        ).timeout(const Duration(seconds: 10));
        
        if (result.exitCode == 0) {
          final ip = (result.stdout?.toString() ?? '').trim();
          if (ip.isNotEmpty && !ip.contains('error') && !ip.contains('Exception')) {
            return ip;
          }
        }
      } catch (_) {}
    }
    
    // Fallback к прямому HttpClient
    try {
      final client = HttpClient();
      try {
        final req = await client.getUrl(
          Uri.parse('https://api.ipify.org?format=text'),
        );
        final resp = await req.close();
        if (resp.statusCode != 200) return '-';
        final ip = await resp.transform(utf8.decoder).join();
        return ip.trim();
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return '-';
    }
  }

  /// Проверка наличия прав администратора (Windows)
  Future<bool> isWindowsAdmin() async {
    if (!Platform.isWindows) return Future.value(false);
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r"(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)",
      ]);
      final out = (result.stdout ?? '').toString().toLowerCase();
      return out.contains('true');
    } catch (_) {
      return false;
    }
  }

  /// Перезапуск приложения с правами администратора (Windows)
  Future<bool> relaunchAsAdmin(List<String> extraArgs) async {
    if (!Platform.isWindows) return false;
    try {
      final exe = Platform.resolvedExecutable;
      final argsEscaped = extraArgs
          .map((a) => a.replaceAll('"', '""'))
          .join(' ');
      final ps =
          'Start-Process -FilePath "${exe.replaceAll('"', '""')}" -ArgumentList "$argsEscaped" -Verb RunAs';
      await Process.start('powershell', [
        '-NoProfile',
        '-Command',
        ps,
      ], runInShell: false);
      return true;
    } catch (_) {
      return false;
    }
  }
}
