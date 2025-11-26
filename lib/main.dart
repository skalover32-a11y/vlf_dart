import 'package:flutter/material.dart';
import 'dart:io';
import 'core/vlf_core.dart';
import 'ui/home_screen.dart';
import 'tray_handler.dart';

// Window sizing on desktop
import 'package:window_size/window_size.dart' as window_size;
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Tray icon is initialized inside TrayHandler after core is ready
  
  // On Windows, initialize window_manager and set a reasonable start size.
  if (Platform.isWindows) {
    try {
      await windowManager.ensureInitialized();
      // Enable close interception as early as possible
      try {
        await windowManager.setPreventClose(true);
      } catch (_) {}

      // start size slightly taller to give more vertical room for logs and content
      const startSize = Size(480, 980);
      const minSize = Size(430, 900);

      final options = WindowOptions(
        size: startSize,
        center: true,
        minimumSize: minSize,
        title: 'VLF tunnel',
      );

      windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.setTitle('VLF tunnel');
        await windowManager.setSize(startSize);
        await windowManager.setMinimumSize(minSize);
        // Ensure close interception is on
        try { await windowManager.setPreventClose(true); } catch (_) {}
        // Prevent the window from being resized/larger than the start size.
        // This disables user resizing (so the UI won't stretch unexpectedly).
        await windowManager.setMaximumSize(startSize);
        await windowManager.setResizable(false);
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (_) {
      // fallback for environments where window_manager is not available
      try {
        final initialSize = Size(430, 860);
        final minSize2 = Size(400, 760);
        window_size.setWindowTitle('VLF tunnel');
        window_size.setWindowMinSize(minSize2);
        window_size.setWindowFrame(
          Rect.fromLTWH(100, 100, initialSize.width, initialSize.height),
        );
      } catch (_) {}
    }
  } else if (Platform.isLinux || Platform.isMacOS) {
    try {
      final initialSize = Size(430, 860);
      final minSize = Size(400, 760);
      window_size.setWindowTitle('VLF tunnel');
      window_size.setWindowMinSize(minSize);
      window_size.setWindowFrame(
        Rect.fromLTWH(100, 100, initialSize.width, initialSize.height),
      );
    } catch (_) {
      // ignore if window sizing not available
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VLF tunnel',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: false,
      ),
      home: const Bootstrap(),
    );
  }
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  VlfCore? _core;
  TrayHandler? _trayHandler;
  _EarlySystemTray? _earlyInterceptor;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Attach an early close interceptor to guarantee hide-to-tray behavior
    // even before core/tray initialization finishes.
    if (Platform.isWindows) {
      _earlyInterceptor = _EarlySystemTray();
      windowManager.addListener(_earlyInterceptor!);
      trayManager.addListener(_earlyInterceptor!);
      _earlyInterceptor!._ensureEarlyTrayIcon();
    }
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // TODO: replace Directory.current with path from path_provider
      final baseDir = Directory.current.path;
      final core = await VlfCore.init(baseDir: baseDir);
      
      // Initialize tray handler
      final trayHandler = TrayHandler(core);
      await trayHandler.initialize();

      setState(() {
        _core = core;
        _trayHandler = trayHandler;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    if (_earlyInterceptor != null) {
      windowManager.removeListener(_earlyInterceptor!);
      trayManager.removeListener(_earlyInterceptor!);
      _earlyInterceptor = null;
    }
    _trayHandler?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Text('Initialization error: $_error'),
        ),
      );
    }
    return AppWindowWrapper(child: HomeScreen(core: _core!));
  }
}

// Minimal early system-tray + close interceptor to bridge app startup.
class _EarlySystemTray with WindowListener, TrayListener {
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
  Future<void> _ensureEarlyTrayIcon() async {
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

// Wrapper that renders the mobile layout at fixed design width (430) and
// scales it based on available width. Also reduces external SafeArea padding
// slightly via MediaQuery so the UI appears denser without modifying widgets.
class AppWindowWrapper extends StatelessWidget {
  final Widget child;
  const AppWindowWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // design width is 430; compute a scale factor based on available width
        double scale = (constraints.maxWidth / 430.0);
        if (scale.isNaN || scale.isInfinite) scale = 1.0;
        scale = scale.clamp(0.8, 1.4);

        // Reduce external safe area padding slightly so the UI is denser.
        final mq = MediaQuery.of(context);
        // Make top/bottom safe area minimal (0) so UI fills window vertically.
        final adjusted = mq.copyWith(
          padding: EdgeInsets.only(
            left: mq.padding.left,
            right: mq.padding.right,
            top: 0,
            bottom: 0,
          ),
        );

        // Make the scaled child occupy full available height by setting its
        // unscaled height to constraints.maxHeight/scale. This reduces the
        // top/bottom gaps around the mobile card without changing internal widgets.
        final double childHeight = (constraints.maxHeight / (scale <= 0 ? 1.0 : scale)).clamp(0.0, double.infinity);

        return MediaQuery(
          data: adjusted,
          child: Center(
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: SizedBox(
                width: 430,
                height: childHeight,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
