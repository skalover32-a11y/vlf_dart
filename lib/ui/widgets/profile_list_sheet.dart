import 'package:flutter/material.dart';
import 'package:vlf_core/vlf_core.dart' show Profile;

import '../../core/vlf_core.dart';
import '../app_dialogs.dart';

class ProfileListSheet extends StatefulWidget {
  final VlfCore core;
  final Future<void> Function(int) onSelect; // index

  const ProfileListSheet({
    super.key,
    required this.core,
    required this.onSelect,
  });

  @override
  State<ProfileListSheet> createState() => _ProfileListSheetState();
}

class _ProfileListSheetState extends State<ProfileListSheet> {
  @override
  Widget build(BuildContext context) {
    final profiles = widget.core.getProfiles();
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.only(top: 8, left: 16, right: 16, bottom: 16),
        decoration: const BoxDecoration(
          color: Color(0xFF17232D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // handle
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Color(0xFF24303A),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ValueListenableBuilder<int?>(
                valueListenable: widget.core.currentProfileIndex,
                builder: (context, currentIdx, _) {
                  return ListView.builder(
                    itemCount: profiles.length,
                    itemBuilder: (context, idx) {
                      final p = profiles[idx];
                      final isSelected = currentIdx == idx;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Card(
                          color: isSelected ? const Color(0xFF102622) : const Color(0xFF18232C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isSelected ? const Color(0xFF10B981) : Colors.transparent,
                              width: 1.4,
                            ),
                          ),
                          child: InkWell(
                            onTap: () async {
                              await widget.onSelect(idx);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                                vertical: 12.0,
                              ),
                              child: Row(
                                children: [
                                  // three dots
                                  PopupMenuButton<String>(
                                onSelected: (action) async {
                                  if (action == 'edit') {
                                    final profile = widget.core.getProfiles()[idx];
                                    final nameController =
                                        TextEditingController(text: profile.name);
                                    final rawController = TextEditingController(
                                      text: profile.source.isNotEmpty
                                          ? profile.source
                                          : profile.url,
                                    );
                                    final uri = Uri.tryParse(profile.url);
                                    final metadataSection = _buildMetadataSection(
                                      profile,
                                      uri,
                                    );

                                    final shouldSave = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => appDialogWrapper(
                                        buildAppAlert(
                                          title: const Text(
                                            'Редактировать профиль',
                                            style: TextStyle(color: Colors.white),
                                          ),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              metadataSection,
                                              const SizedBox(height: 16),
                                              TextField(
                                                controller: nameController,
                                                decoration: const InputDecoration(
                                                  labelText: 'Название',
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              TextField(
                                                controller: rawController,
                                                maxLines: 6,
                                                decoration: const InputDecoration(
                                                  labelText: 'Подписка / VLESS',
                                                  alignLabelWithHint: true,
                                                ),
                                              ),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(ctx).pop(false),
                                              child: const Text('Отмена'),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.of(ctx).pop(true),
                                              child: const Text('Сохранить'),
                                            ),
                                          ],
                                        ),
                                        width: 460,
                                      ),
                                    );

                                    if (shouldSave == true) {
                                      try {
                                        await widget.core.updateProfileFromText(
                                          index: idx,
                                          name: nameController.text,
                                          rawText: rawController.text,
                                        );
                                        if (mounted) {
                                          setState(() {});
                                          showAppSnackBar(context, 'Профиль сохранён');
                                        }
                                      } catch (e) {
                                        final msg = 'Не удалось сохранить профиль: $e';
                                        widget.core.logger.append('$msg\n');
                                        if (mounted) showAppSnackBar(context, msg);
                                      }
                                    }
                                  } else if (action == 'rename') {
                                    final nameController = TextEditingController(
                                      text: widget.core.getProfiles()[idx].name,
                                    );
                                    final shouldSave = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => appDialogWrapper(
                                        buildAppAlert(
                                          title: const Text(
                                            'Переименовать профиль',
                                            style: TextStyle(color: Colors.white),
                                          ),
                                          content: TextField(
                                            controller: nameController,
                                            autofocus: true,
                                            decoration: const InputDecoration(
                                              labelText: 'Новое название',
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(ctx).pop(false),
                                              child: const Text('Отмена'),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.of(ctx).pop(true),
                                              child: const Text('Сохранить'),
                                            ),
                                          ],
                                        ),
                                        width: 420,
                                      ),
                                    );
                                    if (shouldSave == true) {
                                      try {
                                        await widget.core.renameProfile(
                                          idx,
                                          nameController.text,
                                        );
                                        if (mounted) {
                                          setState(() {});
                                          showAppSnackBar(
                                            context,
                                            'Название профиля обновлено',
                                          );
                                        }
                                      } catch (e) {
                                        final msg = 'Не удалось переименовать профиль: $e';
                                        widget.core.logger.append('$msg\n');
                                        if (mounted) showAppSnackBar(context, msg);
                                      }
                                    }
                                  } else if (action == 'delete') {
                                    widget.core.removeProfile(idx);
                                    setState(() {});
                                  } else if (action == 'refresh') {
                                    try {
                                      await widget.core.refreshProfileByIndex(idx);
                                      const msg = 'Профиль обновлён';
                                      widget.core.logger.append('$msg\n');
                                      if (mounted) showAppSnackBar(context, msg);
                                    } catch (e) {
                                      final msg = 'Ошибка обновления профиля: $e';
                                      widget.core.logger.append('$msg\n');
                                      if (mounted) showAppSnackBar(context, msg);
                                    }
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Изменить'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'rename',
                                    child: Text('Переименовать'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Удалить'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'refresh',
                                    child: Text('Обновить'),
                                  ),
                                ],
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.0,
                                  ),
                                  child: Icon(
                                    Icons.more_vert,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            p.name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: const Text(
                                              'активен',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      '∞ GiB',
                                      style: TextStyle(
                                        color: Color(0xFF9CA3AF),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Ещё ∞ дн',
                                style: const TextStyle(
                                  color: Color(0xFF9CA3AF),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataSection(Profile profile, Uri? uri) {
    final String lastUpdated = _formatLastUpdated(profile.lastUpdatedAt);
    final String protocol = _resolveProtocol(profile, uri);
    final String target = _resolveTarget(uri);
    final params = uri?.queryParameters ?? const <String, String>{};
    final String sni = _formatOptional(params['sni']);
    final String fingerprint = _formatOptional(params['fp']);
    final String clientId = _formatOptional(uri?.userInfo);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1A21),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2A33)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Информация о профиле',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _metaRow('Последнее обновление', lastUpdated),
          _metaRow('Тип подключения', protocol),
          _metaRow('Целевой сервер', target),
          _metaRow('SNI', sni),
          _metaRow('Fingerprint', fingerprint),
          _metaRow('Client ID', clientId),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatLastUpdated(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _resolveProtocol(Profile profile, Uri? uri) {
    if (profile.ptype.isNotEmpty) return profile.ptype.toUpperCase();
    final scheme = uri?.scheme ?? '';
    return scheme.isNotEmpty ? scheme.toUpperCase() : '—';
  }

  String _resolveTarget(Uri? uri) {
    if (uri == null || uri.host.isEmpty) return '—';
    final port = _resolvePort(uri);
    return '${uri.host}:$port';
  }

  String _formatOptional(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return '—';
    return trimmed;
  }

  int _resolvePort(Uri uri) {
    if (uri.hasPort && uri.port > 0) return uri.port;
    switch (uri.scheme.toLowerCase()) {
      case 'vless':
      case 'vmess':
      case 'trojan':
        return 443;
      case 'shadowsocks':
        return 8388;
      default:
        return 443;
    }
  }
}
