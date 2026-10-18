import 'package:flutter/material.dart';

import '../theme.dart';

/// Friendly message for empty or failed views.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [gx.accent.withValues(alpha: 0.28), gx.accent.withValues(alpha: 0.04)]),
              ),
              child: Icon(icon, size: 38, color: gx.accent),
            ),
            const SizedBox(height: 22),
            Text(title, textAlign: TextAlign.center, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: gx.muted, height: 1.5)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              if (actionIcon != null)
                FilledButton.icon(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
                  icon: Icon(actionIcon),
                  label: Text(actionLabel!),
                )
              else
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ]),
        ),
      ),
    );
  }
}
