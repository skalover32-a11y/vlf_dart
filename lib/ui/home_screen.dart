import 'package:flutter/material.dart';

import '../core/vlf_core.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../qr_profile_loader.dart';
import 'widgets/vlf_header.dart';
import 'widgets/vlf_circle_button.dart';
import 'widgets/ru_mode_button.dart';
import 'widgets/profile_header.dart';
import 'widgets/status_block.dart';
import 'logs_screen.dart';
import 'widgets/popover_menu.dart';
import 'widgets/footer_links.dart';
import 'widgets/profile_list_sheet.dart';
import 'app_dialogs.dart';
import 'exclusions_manager.dart';

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
  void dispose() {
    // ensure core resources (sing-box) are stopped when UI disposes
    try {
      widget.core.dispose();
    } catch (_) {}
    super.dispose();
  }

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

    // Add profile from clipboard
    Future<void> _handleAddFromClipboard() async {
      setState(() => _isAddMenuOpen = false);
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text ?? '';
        if (text.trim().isEmpty) {
          final msg = 'Буфер пуст или не содержит текста';
          core.logger.append('$msg\n');
          if (mounted) showAppSnackBar(context, msg);
          return;
        }
        final p = await core.addProfileFromText(text);
        final msg = 'Профиль "${p.name}" добавлен';
        core.logger.append('$msg\n');
        if (mounted) showAppSnackBar(context, msg);
      } catch (e) {
        final msg = 'Ошибка при добавлении профиля: $e';
        core.logger.append('$msg\n');
        if (mounted) showAppSnackBar(context, msg);
      }
    }

    // Add profile by link (prompt dialog)
    Future<void> _handleAddByLink() async {
      setState(() => _isAddMenuOpen = false);
      final controller = TextEditingController();
      final result = await showDialog<bool>(
        context: context,
        builder: (context) {
          return appDialogWrapper(
            buildAppAlert(
              title: const Text(
                'Добавить ссылкой',
                style: TextStyle(color: Colors.white),
              ),
              content: TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.tealAccent,
                decoration: const InputDecoration(
                  hintText: 'Вставьте ссылку или подписку',
                  hintStyle: TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Color(0x15FFFFFF),
                  border: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                ),
                maxLines: null,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  child: const Text('Отмена'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.tealAccent,
                  ),
                  child: const Text('Добавить'),
                ),
              ],
            ),
            width: 380.0,
          );
        },
      );

      if (result != true) return;
      final text = controller.text;
      if (text.trim().isEmpty) {
        final msg = 'Пустая ссылка';
        core.logger.append('$msg\n');
        if (mounted) showAppSnackBar(context, msg);
        return;
      }
      try {
        final p = await core.addProfileFromText(text);
        final msg = 'Профиль "${p.name}" добавлен';
        core.logger.append('$msg\n');
        if (mounted) showAppSnackBar(context, msg);
      } catch (e) {
        final msg = 'Ошибка при добавлении профиля: $e';
        core.logger.append('$msg\n');
        if (mounted) showAppSnackBar(context, msg);
      }
    }

    // Add profile through QR (image or camera)
    Future<void> _handleAddByQr() async {
      setState(() => _isAddMenuOpen = false);
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return appDialogWrapper(
            buildAppSimpleDialog(
              title: const Text(
                'Добавить через QR',
                style: TextStyle(color: Colors.white),
              ),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop('camera'),
                  child: const Text(
                    'Использовать камеру',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop('image'),
                  child: const Text(
                    'Использовать картинку',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            width: 360.0,
          );
        },
      );

      if (choice == null) return;
      if (choice == 'camera') {
        final msg = 'Использование камеры для QR пока в разработке';
        widget.core.logger.append('$msg\n');
        if (mounted) showAppSnackBar(context, msg);
        return;
      }

      // image
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg'],
        );
        if (result == null || result.files.isEmpty) return; // cancelled
        final path = result.files.single.path;
        if (path == null) return;
        final file = File(path);
        final decoded = await decodeQrFromImage(file);
        if (decoded == null || decoded.trim().isEmpty) {
          final msg = 'Не удалось распознать VLESS/подписку из QR-кода.';
          widget.core.logger.append('$msg\n');
          if (mounted) showAppSnackBar(context, msg);
          return;
        }
        // reuse existing addProfileFromText logic
        try {
          final p = await widget.core.addProfileFromText(decoded);
          final msg = 'Профиль "${p.name}" добавлен из QR';
          widget.core.logger.append('$msg\n');
          if (mounted) showAppSnackBar(context, msg);
        } catch (e) {
          final msg = 'Ошибка при добавлении профиля из QR: $e';
          widget.core.logger.append('$msg\n');
          if (mounted) showAppSnackBar(context, msg);
        }
      } catch (e) {
        final msg = 'Ошибка при обработке изображения: $e';
        widget.core.logger.append('$msg\n');
        if (mounted) showAppSnackBar(context, msg);
      }
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
          final msg =
              'Нет профилей. Добавьте профиль через кнопку "+" (из буфера или по ссылке).';
          core.logger.append('$msg\n');
          if (mounted) showAppSnackBar(context, msg);
          return;
        }
        try {
          final selected = core.getCurrentProfile();
          if (selected == null) {
            final msg = 'Нет выбранного профиля. Выберите профиль в шапке.';
            core.logger.append('$msg\n');
            if (mounted) showAppSnackBar(context, msg);
            return;
          }
          await core.connectWithProfile(selected);
        } catch (e) {
          final msg = _normalizeExceptionMessage(e);
          core.logger.append('Ошибка подключения: $msg\n');
          if (mounted) showAppSnackBar(context, msg);
          return;
        }
      } else {
        try {
          await core.disconnect();
        } catch (e) {
          final msg = _normalizeExceptionMessage(e);
          core.logger.append('Ошибка остановки: $msg\n');
          if (mounted)
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      body: SafeArea(
        child: Padding(
          // make outer padding minimal so the card is closer to window edges
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardMaxWidth =
                    700.0; // allow wider cards on large screens
                // Use available height from LayoutBuilder constraints so the
                // card fills the vertical space and avoids bottom gaps.
                final cardMaxHeight = constraints.maxHeight;
                // Use a fixed "design" size and scale it down when available space is smaller.
                // This keeps the layout proportional when the window is resized.
                const double designWidth = 430.0;

                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: cardMaxWidth,
                    maxHeight: cardMaxHeight,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: designWidth),
                        child: SizedBox(
                          width: designWidth,
                          child: Container(
                            // allow height to expand up to the parent's maxHeight so UI stretches vertically
                            constraints: BoxConstraints(
                              maxHeight: cardMaxHeight,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 20,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF17232D),
                              borderRadius: BorderRadius.circular(32),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Stack(
                              children: [
                                // Main vertical layout
                                SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      VlfHeader(
                                        onMenuTap: onMenuTap,
                                        onAddTap: onAddTap,
                                      ),
                                      const SizedBox(height: 12),

                                      // Profile header (new)
                                      ProfileHeader(
                                        core: core,
                                        onRefreshPressed: () async {
                                          // Refresh should only regenerate the config
                                          // for the currently selected profile without
                                          // starting the tunnel.
                                          try {
                                            await core.writeConfigForCurrentProfile();
                                            final msg = 'Конфиг профиля обновлён';
                                            core.logger.append('$msg\n');
                                            if (mounted) showAppSnackBar(context, msg);
                                          } catch (e) {
                                            final msg = 'Ошибка обновления конфига: $e';
                                            core.logger.append('$msg\n');
                                            if (mounted) showAppSnackBar(context, msg);
                                          }
                                        },
                                        onHeaderTap: () {
                                          setState(
                                            () => _isAddMenuOpen = false,
                                          );
                                          showModalBottomSheet(
                                            context: context,
                                            isScrollControlled: true,
                                            backgroundColor: Colors.transparent,
                                            builder: (ctx) {
                                              return SizedBox(
                                                height:
                                                    MediaQuery.of(
                                                      context,
                                                    ).size.height *
                                                    0.6,
                                                child: ProfileListSheet(
                                                  core: core,
                                                  onSelect: (idx) {
                                                    core.setCurrentProfileByIndex(
                                                      idx,
                                                    );
                                                    Navigator.of(ctx).pop();
                                                    setState(() {});
                                                  },
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 12),

                                      // status strip (small dot + text)
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          ValueListenableBuilder<bool>(
                                            valueListenable: core.isConnected,
                                            builder: (context, connected, _) {
                                              return Container(
                                                width: 12,
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  color: connected
                                                      ? Colors.green
                                                      : Colors.red,
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
                                                connected
                                                    ? 'Туннель активен'
                                                    : 'Туннель не активен',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      // Режим работы: всегда TUN (proxy-режим отключён)
                                      const SizedBox(height: 18),

                                      // big circle button
                                      ValueListenableBuilder<bool>(
                                        valueListenable: core.isConnected,
                                        builder: (context, connected, _) {
                                          return VlfCircleButton(
                                            isOn: connected,
                                            onTap: _toggleConnection,
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 16),

                                      // RU mode pill button centered (no outer wrapper)
                                      Center(
                                        child: IntrinsicWidth(
                                          child: RuModeButton(
                                            isEnabled: core.ruMode,
                                            onTap: () {
                                              core.setRuMode(!core.ruMode);
                                              setState(() {});
                                            },
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),

                                      // framed status block
                                      StatusBlock(core: core),
                                      const SizedBox(height: 24),

                                      // Logs moved to a separate screen (burger menu)

                                      const SizedBox(height: 12),
                                      const FooterLinks(),
                                    ],
                                  ),
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
                                        PopoverMenuItem(
                                          icon: Icons.insert_drive_file,
                                          text: 'Добавить исключения',
                                          onTap: () {
                                            setState(
                                              () => _isMainMenuOpen = false,
                                            );
                                            // Show a simple dialog to pick site/app and add
                                            showDialog<void>(
                                              context: context,
                                              builder: (ctx) {
                                                return appDialogWrapper(
                                                  buildAppSimpleDialog(
                                                    title: const Text(
                                                      'Добавить исключение',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    children: [
                                                      SimpleDialogOption(
                                                        onPressed: () {
                                                          Navigator.of(
                                                            ctx,
                                                          ).pop();
                                                          // reuse manager's add flow by opening manager and auto-scrolling
                                                          Navigator.of(
                                                            context,
                                                          ).push(
                                                            MaterialPageRoute(
                                                              builder: (c) =>
                                                                  ExclusionsManager(
                                                                    core: core,
                                                                  ),
                                                            ),
                                                          );
                                                        },
                                                        child: const Text(
                                                          'Сайт (домен)',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                      SimpleDialogOption(
                                                        onPressed: () {
                                                          Navigator.of(
                                                            ctx,
                                                          ).pop();
                                                          Navigator.of(
                                                            context,
                                                          ).push(
                                                            MaterialPageRoute(
                                                              builder: (c) =>
                                                                  ExclusionsManager(
                                                                    core: core,
                                                                  ),
                                                            ),
                                                          );
                                                        },
                                                        child: const Text(
                                                          'Программа (приложение)',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  width: 340.0,
                                                );
                                              },
                                            );
                                          },
                                        ),
                                        PopoverMenuItem(
                                          icon: Icons.settings,
                                          text: 'Менеджер исключений',
                                          onTap: () {
                                            setState(
                                              () => _isMainMenuOpen = false,
                                            );
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (c) =>
                                                    ExclusionsManager(
                                                      core: core,
                                                    ),
                                              ),
                                            );
                                          },
                                        ),
                                        PopoverMenuItem(
                                          icon: Icons.list_alt,
                                          text: 'Логи',
                                          onTap: () {
                                            setState(() => _isMainMenuOpen = false);
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (c) => LogsScreen(core: core),
                                              ),
                                            );
                                          },
                                        ),
                                        // 'Настройка режима работы' удалена — всегда работает TUN
                                        // 'Выбор профиля' removed from burger menu (not needed in this UI)
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
                                        PopoverMenuItem(
                                          icon: Icons.content_paste,
                                          text: 'Добавить из буфера',
                                          onTap: () {
                                            _handleAddFromClipboard();
                                          },
                                        ),
                                        PopoverMenuItem(
                                          icon: Icons.link,
                                          text: 'Добавить ссылкой',
                                          onTap: () {
                                            _handleAddByLink();
                                          },
                                        ),
                                        PopoverMenuItem(
                                          icon: Icons.qr_code,
                                          text: 'Добавить через QR код',
                                          onTap: () {
                                            _handleAddByQr();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ), // Stack
                          ), // Container
                        ), // SizedBox
                      ), // ConstrainedBox (maxWidth: designWidth)
                    ), // FittedBox
                  ), // Align
                ); // ConstrainedBox (cardMaxWidth/cardMaxHeight)
              },
            ),
          ),
        ),
      ),
    );
  }
}
