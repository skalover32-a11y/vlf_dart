import 'package:flutter/material.dart';
import 'dart:io';
import 'core/vlf_core.dart';
import 'ui/home_screen.dart';
import 'platform/tray/tray_handler.dart';

// Window sizing on desktop
import 'package:window_size/window_size.dart' as window_size;
// Conditional import for desktop-only window_manager
import 'package:window_manager/window_manager.dart'
    if (dart.library.html) 'platform/tray/window_manager_stub.dart';

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
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Attach an early close interceptor to guarantee hide-to-tray behavior
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

