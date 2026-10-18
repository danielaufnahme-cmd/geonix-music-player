import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/player_controller.dart';
import '../theme.dart';
import 'cover_image.dart';
import 'empty_state.dart';
import 'player_bar.dart';

/// Right-hand "Up next" panel: reorder, remove or jump to queued songs.
class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final s = ref.watch(playerProvider);
    final c = ref.read(playerProvider.notifier);
    final upNext = s.upNext;

    return Container(
      width: 330,
      margin: const EdgeInsets.fromLTRB(0, 12, 12, kContentBottomPadding - 20),
      decoration: BoxDecoration(
        color: gx.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: gx.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(children: [
            Expanded(child: Text('Up next', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            if (upNext.isNotEmpty) TextButton(onPressed: c.clearUpNext, child: const Text('Clear')),
            IconButton(
              tooltip: 'Close',
              onPressed: () => ref.read(queueOpenProvider.notifier).toggle(),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
        ),
        if (s.current != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: gx.accentSoft, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                CoverImage(videoId: s.current!.videoId, size: 48, radius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('NOW PLAYING',
                        style: text.labelSmall?.copyWith(color: gx.accent, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    Text(s.current!.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(s.current!.artist,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: gx.muted)),
                  ]),
                ),
              ]),
            ),
          ),
        Expanded(
          child: upNext.isEmpty
              ? const EmptyState(
                  icon: Icons.queue_music_rounded,
                  title: 'Queue is empty',
                  message: 'Use “Play next” or “Add to queue” on any song.',
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  buildDefaultDragHandles: false,
                  itemCount: upNext.length,
                  onReorderItem: c.reorderUpNext,
                  proxyDecorator: (child, _, _) => Material(
                    color: gx.surfaceHigh,
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    child: child,
                  ),
                  itemBuilder: (context, i) {
                    final t = upNext[i];
                    return Material(
                      key: ValueKey('${t.videoId}-$i'),
                      color: Colors.transparent,
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.only(left: 4, right: 4),
                        leading: ReorderableDragStartListener(
                          index: i,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.drag_indicator_rounded, color: gx.muted, size: 18),
                            const SizedBox(width: 4),
                            CoverImage(videoId: t.videoId, size: 40, radius: 8),
                          ]),
                        ),
                        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(t.artist,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: gx.muted)),
                        trailing: IconButton(
                          tooltip: 'Remove from queue',
                          icon: Icon(Icons.close_rounded, size: 18, color: gx.muted),
                          onPressed: () => c.removeFromUpNext(i),
                        ),
                        onTap: () => c.jumpTo(i),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
