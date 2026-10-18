import 'package:flutter/material.dart';

import '../theme.dart';

/// Large card for horizontal rows: lifts on hover and reveals a play button.
class CoverCard extends StatefulWidget {
  const CoverCard({
    super.key,
    required this.image,
    required this.title,
    this.subtitle,
    this.onTap,
    this.onPlay,
    this.onDownload,
    this.width = 176,
    this.circle = false,
  });

  final Widget image;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onDownload;
  final double width;
  final bool circle;

  @override
  State<CoverCard> createState() => _CoverCardState();
}

class _CoverCardState extends State<CoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap ?? widget.onPlay,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: widget.width + 20,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _hover ? gx.text.withValues(alpha: 0.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedScale(
              scale: _hover ? 1.03 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Stack(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: widget.width,
                  height: widget.width,
                  decoration: BoxDecoration(
                    shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: widget.circle ? null : BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: _hover ? 0.45 : 0.25),
                        blurRadius: _hover ? 28 : 16,
                        offset: Offset(0, _hover ? 14 : 8),
                      ),
                    ],
                  ),
                  child: widget.image,
                ),
                if (widget.onDownload != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: AnimatedOpacity(
                      opacity: _hover ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: _RoundButton(
                        icon: Icons.download_rounded,
                        tooltip: 'Download',
                        size: 34,
                        background: Colors.black.withValues(alpha: 0.55),
                        foreground: Colors.white,
                        onTap: widget.onDownload!,
                      ),
                    ),
                  ),
                if (widget.onPlay != null)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: AnimatedSlide(
                      offset: _hover ? Offset.zero : const Offset(0, 0.4),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: _hover ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: _RoundButton(
                          icon: Icons.play_arrow_rounded,
                          tooltip: 'Play',
                          size: 48,
                          background: gx.accent,
                          foreground: gx.onAccent,
                          onTap: widget.onPlay!,
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Text(widget.title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 3),
              Text(widget.subtitle!,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: gx.muted)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final double size;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: Colors.black54,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: size, height: size, child: Icon(icon, color: foreground, size: size * 0.6)),
          ),
        ),
      );
}
