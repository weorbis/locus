import 'package:flutter/material.dart';

/// Standard action button used across the demo screens. Renders either a
/// filled or outlined button depending on [filled], and disables itself
/// (with muted styling) when [onPressed] is null.
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.color,
    this.filled = false,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = onPressed == null
        ? Theme.of(context).colorScheme.onSurface.withAlpha(97)
        : color ?? Theme.of(context).colorScheme.primary;

    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: onPressed == null ? null : effectiveColor,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: effectiveColor),
      label: Text(label, style: TextStyle(color: effectiveColor)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: effectiveColor.withAlpha(100)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}
