import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../core/vlf_core.dart';
import 'app_dialogs.dart';

class ExclusionsManager extends StatefulWidget {
  final VlfCore core;

  const ExclusionsManager({super.key, required this.core});

  @override
  State<ExclusionsManager> createState() => _ExclusionsManagerState();
}

class _ExclusionsManagerState extends State<ExclusionsManager> {
  late Future<List<String>> _sitesFuture;
  late Future<List<String>> _appsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _sitesFuture = widget.core.getSiteExclusions();
    _appsFuture = widget.core.getAppExclusions();
  }

  Future<void> _promptAddSite() async {
    final ctrl = TextEditingController();
    final desc = TextEditingController();
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => appDialogWrapper(
        buildAppAlert(
          title: const Text(
            'Добавить исключение — сайт',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'example.com или *.example.com',
                  hintStyle: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: desc,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Описание (опционально)',
                  hintStyle: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.tealAccent),
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );

    if (res != true) return;
    final val = ctrl.text.trim();
    if (val.isEmpty || val.contains(' ')) {
      showAppSnackBar(context, 'Неверный домен');
      return;
    }
    await widget.core.addSiteExclusionAsync(val);
    _reload();
    setState(() {});
    showAppSnackBar(context, 'Исключение для сайта добавлено');
  }

  Future<void> _promptAddApp() async {
    final choice = await showDialog<String?>(
      context: context,
      builder: (ctx) => appDialogWrapper(
        buildAppSimpleDialog(
          title: const Text(
            'Добавить исключение — приложение',
            style: TextStyle(color: Colors.white),
          ),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop('file'),
              child: const Text(
                'Выбрать файл (exe)',
                style: TextStyle(color: Colors.white),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop('process'),
              child: const Text(
                'Выбрать из процессов',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;
    if (choice == 'process') {
      // Try simple Windows tasklist-based implementation
      if (!Platform.isWindows) {
        showAppSnackBar(context, 'Выбор процессов доступен только на Windows');
        return;
      }
      try {
        final pr = await Process.run('tasklist', [], runInShell: true);
        final out = pr.stdout as String;
        final lines = out.split('\n');
        final names = <String>{};
        for (var i = 3; i < lines.length; i++) {
          final l = lines[i].trim();
          if (l.isEmpty) continue;
          final parts = l.split(RegExp(r'\s+'));
          if (parts.isNotEmpty) names.add(parts[0]);
        }
        final selected = await showDialog<String?>(
          context: context,
          builder: (ctx) => appDialogWrapper(
            buildAppAlert(
              title: const Text(
                'Выберите процесс',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: names
                      .map(
                        (n) => ListTile(
                          title: Text(
                            n,
                            style: const TextStyle(color: Colors.white),
                          ),
                          onTap: () => Navigator.of(ctx).pop(n),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        );
        if (selected == null) return;
        await widget.core.addAppExclusionAsync(selected);
        _reload();
        setState(() {});
        showAppSnackBar(context, 'Исключение для приложения добавлено');
        return;
      } catch (e) {
        showAppSnackBar(context, 'Ошибка при получении процессов');
        return;
      }
    }

    // file
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      // store either filename or full path depending on convention — store filename
      final fileName = path.split(Platform.pathSeparator).last;
      await widget.core.addAppExclusionAsync(fileName);
      _reload();
      setState(() {});
      showAppSnackBar(context, 'Исключение для приложения добавлено');
    } catch (e) {
      showAppSnackBar(context, 'Ошибка при выборе файла');
    }
  }

  Future<void> _removeSite(String value) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => appDialogWrapper(
        buildAppAlert(
          title: const Text(
            'Подтвердите удаление',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Удалить исключение для сайта "$value"?',
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('Удалить'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await widget.core.removeSiteExclusionValue(value);
    _reload();
    setState(() {});
    showAppSnackBar(context, 'Исключение удалено');
  }

  Future<void> _removeApp(String value) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => appDialogWrapper(
        buildAppAlert(
          title: const Text(
            'Подтвердите удаление',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Удалить исключение для приложения "$value"?',
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('Удалить'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await widget.core.removeAppExclusionValue(value);
    _reload();
    setState(() {});
    showAppSnackBar(context, 'Исключение удалено');
  }

  Future<void> _editSite(String old) async {
    final ctrl = TextEditingController(text: old);
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => appDialogWrapper(
        buildAppAlert(
          title: const Text(
            'Редактировать исключение — сайт',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: ctrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'example.com',
              hintStyle: TextStyle(color: Colors.white54),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.tealAccent),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (res != true) return;
    final nv = ctrl.text.trim();
    if (nv.isEmpty || nv.contains(' ')) {
      showAppSnackBar(context, 'Неверный домен');
      return;
    }
    await widget.core.updateSiteExclusion(oldValue: old, newValue: nv);
    _reload();
    setState(() {});
    showAppSnackBar(context, 'Исключение обновлено');
  }

  Future<void> _editApp(String old) async {
    final ctrl = TextEditingController(text: old);
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => appDialogWrapper(
        buildAppAlert(
          title: const Text(
            'Редактировать исключение — приложение',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'chrome.exe или полный путь',
                  hintStyle: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['exe'],
                  );
                  if (result == null || result.files.isEmpty) return;
                  final path = result.files.single.path;
                  if (path == null) return;
                  ctrl.text = path.split(Platform.pathSeparator).last;
                },
                child: const Text('Выбрать файл'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.tealAccent),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (res != true) return;
    final nv = ctrl.text.trim();
    if (nv.isEmpty) {
      showAppSnackBar(context, 'Неверное имя/путь');
      return;
    }
    await widget.core.updateAppExclusion(oldValue: old, newValue: nv);
    _reload();
    setState(() {});
    showAppSnackBar(context, 'Исключение обновлено');
  }

  Widget _buildSitesBlock(List<String> sites) {
    return Card(
      color: const Color(0xFF18232C),
      child: Column(
        children: [
          ListTile(
            title: const Text(
              'Сайты',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),
          ...sites.map(
            (s) => ListTile(
              title: Text(s, style: const TextStyle(color: Colors.white)),
              trailing: PopupMenuButton<String>(
                onSelected: (act) async {
                  if (act == 'edit') await _editSite(s);
                  if (act == 'delete') await _removeSite(s);
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'edit', child: Text('Изменить')),
                  const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppsBlock(List<String> apps) {
    return Card(
      color: const Color(0xFF18232C),
      child: Column(
        children: [
          ListTile(
            title: const Text(
              'Приложения',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),
          ...apps.map(
            (s) => ListTile(
              title: Text(s, style: const TextStyle(color: Colors.white)),
              trailing: PopupMenuButton<String>(
                onSelected: (act) async {
                  if (act == 'edit') await _editApp(s);
                  if (act == 'delete') await _removeApp(s);
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'edit', child: Text('Изменить')),
                  const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      appBar: AppBar(
        title: const Text('Менеджер исключений'),
        backgroundColor: const Color(0xFF17232D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<List<String>>(
                future: _sitesFuture,
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final sites = snap.data ?? [];
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildSitesBlock(sites),
                        const SizedBox(height: 12),
                        FutureBuilder<List<String>>(
                          future: _appsFuture,
                          builder: (ctx2, snap2) {
                            if (snap2.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final apps = snap2.data ?? [];
                            return _buildAppsBlock(apps);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _promptAddSite,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F2A30),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      minimumSize: const Size(0, 46),
                    ),
                    child: const Text('Добавить сайт'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _promptAddApp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F2A30),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      minimumSize: const Size(0, 46),
                    ),
                    child: const Text('Добавить приложение'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
