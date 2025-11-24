import 'package:flutter/material.dart';
import '../../core/vlf_core.dart';
import '../app_dialogs.dart';

class ProfileListSheet extends StatefulWidget {
  final VlfCore core;
  final ValueChanged<int> onSelect; // index

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
              child: ListView.builder(
                itemCount: profiles.length,
                itemBuilder: (context, idx) {
                  final p = profiles[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Card(
                      color: const Color(0xFF18232C),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: () {
                          widget.onSelect(idx);
                        },
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
                                    // Open the config.json for this profile in the
                                    // system editor (writes config first).
                                    try {
                                      await widget.core.openConfigForProfileIndex(idx);
                                    } catch (e) {
                                      final msg = 'Не удалось открыть конфиг: $e';
                                      widget.core.logger.append('$msg\n');
                                      if (mounted) showAppSnackBar(context, msg);
                                    }
                                  } else if (action == 'delete') {
                                    widget.core.removeProfile(idx);
                                    setState(() {});
                                  } else if (action == 'refresh') {
                                    // Refresh should only regenerate the config for
                                    // this profile, not start the tunnel.
                                    try {
                                      await widget.core.writeConfigForProfileIndex(idx);
                                      final msg = 'Конфиг профиля обновлён';
                                      widget.core.logger.append('$msg\n');
                                      if (mounted) showAppSnackBar(context, msg);
                                    } catch (e) {
                                      final msg = 'Ошибка обновления конфига: $e';
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
                                    Text(
                                      p.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
