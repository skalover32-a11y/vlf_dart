import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'core/vlf_core.dart';
import 'core/system_proxy.dart';

/// Handles system tray interactions and window close events.
/// When user closes the window, it hides to tray instead of exiting.
/// Tray menu provides options to restore window or disconnect and exit.
class TrayHandler with WindowListener, TrayListener {
  final VlfCore core;
  bool _isExiting = false;

  TrayHandler(this.core);

  Future<void> initialize() async {
    // Register window and tray listeners
    windowManager.addListener(this);
    trayManager.addListener(this);

    // Ensure tray icon is visible
    final iconPath = _resolveTrayIconPath();
    try {
      if (iconPath != null) {
        await trayManager.setIcon(iconPath);
      } else {
        // Fallback to asset reference (plugin may resolve assets internally)
        await trayManager.setIcon('assets/tray_icon.ico');
      }
      await trayManager.setToolTip('VLF tunnel');
    } catch (_) {}

    // Set up tray menu
    await _updateTrayMenu();
  }

  String? _resolveTrayIconPath() {
    // Try a few likely locations in Windows release/dev builds
    final base = Directory.current.path;
    final candidates = <String>[
      // Dev run
      '$base${Platform.pathSeparator}assets${Platform.pathSeparator}tray_icon.ico',
      // Flutter bundled assets in release
      '$base${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}assets${Platform.pathSeparator}tray_icon.ico',
      // Runner resources icon (same image, different name)
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
  }

  @override
  void onWindowClose() async {
    // Prevent default exit behavior
    if (_isExiting) {
      return; // Allow actual exit when we're intentionally exiting
    }
    // Hide window to tray instead of exiting
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

  @override
  void onTrayIconMouseDown() {
    // On tray icon click, show the window
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // Show context menu on right-click
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
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
    await windowManager.show();
    try {
      await windowManager.setSkipTaskbar(false);
    } catch (_) {}
    await windowManager.focus();
  }

  Future<void> _disconnectAndExit() async {
    _isExiting = true;

    // Stop tunnel if running (same logic as Power button)
    try {
      await core.stopTunnel();
    } catch (_) {}

    try {
      await SystemProxy.disableProxy();
    } catch (_) {}

    // Extra safety on Windows: force-kill mihomo if still alive
    if (Platform.isWindows) {
      try {
        // Kill by image name; /T also kills child processes, /F is force
        await Process.run('taskkill', ['/IM', 'mihomo.exe', '/T', '/F']);
      } catch (_) {}
    }

    // Clean exit
    await windowManager.destroy();
  }

  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
  }
}
