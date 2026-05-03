import 'package:flutter/material.dart';

/// Pill-shaped indicator showing whether something is active, with a label.
class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    super.key,
    required this.active,
    required this.label,
  });

  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? const Color(0xFF4CAF50) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? const Color(0xFF4CAF50) : const Color(0xFFBDBDBD),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: active ? const Color(0xFF2E7D32) : const Color(0xFF757575),
            ),
          ),
        ],
      ),
    );
  }
}
