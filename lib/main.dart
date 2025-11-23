import 'package:flutter/material.dart';
import 'dart:io';
import 'core/vlf_core.dart';
import 'ui/home_screen.dart';

// Window sizing on desktop
import 'package:window_size/window_size.dart' as window_size;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      final initialSize = Size(430, 860);
      final minSize = Size(400, 760);
      window_size.setWindowTitle('VLF tunnel');
      window_size.setWindowMinSize(minSize);
      window_size.setWindowFrame(Rect.fromLTWH(100, 100, initialSize.width, initialSize.height));
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
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
            body: Center(child: Text('Initialization error: ${snapshot.error}')),
          );
        }
        final core = snapshot.data!;
        return HomeScreen(core: core);
      },
    );
  }
}
