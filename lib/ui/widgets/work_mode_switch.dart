import 'package:flutter/material.dart';
import 'package:vlf_core/vlf_core.dart' show VlfWorkMode;

/// Segmented control for switching between TUN and PROXY modes.
/// Displays current mode and allows switching with visual feedback.
class WorkModeSwitch extends StatelessWidget {
  final VlfWorkMode currentMode;
  final ValueChanged<VlfWorkMode> onModeChanged;
  final bool enabled;

  const WorkModeSwitch({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeButton(
            context,
            mode: VlfWorkMode.tun,
            label: 'TUNNEL',
            icon: Icons.vpn_lock,
          ),
          const SizedBox(width: 2),
          _buildModeButton(
            context,
            mode: VlfWorkMode.proxy,
            label: 'PROXY',
            icon: Icons.dns,
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(
    BuildContext context, {
    required VlfWorkMode mode,
    required String label,
    required IconData icon,
  }) {
    final isSelected = currentMode == mode;
    final color = isSelected ? const Color(0xFF3B82F6) : Colors.transparent;
    final textColor = isSelected ? Colors.white : const Color(0xFF94A3B8);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled && !isSelected ? () => onModeChanged(mode) : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: textColor),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
