import 'dart:io';
import 'package:flutter/material.dart';

class FooterLinks extends StatelessWidget {
  const FooterLinks({super.key});

  Future<void> _openLink(String url) async {
    try {
      if (Platform.isWindows) {
        // Use cmd start to reliably open URLs (handles full URL with path)
        await Process.start('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [url]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [url]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          onTap: () => _openLink('https://t.me/maloff32'),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            child: Row(
              children: const [
                Icon(Icons.send, size: 16, color: Color(0xFF9CA3AF)),
                SizedBox(width: 8),
                Text('@maloff32', style: TextStyle(color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
        ),
        InkWell(
          onTap: () => _openLink('https://github.com/skalover32-a11y/'),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            child: Row(
              children: const [
                Icon(Icons.code, size: 16, color: Color(0xFF9CA3AF)),
                SizedBox(width: 8),
                Text('GitHub', style: TextStyle(color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
