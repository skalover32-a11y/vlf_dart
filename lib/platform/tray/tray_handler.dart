import 'dart:io';
import '../../core/vlf_core.dart';
import '../../core/system_proxy.dart';
import 'tray_support.dart';

// Conditional imports for desktop-only plugins
import 'package:window_manager/window_manager.dart'
    if (dart.library.html) 'window_manager_stub.dart';
import 'package:tray_manager/tray_manager.dart'
    if (dart.library.html) 'tray_stub.dart';

/// Handles system tray interactions and window close events.
/// Only active on desktop platforms (Windows/Linux/macOS).
/// On mobile/web platforms, all operations are no-ops.
class TrayHandler with WindowListener, TrayListener {
  final VlfCore core;
  bool _isExiting = false;

  TrayHandler(this.core);

  Future<void> initialize() async {
    // Skip tray initialization on unsupported platforms
    if (!isTraySupported) {
      return;
    }

    // Register window and tray listeners (desktop only)
    windowManager.addListener(this);
    trayManager.addListener(this);

    // Set up tray icon
    final iconPath = _resolveTrayIconPath();
    try {
      if (iconPath != null) {
        await trayManager.setIcon(iconPath);
      } else {
        await trayManager.setIcon('assets/tray_icon.ico');
      }
      await trayManager.setToolTip('VLF tunnel');
    } catch (_) {
      // Ignore tray icon errors on unsupported platforms
    }

    // Set up tray menu
    await _updateTrayMenu();
  }

  String? _resolveTrayIconPath() {
    if (!isTraySupported) return null;

    final base = Directory.current.path;
    final candidates = <String>[
      '$base${Platform.pathSeparator}assets${Platform.pathSeparator}tray_icon.ico',
      '$base${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}assets${Platform.pathSeparator}tray_icon.ico',
      '$base${Platform.pathSeparator}windows${Platform.pathSeparator}runner${Platform.pathSeparator}resources${Platform.pathSeparator}app_icon.ico',
    ];
    
    for (final p in candidates) {
      try {
        if (File(p).existsSync()) return p;
      } catch (_) {}
    }
    return null;
  }

  Future<void> _updateTrayMenu() async {
    if (!isTraySupported) return;

    try {
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(
              key: 'show',
              label: 'Открыть VLF tunnel',
            ),
            MenuItem.separator(),
            MenuItem(
              key: 'disconnect_exit',
              label: 'Отключиться и выйти',
            ),
          ],
        ),
      );
    } catch (_) {
      // Ignore menu setup errors
    }
  }

  @override
  void onWindowClose() async {
    if (!isTraySupported) return;

    if (_isExiting) {
      return;
    }

    try {
      final prevent = await windowManager.isPreventClose();
      if (prevent) {
        await windowManager.hide();
        await windowManager.setSkipTaskbar(true);
      }
    } catch (_) {
      try {
        await windowManager.hide();
      } catch (_) {}
    }
  }

  @override
  void onTrayIconMouseDown() {
    if (!isTraySupported) return;
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    if (!isTraySupported) return;
    try {
      trayManager.popUpContextMenu();
    } catch (_) {}
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (!isTraySupported) return;

    switch (menuItem.key) {
      case 'show':
        await _showWindow();
        break;
      case 'disconnect_exit':
        await _disconnectAndExit();
        break;
    }
  }

  Future<void> _showWindow() async {
    if (!isTraySupported) return;

    try {
      await windowManager.show();
      await windowManager.setSkipTaskbar(false);
      await windowManager.focus();
    } catch (_) {}
  }

  Future<void> _disconnectAndExit() async {
    if (!isTraySupported) return;

    _isExiting = true;

    try {
      await core.stopTunnel();
    } catch (_) {}

    try {
      await SystemProxy.disableProxy();
    } catch (_) {}

    if (Platform.isWindows) {
      try {
        await Process.run('taskkill', ['/IM', 'mihomo.exe', '/T', '/F']);
      } catch (_) {}
    }

    try {
      await windowManager.destroy();
    } catch (_) {}
  }

  void dispose() {
    if (!isTraySupported) return;

    try {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    } catch (_) {}
  }
}
