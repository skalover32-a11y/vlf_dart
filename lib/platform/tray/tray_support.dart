import 'dart:io';

/// Check if tray operations are supported on current platform
bool get isTraySupported =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;
