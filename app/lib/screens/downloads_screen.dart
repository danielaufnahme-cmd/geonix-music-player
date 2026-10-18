import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_header.dart';

/// Ids between [anchor] and [target] (inclusive) in display order, added to
/// [current] — what Shift+click selects.
Set<String> selectRange(List<String> ordered, String anchor, String target, Set<String> current) {
  final a = ordered.indexOf(anchor), b = ordered.indexOf(target);
  if (a < 0 || b < 0) return {...current, target};
  final (lo, hi) = a <= b ? (a, b) : (b, a);
  return {...current, ...ordered.sublist(lo, hi + 1)};
}

/// Download list with live progress, retry, and bulk clean-up. Removing
/// entries only tidies the list; music files are never deleted here.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  Set<String> _selected = {};
  String? _anchor;
  final _focus = FocusNode(debugLabel: 'downloads');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  DownloadsController get _ctrl => ref.read(downloadsProvider.notifier);

  void _say(String text) => ref.read(messengerKeyProvider).currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  void _toggle(Download d, List<String> ordered) {
    final shift = HardwareKeyboard.instance.isShiftPressed;
    setState(() {
      if (shift && _anchor != null) {
        _selected = selectRange(ordered, _anchor!, d.id, _selected);
      } else if (_selected.contains(d.id)) {
        _selected = {..._selected}..remove(d.id);
        _anchor = d.id;
      } else {
        _selected = {..._selected, d.id};
        _anchor = d.id;
      }
    });
  }

  void _setAll(List<Download> items, bool select) => setState(() {
        final ids = items.map((d) => d.id);
        _selected = select ? {..._selected, ...ids} : ({..._selected}..removeAll(ids));
      });

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    setState(() => _selected = {});
    await _ctrl.remove(ids);
    _say('Removed ${ids.length} from the list. Your music files are kept.');
  }

  Future<void> _clear(String status) async {
    final n = await _ctrl.clear(status);
    setState(() => _selected = {});
    if (n > 0) {
      _say(status == 'failed' ? 'Cleared $n failed download${n == 1 ? '' : 's'}' : 'Cleared $n completed download${n == 1 ? '' : 's'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(downloadsProvider);
    final active = all.where((d) => d.isActive).toList()
      ..sort((a, b) => (a.status == 'downloading' ? 0 : 1).compareTo(b.status == 'downloading' ? 0 : 1));
    final failed = all.where((d) => d.isFailed).toList();
    final finished = all.where((d) => d.isFinished).toList();
    final selectable = [...failed, ...finished];
    final ordered = [for (final d in selectable) d.id];
    // Drop selections whose rows went away (cleared elsewhere, retried, ...).
    final selected = _selected.intersection(ordered.toSet());
    final text = Theme.of(context).textTheme;
    final gx = context.gx;

    Widget section(String title, List<Download> items, {required bool selectableRows, List<Widget> actions = const []}) {
      final picked = items.where((d) => selected.contains(d.id)).length;
      final allPicked = items.isNotEmpty && picked == items.length;
      return SliverMainAxisGroup(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
            child: Row(children: [
              if (selectableRows)
                Checkbox(
                  tristate: true,
                  value: allPicked ? true : (picked == 0 ? false : null),
                  onChanged: (_) => _setAll(items, !allPicked),
                  side: BorderSide(color: gx.muted),
                ),
              Text('$title · ${items.length}', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              ...actions,
            ]),
          ),
        ),
        SliverList.builder(
          itemCount: items.length,
          itemBuilder: (_, i) => _DownloadRow(
            download: items[i],
            selected: selected.contains(items[i].id),
            onToggle: selectableRows ? () => _toggle(items[i], ordered) : null,
            onRemove: selectableRows ? () => _ctrl.remove([items[i].id]) : null,
          ),
        ),
      ]);
    }

    final headerActions = selected.isNotEmpty
        ? [
            Text('${selected.length} selected', style: text.titleSmall?.copyWith(color: gx.muted)),
            TextButton(onPressed: () => setState(() => _selected = {}), child: const Text('Clear selection')),
            FilledButton.icon(
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete_sweep_rounded),
              label: Text('Remove ${selected.length} from list'),
            ),
          ]
        : [
            if (failed.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _ctrl.retryAllFailed,
                icon: const Icon(Icons.refresh_rounded),
                label: Text('Retry all failed (${failed.length})'),
              ),
          ];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () => setState(() => _selected = ordered.toSet()),
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (selected.isNotEmpty) _deleteSelected();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(() => _selected = {}),
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            sliver: SliverToBoxAdapter(
              child: PageHeader(
                title: 'Downloads',
                subtitle: active.isEmpty
                    ? 'Nothing downloading right now'
                    : '${active.length} in progress · up to 3 at once',
                actions: headerActions,
              ),
            ),
          ),
          if (all.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.download_rounded,
                title: 'No downloads yet',
                message: 'Downloads appear here with live progress.',
                actionLabel: 'Find music',
                onAction: () => ref.read(navProvider.notifier).go(const SearchRoute()),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, kContentBottomPadding),
              sliver: SliverMainAxisGroup(slivers: [
                if (active.isNotEmpty) section('Downloading', active, selectableRows: false),
                if (failed.isNotEmpty)
                  section('Failed', failed, selectableRows: true, actions: [
                    TextButton.icon(
                      onPressed: () => _clear('failed'),
                      icon: const Icon(Icons.clear_all_rounded, size: 18),
                      label: const Text('Clear failed'),
                    ),
                  ]),
                if (finished.isNotEmpty)
                  section('Completed', finished, selectableRows: true, actions: [
                    TextButton.icon(
                      onPressed: () => _clear('done'),
                      icon: const Icon(Icons.clear_all_rounded, size: 18),
                      label: const Text('Clear completed'),
                    ),
                  ]),
                if (selectable.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        'Tip: Shift+click selects a range · Ctrl+A selects all · Delete removes from the list',
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(color: gx.muted),
                      ),
                    ),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _DownloadRow extends ConsumerWidget {
  const _DownloadRow({required this.download, this.selected = false, this.onToggle, this.onRemove});
  final Download download;
  final bool selected;
  final VoidCallback? onToggle;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final d = download;
    final title = d.title.isEmpty ? d.videoId : d.title;

    final (IconData icon, Color color, String status) = switch (d.status) {
      'downloading' => (Icons.downloading_rounded, gx.accent, '${d.progress.toStringAsFixed(0)}%${d.speed != null ? ' · ${d.speed}' : ''}'),
      'queued' => (Icons.schedule_rounded, gx.muted, 'Waiting in queue'),
      'failed' => (Icons.error_outline_rounded, Colors.redAccent, d.error ?? 'Failed'),
      'skipped' => (Icons.check_circle_outline_rounded, gx.muted, 'Already in your library'),
      _ => (Icons.check_circle_rounded, gx.accent, 'Downloaded'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: selected ? gx.accentSoft : gx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? gx.accent.withValues(alpha: 0.5) : gx.outline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              if (onToggle != null) ...[
                Checkbox(value: selected, onChanged: (_) => onToggle!(), side: BorderSide(color: gx.muted)),
                const SizedBox(width: 4),
              ],
              CoverImage(videoId: d.videoId, size: 52, radius: 10),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (d.artist.isNotEmpty)
                    Text(d.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: gx.muted)),
                  const SizedBox(height: 8),
                  if (d.isActive)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: d.progress / 100),
                        duration: const Duration(milliseconds: 400),
                        builder: (_, v, _) => LinearProgressIndicator(value: d.status == 'queued' ? null : v, minHeight: 6),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(icon, size: 15, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(status,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: d.isFailed ? color : gx.muted)),
                    ),
                  ]),
                ]),
              ),
              if (d.isFailed) ...[
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: () => ref.read(downloadsProvider.notifier).retry(d),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remove from list (keeps the file)',
                  onPressed: onRemove,
                  icon: Icon(Icons.close_rounded, color: gx.muted, size: 20),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
