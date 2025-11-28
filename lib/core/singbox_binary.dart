import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:vlf_core/vlf_core.dart';

/// Обёртка для подготовки бинарника sing-box в internal storage.
class SingboxBinary {
  final Directory baseDir;
  final Logger logger;

  const SingboxBinary({required this.baseDir, required this.logger});

  /// Копирует бинарник из assets/core/sing-box-android-arm64 в baseDir/core/sing-box,
  /// выдаёт права исполнения и возвращает абсолютный путь.
  Future<String> ensureSingboxBinary() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('SingboxBinary доступен только на Android');
    }

    final coreDir = Directory(p.join(baseDir.path, 'core'));
    if (!await coreDir.exists()) {
      await coreDir.create(recursive: true);
      logger.append('Создан каталог sing-box core: ${coreDir.path}\n');
    }

    final binPath = p.join(coreDir.path, 'sing-box');
    final binFile = File(binPath);

    if (await _isExistingBinary(binFile)) {
      logger.append('Используем существующий sing-box: $binPath\n');
      return binPath;
    }

    logger.append('Готовим sing-box бинарник в $binPath ...\n');
    final data = await rootBundle.load('assets/core/sing-box-android-arm64');
    await binFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
    logger.append('sing-box скопирован (${data.lengthInBytes} байт)\n');

    await _chmodExecutable(binPath);
    return binPath;
  }

  Future<bool> _isExistingBinary(File file) async {
    if (!await file.exists()) return false;
    try {
      final size = await file.length();
      return size > 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _chmodExecutable(String path) async {
    if (!Platform.isAndroid) return;
    try {
      final result = await Process.run('chmod', ['700', path]);
      if (result.exitCode == 0) {
        logger.append('chmod 700 применён к sing-box\n');
      } else {
        logger.append('⚠️ chmod 700 завершился с кодом ${result.exitCode}: ${result.stderr}\n');
      }
    } catch (e) {
      logger.append('⚠️ Не удалось применить chmod к sing-box: $e\n');
    }
  }
}
