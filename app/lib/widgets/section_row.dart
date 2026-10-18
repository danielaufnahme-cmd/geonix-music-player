import 'package:flutter/material.dart';

import '../theme.dart';

/// Titled horizontal row of cards with scroll arrows (mouse wheels only
/// scroll vertically on desktop).
class SectionRow extends StatefulWidget {
  const SectionRow({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.subtitle,
    this.action,
    this.height = 262,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;

  @override
  State<SectionRow> createState() => _SectionRowState();
}

class _SectionRowState extends State<SectionRow> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scroll(double direction) {
    if (!_controller.hasClients) return;
    final target = (_controller.offset + direction * _controller.position.viewportDimension * 0.8)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(target, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.subtitle != null)
                Text(widget.subtitle!.toUpperCase(),
                    style: text.labelSmall?.copyWith(color: gx.muted, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
              Text(widget.title, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            ]),
          ),
          ?widget.action,
          IconButton(
              tooltip: 'Scroll left', onPressed: () => _scroll(-1), icon: const Icon(Icons.chevron_left_rounded)),
          IconButton(
              tooltip: 'Scroll right', onPressed: () => _scroll(1), icon: const Icon(Icons.chevron_right_rounded)),
        ]),
      ),
      SizedBox(
        height: widget.height,
        child: ListView.builder(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          itemCount: widget.itemCount,
          itemBuilder: widget.itemBuilder,
        ),
      ),
      const SizedBox(height: 18),
    ]);
  }
}
