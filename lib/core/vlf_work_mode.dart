/// Work mode for VLF tunnel
enum VlfWorkMode {
  /// TUN mode: uses TUN interface for transparent proxying (requires wintun.dll on Windows)
  tun,
  
  /// PROXY mode: exposes HTTP/SOCKS proxy on localhost (no TUN, no admin rights needed)
  proxy,
}

extension VlfWorkModeExtension on VlfWorkMode {
  String get displayName {
    switch (this) {
      case VlfWorkMode.tun:
        return 'TUNNEL';
      case VlfWorkMode.proxy:
        return 'PROXY';
    }
  }
  
  String get description {
    switch (this) {
      case VlfWorkMode.tun:
        return 'Прозрачное проксирование через TUN интерфейс';
      case VlfWorkMode.proxy:
        return 'HTTP/SOCKS прокси на localhost:7890';
    }
  }
}
