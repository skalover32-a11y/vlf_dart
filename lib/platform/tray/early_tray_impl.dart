// Desktop implementation of early tray interceptor
import 'dart:io';
import 'desktop_plugins.dart';

// Minimal early system-tray + close interceptor to bridge app startup.
class EarlySystemTray with WindowListener, TrayListener {
  @override
  void onWindowClose() async {
    try {
      final prevent = await windowManager.isPreventClose();
      if (prevent) {
        await windowManager.hide();
        await windowManager.setSkipTaskbar(true);
      }
    } catch (_) {
      await windowManager.hide();
    }
  }

  // Basic tray icon so user can restore the window even before core is ready.
  Future<void> ensureEarlyTrayIcon() async {
    try {
      final path = _resolveTrayIconPath();
      if (path != null) {
        await trayManager.setIcon(path);
      }
      await trayManager.setContextMenu(
        Menu(items: [MenuItem(key: 'show', label: 'Открыть VLF tunnel')]),
      );
    } catch (_) {}
  }

  String? _resolveTrayIconPath() {
    final base = Directory.current.path;
    final sep = Platform.pathSeparator;
    final candidates = <String>[
      '$base${sep}assets${sep}tray_icon.ico',
      '$base${sep}data${sep}flutter_assets${sep}assets${sep}tray_icon.ico',
    ];
    for (final p in candidates) {
      try {
        if (File(p).existsSync()) return p;
      } catch (_) {}
    }
    return null;
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.setSkipTaskbar(false);
    windowManager.focus();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      windowManager.show();
      windowManager.setSkipTaskbar(false);
      windowManager.focus();
    }
  }
}
