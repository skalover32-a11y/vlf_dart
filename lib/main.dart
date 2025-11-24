import 'package:flutter/material.dart';
import 'dart:io';
import 'core/vlf_core.dart';
import 'ui/home_screen.dart';

// Window sizing on desktop
import 'package:window_size/window_size.dart' as window_size;
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On Windows, initialize window_manager and set a reasonable start size.
  if (Platform.isWindows) {
    try {
      await windowManager.ensureInitialized();

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

class Bootstrap extends StatelessWidget {
  const Bootstrap({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: replace Directory.current with path from path_provider
    final baseDir = Directory.current.path;

    return FutureBuilder<VlfCore>(
      future: VlfCore.init(baseDir: baseDir),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Initialization error: ${snapshot.error}'),
            ),
          );
        }
        final core = snapshot.data!;
        return AppWindowWrapper(child: HomeScreen(core: core));
      },
    );
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
              alignment: Alignment.topCenter,
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
