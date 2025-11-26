import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/vlf_core.dart';
import '../core/vlf_work_mode.dart';
import '../qr_profile_loader.dart';
import 'app_dialogs.dart';
import 'exclusions_manager.dart';
import 'logs_screen.dart';
import 'widgets/footer_links.dart';
import 'widgets/popover_menu.dart';
import 'widgets/profile_header.dart';
import 'widgets/profile_list_sheet.dart';
import 'widgets/ru_mode_button.dart';
import 'widgets/status_block.dart';
import 'widgets/vlf_circle_button.dart';
import 'widgets/vlf_header.dart';
import 'widgets/work_mode_switch.dart';

class HomeScreen extends StatefulWidget {
  final VlfCore core;

  const HomeScreen({super.key, required this.core});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isAddMenuOpen = false;
  bool _isMainMenuOpen = false;
  bool _isBusy = false;

  VlfCore get core => widget.core;

  @override
  void dispose() {
    // Best-effort cleanup; ignore errors because app might be closing fast
    core.dispose();
    super.dispose();
  }

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

  void toggleConnection() {
    _toggleConnectionAsync();
  }

  Future<void> _toggleConnectionAsync() async {
    if (_isBusy) return;
    final idx = core.currentProfileIndex.value;
    final isConnected = core.isConnected.value;

    if (!isConnected && idx == null) {
      showAppSnackBar(context, 'Нет выбранного профиля');
      return;
    }

    setState(() => _isBusy = true);
    try {
      if (isConnected) {
        await core.stopTunnel();
        core.logger.append('Туннель остановлен пользователем\n');
      } else {
        await core.startTunnel(idx!);
        core.logger.append('Туннель запускается...\n');
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void handleAddFromClipboard() {
    _handleAddFromClipboardAsync();
  }

  Future<void> _handleAddFromClipboardAsync() async {
    _closeMenus();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (!mounted) return;
      showAppSnackBar(context, 'Буфер обмена пуст');
      return;
    }
    await _addProfileFromSource(text);
  }

  void handleAddByLink() {
    _handleAddByLinkAsync();
  }

  Future<void> _handleAddByLinkAsync() async {
    _closeMenus();
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return appDialogWrapper(
          buildAppAlert(
            title: const Text('Добавить ссылкой', style: TextStyle(color: Colors.white)),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Вставьте vless:// или текст подписки',
                hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF25313D))),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF4B89FF))),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                child: const Text('Добавить'),
              ),
            ],
          ),
        );
      },
    );

    if (text == null || text.isEmpty) return;
    await _addProfileFromSource(text);
  }

  void handleAddByQr() {
    _handleAddByQrAsync();
  }

  Future<void> _handleAddByQrAsync() async {
    _closeMenus();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp'],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final file = File(path);
      final decoded = await decodeQrFromImage(file);
      if (decoded == null || decoded.trim().isEmpty) {
        if (!mounted) return;
        showAppSnackBar(context, 'Не удалось распознать QR-код');
        return;
      }
      await _addProfileFromSource(decoded);
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 'Ошибка чтения файла: $e');
    }
  }

  Future<void> _addProfileFromSource(String raw) async {
    try {
      final profile = await core.addProfileFromText(raw);
      if (!mounted) return;
      setState(() {});
      showAppSnackBar(context, 'Профиль "${profile.name}" добавлен');
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 'Не удалось добавить профиль: $e');
    }
  }

  void _closeMenus() {
    if (!_isAddMenuOpen && !_isMainMenuOpen) return;
    setState(() {
      _isAddMenuOpen = false;
      _isMainMenuOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double cardWidth = constraints.maxWidth.clamp(360.0, 960.0);
            final double cardHeight = constraints.maxHeight.clamp(620.0, 1080.0);

            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Container(
                  width: cardWidth,
                  height: cardHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF17232D),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.45),
                        blurRadius: 24,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: cardHeight - 48),
                            child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              VlfHeader(
                                onMenuTap: onMenuTap,
                                onAddTap: onAddTap,
                              ),
                              // Admin-elevation warning banner
                              ValueListenableBuilder<String?>(
                                valueListenable: core.adminWarning,
                                builder: (context, msg, _) {
                                  if (msg == null) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E1E1E),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFF3A3A3A)),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFC107)),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              msg,
                                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                                            onPressed: () => core.adminWarning.value = null,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              ProfileHeader(
                                core: core,
                                onRefreshPressed: () async {
                                  try {
                                    await core.refreshCurrentProfile();
                                    if (!mounted) return;
                                    showAppSnackBar(context, 'Профиль обновлён');
                                  } catch (e) {
                                    if (!mounted) return;
                                    showAppSnackBar(context, 'Ошибка обновления: $e');
                                  }
                                },
                                onHeaderTap: () {
                                  setState(() => _isAddMenuOpen = false);
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (ctx) {
                                      return SizedBox(
                                        height: MediaQuery.of(context).size.height * 0.6,
                                        child: ProfileListSheet(
                                          core: core,
                                          onSelect: (idx) async {
                                            try {
                                              await core.setCurrentProfileByIndex(idx);
                                              if (!mounted) return;
                                              Navigator.of(ctx).pop();
                                              setState(() {});
                                              showAppSnackBar(
                                                context,
                                                'Профиль переключён. Запустите туннель для активации.',
                                              );
                                            } catch (e) {
                                              if (!mounted) return;
                                              showAppSnackBar(
                                                context,
                                                'Не удалось переключить профиль: $e',
                                              );
                                            }
                                          },
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
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
                                          color: connected ? const Color(0xFF10B981) : Colors.redAccent,
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
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              ValueListenableBuilder<bool>(
                                valueListenable: core.isConnected,
                                builder: (context, connected, _) {
                                  return VlfCircleButton(
                                    isOn: connected,
                                    onTap: toggleConnection,
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              Center(
                                child: IntrinsicWidth(
                                  child: RuModeButton(
                                    isEnabled: core.ruMode,
                                    onTap: () async {
                                      final wasRunning = core.clashManager.isRunningNotifier.value;
                                      final currentProfileIdx = core.currentProfileIndex.value;
                                      if (wasRunning) {
                                        await core.stopTunnel();
                                      }
                                      core.setRuMode(!core.ruMode);
                                      setState(() {});
                                      if (wasRunning && currentProfileIdx != null && currentProfileIdx >= 0) {
                                        await core.startTunnel(currentProfileIdx);
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Work mode switch (TUN / PROXY)
                              Center(
                                child: ValueListenableBuilder<VlfWorkMode>(
                                  valueListenable: core.workMode,
                                  builder: (context, mode, _) {
                                    return WorkModeSwitch(
                                      currentMode: mode,
                                      enabled: !_isBusy,
                                      onModeChanged: (newMode) async {
                                        if (_isBusy) return;
                                        setState(() => _isBusy = true);
                                        try {
                                          await core.setWorkMode(newMode);
                                          if (!mounted) return;
                                          showAppSnackBar(
                                            context,
                                            'Режим изменён на ${newMode.displayName}',
                                          );
                                        } catch (e) {
                                          if (!mounted) return;
                                          showAppSnackBar(context, 'Ошибка: $e');
                                        } finally {
                                          if (mounted) setState(() => _isBusy = false);
                                        }
                                      },
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              StatusBlock(core: core),
                              const SizedBox(height: 24),
                              const FooterLinks(),
                            ],
                          ),
                        ),
                      ),
                    ),
                      if (_isAddMenuOpen || _isMainMenuOpen)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: _closeMenus,
                          ),
                        ),
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
                                  _closeMenus();
                                  showDialog<void>(
                                    context: context,
                                    builder: (ctx) {
                                      return appDialogWrapper(
                                        buildAppSimpleDialog(
                                          title: const Text('Добавить исключение', style: TextStyle(color: Colors.white)),
                                          children: [
                                            SimpleDialogOption(
                                              onPressed: () {
                                                Navigator.of(ctx).pop();
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (c) => ExclusionsManager(core: core),
                                                  ),
                                                );
                                              },
                                              child: const Text('Сайт (домен)', style: TextStyle(color: Colors.white)),
                                            ),
                                            SimpleDialogOption(
                                              onPressed: () {
                                                Navigator.of(ctx).pop();
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (c) => ExclusionsManager(core: core),
                                                  ),
                                                );
                                              },
                                              child: const Text('Программа (приложение)', style: TextStyle(color: Colors.white)),
                                            ),
                                          ],
                                        ),
                                        width: 340,
                                      );
                                    },
                                  );
                                },
                              ),
                              PopoverMenuItem(
                                icon: Icons.settings,
                                text: 'Менеджер исключений',
                                onTap: () {
                                  _closeMenus();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (c) => ExclusionsManager(core: core),
                                    ),
                                  );
                                },
                              ),
                              PopoverMenuItem(
                                icon: Icons.list_alt,
                                text: 'Логи',
                                onTap: () {
                                  _closeMenus();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (c) => LogsScreen(core: core),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
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
                                onTap: handleAddFromClipboard,
                              ),
                              PopoverMenuItem(
                                icon: Icons.link,
                                text: 'Добавить ссылкой',
                                onTap: handleAddByLink,
                              ),
                              PopoverMenuItem(
                                icon: Icons.qr_code,
                                text: 'Добавить через QR код',
                                onTap: handleAddByQr,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
