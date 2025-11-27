import 'dart:io';

/// Check if desktop features (window management, tray) are supported
bool get isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;
