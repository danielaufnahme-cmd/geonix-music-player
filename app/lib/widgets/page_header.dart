import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme.dart';

/// Page title with an optional back button (when the nav stack allows it).
class PageHeader extends ConsumerWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final canPop = ref.watch(navProvider).length > 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 20),
      child: Row(children: [
        if (canPop) ...[
          BackButtonCircle(onTap: () => ref.read(navProvider.notifier).pop()),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(subtitle!, style: text.bodyMedium?.copyWith(color: gx.muted)),
              ),
          ]),
        ),
        ...actions,
      ]),
    );
  }
}

class BackButtonCircle extends StatelessWidget {
  const BackButtonCircle({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
        tooltip: 'Back',
        onPressed: onTap,
        style: IconButton.styleFrom(backgroundColor: context.gx.surfaceHigh),
        icon: const Icon(Icons.arrow_back_rounded),
      );
}
