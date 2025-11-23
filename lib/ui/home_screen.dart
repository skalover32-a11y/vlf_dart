import 'package:flutter/material.dart';

import '../core/vlf_core.dart';
import '../profile_manager.dart';
import 'widgets/vlf_header.dart';
import 'widgets/vlf_circle_button.dart';
import 'widgets/ru_mode_button.dart';
import 'widgets/status_block.dart';
import 'widgets/log_panel.dart';
import 'widgets/popover_menu.dart';
import 'widgets/footer_links.dart';

class HomeScreen extends StatefulWidget {
  final VlfCore core;

  const HomeScreen({super.key, required this.core});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isAddMenuOpen = false;
  bool _isMainMenuOpen = false;
  @override
  Widget build(BuildContext context) {
    final core = widget.core;

    void onMenuTap() {
      setState(() {
        _isMainMenuOpen = !_isMainMenuOpen;
        if (_isMainMenuOpen) _isAddMenuOpen = false;
      });
    }

    void onAddTap() {
      setState(() {
        _isAddMenuOpen = !_isAddMenuOpen;
        if (_isAddMenuOpen) _isMainMenuOpen = false;
      });
    }

    String _normalizeExceptionMessage(Object e) {
      var s = e.toString();
      const p = 'Exception: ';
      if (s.startsWith(p)) s = s.substring(p.length);
      return s;
    }

    Future<void> _toggleConnection() async {
      if (!core.isConnected.value) {
        final profiles = core.getProfiles();
        if (profiles.isEmpty) {
          // temporary test profile
          try {
            await core.connectWithProfile(Profile('test', 'https://example.com/sub'));
          } catch (e) {
            final msg = _normalizeExceptionMessage(e);
            core.logger.append('Ошибка подключения: $msg\n');
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
            return;
          }
        } else {
          try {
            await core.connectWithProfile(profiles.first);
          } catch (e) {
            final msg = _normalizeExceptionMessage(e);
            core.logger.append('Ошибка подключения: $msg\n');
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
            return;
          }
        }
      } else {
        try {
          await core.disconnect();
        } catch (e) {
          final msg = _normalizeExceptionMessage(e);
          core.logger.append('Ошибка остановки: $msg\n');
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardMaxWidth = 700.0; // allow wider cards on large screens
                final cardMaxHeight = MediaQuery.of(context).size.height * 0.92;
                return ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: cardMaxWidth, maxHeight: cardMaxHeight),
                  child: Container(
                    width: double.infinity,
                    height: cardMaxHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF17232D),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 18, offset: const Offset(0, 8))],
                    ),
                    child: Stack(
                      children: [
                        // Main vertical layout
                        Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            VlfHeader(onMenuTap: onMenuTap, onAddTap: onAddTap),
                            const SizedBox(height: 12),

                            // status strip (small dot + text)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ValueListenableBuilder<bool>(
                                  valueListenable: core.isConnected,
                                  builder: (context, connected, _) {
                                    return Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: connected ? Colors.green : Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                ValueListenableBuilder<bool>(
                                  valueListenable: core.isConnected,
                                  builder: (context, connected, _) {
                                    return Text(
                                      connected ? 'Туннель активен' : 'Туннель не активен',
                                      style: const TextStyle(color: Colors.white),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                                    // big circle button
                                    ValueListenableBuilder<bool>(
                                      valueListenable: core.isConnected,
                                      builder: (context, connected, _) {
                                        return VlfCircleButton(isOn: connected, onTap: _toggleConnection);
                                      },
                                    ),
                                    const SizedBox(height: 16),

                                    // RU mode pill button centered (no outer wrapper)
                                    Center(
                                      child: IntrinsicWidth(
                                        child: RuModeButton(isEnabled: core.ruMode, onTap: () {
                                          core.setRuMode(!core.ruMode);
                                          setState(() {});
                                        }),
                                      ),
                                    ),
                                    const SizedBox(height: 24),

                            // framed status block
                            StatusBlock(core: core),
                            const SizedBox(height: 24),

                            // Logs header + count (LogPanel includes header)
                            // Expanded so logs occupy remaining space and scroll safely
                            Expanded(
                              child: LogPanel(core: core),
                            ),

                            const SizedBox(height: 12),
                            const FooterLinks(),
                          ],
                        ),

                        // translucent layer to catch taps outside the menus
                        if (_isAddMenuOpen || _isMainMenuOpen)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () {
                                setState(() {
                                  _isAddMenuOpen = false;
                                  _isMainMenuOpen = false;
                                });
                              },
                            ),
                          ),

                        // Main (burger) menu - left top
                        if (_isMainMenuOpen)
                          Positioned(
                            top: 56,
                            left: 12,
                            child: PopoverMenu(
                              width: 260,
                              items: [
                                PopoverMenuItem(icon: Icons.insert_drive_file, text: 'Добавить исключения', onTap: () {
                                  setState(() => _isMainMenuOpen = false);
                                  final msg = 'Добавление исключений пока в разработке';
                                  core.logger.append('$msg\n');
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                                }),
                                PopoverMenuItem(icon: Icons.settings, text: 'Менеджер исключений', onTap: () {
                                  setState(() => _isMainMenuOpen = false);
                                  final msg = 'Менеджер исключений пока в разработке';
                                  core.logger.append('$msg\n');
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                                }),
                                PopoverMenuItem(icon: Icons.tune, text: 'Настройка режима работы', onTap: () {
                                  setState(() => _isMainMenuOpen = false);
                                  final msg = 'Настройка режима работы пока в разработке';
                                  core.logger.append('$msg\n');
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                                }),
                                PopoverMenuItem(icon: Icons.person, text: 'Выбор профиля', onTap: () {
                                  setState(() => _isMainMenuOpen = false);
                                  final msg = 'Выбор профиля пока в разработке';
                                  core.logger.append('$msg\n');
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                                }),
                              ],
                            ),
                          ),

                        // Add (+) menu - right top
                        if (_isAddMenuOpen)
                          Positioned(
                            top: 56,
                            right: 12,
                            child: PopoverMenu(
                              width: 240,
                              items: [
                                PopoverMenuItem(icon: Icons.content_paste, text: 'Добавить из буфера', onTap: () {
                                  setState(() => _isAddMenuOpen = false);
                                  final msg = 'Добавление из буфера пока в разработке';
                                  core.logger.append('$msg\n');
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                                }),
                                PopoverMenuItem(icon: Icons.link, text: 'Добавить ссылкой', onTap: () {
                                  setState(() => _isAddMenuOpen = false);
                                  final msg = 'Добавление по ссылке пока в разработке';
                                  core.logger.append('$msg\n');
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                                }),
                                PopoverMenuItem(icon: Icons.qr_code, text: 'Добавить через QR код', onTap: () {
                                  setState(() => _isAddMenuOpen = false);
                                  final msg = 'Добавление через QR пока в разработке';
                                  core.logger.append('$msg\n');
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                                }),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
