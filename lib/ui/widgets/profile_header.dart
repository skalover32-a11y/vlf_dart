import 'package:flutter/material.dart';
import '../../core/vlf_core.dart';

class ProfileHeader extends StatelessWidget {
  final VlfCore core;
  final VoidCallback onRefreshPressed;
  final VoidCallback onHeaderTap;

  const ProfileHeader({
    super.key,
    required this.core,
    required this.onRefreshPressed,
    required this.onHeaderTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: core.currentProfileIndex,
      builder: (context, idx, _) {
        final profile =
            (idx != null && idx >= 0 && idx < core.getProfiles().length)
            ? core.getProfiles()[idx]
            : null;
        return Row(
          children: [
            // refresh circular button
            InkWell(
              onTap: onRefreshPressed,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2A36),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.refresh,
                  size: 18,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // profile plate
            Expanded(
              child: GestureDetector(
                onTap: onHeaderTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18232C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF24303A)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.name ?? 'Нет профиля',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              profile != null ? '∞ GiB' : '',
                              style: const TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // right badge with "Ещё ∞ дн" and caret
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF23303A),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: const [
                            Text(
                              'Ещё ∞ дн',
                              style: TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(
                              Icons.keyboard_arrow_down,
                              color: Color(0xFF9CA3AF),
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
