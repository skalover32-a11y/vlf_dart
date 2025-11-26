import 'package:flutter/material.dart';
import '../../core/vlf_work_mode.dart';

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

/// Info panel showing proxy details when in PROXY mode.
class ProxyModeInfo extends StatelessWidget {
  const ProxyModeInfo({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF3B82F6).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.info_outline, size: 20, color: Color(0xFF3B82F6)),
              SizedBox(width: 8),
              Text(
                'PROXY режим',
                style: TextStyle(
                  color: Color(0xFF3B82F6),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildProxyLine('HTTP/SOCKS:', '127.0.0.1:7890'),
          const SizedBox(height: 6),
          _buildProxyLine('SOCKS только:', '127.0.0.1:7891'),
          const SizedBox(height: 12),
          const Text(
            'Настройте приложения на использование прокси вручную',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProxyLine(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
