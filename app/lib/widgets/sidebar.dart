import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playlist.dart';
import '../state/actions.dart';
import '../state/desktop_theme.dart';
import '../state/providers.dart';
import '../state/sync.dart';
import '../theme.dart';
import 'devices_dialog.dart';
import 'playlist_cover.dart';
import 'skeleton.dart';

/// Left navigation: main sections plus the playlist list. Collapses to
/// icons on narrow windows.
class Sidebar extends ConsumerWidget {
  const Sidebar({super.key, required this.collapsed});
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final route = ref.watch(navProvider).first;
    final current = ref.watch(navProvider).last;
    final nav = ref.read(navProvider.notifier);
    final activeDownloads = ref.watch(activeDownloadCountProvider);
    final playlists = ref.watch(playlistsProvider);

    Widget item(IconData icon, String label, AppRoute target, bool selected, {int badge = 0}) => _NavItem(
          icon: icon,
          label: label,
          selected: selected,
          collapsed: collapsed,
          badge: badge,
          onTap: () => nav.go(target),
        );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: collapsed ? 84 : 256,
      margin: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      decoration: BoxDecoration(
        // Mostly opaque: the wave backdrop only glows faintly through.
        color: gx.surface.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: gx.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(collapsed ? 0 : 20, 22, 12, 18),
          child: Row(mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [gx.accent, gx.accent.withValues(alpha: 0.35), gx.accent]),
                boxShadow: [BoxShadow(color: gx.accent.withValues(alpha: 0.45), blurRadius: 18)],
              ),
              child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 22),
            ),
            if (!collapsed) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text('Geonix',
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              ),
            ],
          ]),
        ),
        item(Icons.home_rounded, 'Home', const HomeRoute(), route is HomeRoute),
        item(Icons.search_rounded, 'Search', const SearchRoute(), route is SearchRoute),
        item(Icons.library_music_rounded, 'Library', const LibraryRoute(), route is LibraryRoute),
        item(Icons.download_rounded, 'Downloads', const DownloadsRoute(), route is DownloadsRoute,
            badge: activeDownloads),
        Padding(
          padding: EdgeInsets.fromLTRB(collapsed ? 0 : 20, 22, 10, 6),
          child: Row(mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            if (!collapsed)
              Expanded(
                child: Text('PLAYLISTS',
                    style: text.labelSmall?.copyWith(color: gx.muted, fontWeight: FontWeight.w800, letterSpacing: 1.3)),
              ),
            IconButton(
              tooltip: 'New playlist',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                final p = await LibraryActions(ref).createPlaylist(context);
                if (p != null) nav.go(PlaylistRoute(p.id));
              },
              icon: Icon(Icons.add_rounded, color: gx.muted),
            ),
          ]),
        ),
        Expanded(
          child: playlists.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: Shimmer(child: SkeletonBox(height: 40))),
            error: (_, _) => const SizedBox.shrink(),
            data: (list) => ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              itemCount: list.length,
              itemBuilder: (context, i) => _PlaylistItem(
                playlist: list[i],
                collapsed: collapsed,
                selected: current is PlaylistRoute && current.id == list[i].id,
                onTap: () => nav.go(PlaylistRoute(list[i].id)),
              ),
            ),
          ),
        ),
        PrivateListeningToggle(collapsed: collapsed),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          child: collapsed
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  const DevicesButton(),
                  _ThemeMenu(collapsed: collapsed),
                ])
              : Row(children: [
                  Expanded(child: _ThemeMenu(collapsed: collapsed)),
                  const DevicesButton(),
                ]),
        ),
      ]),
    );
  }
}

/// Opens the devices dialog (pairing + sync). Hidden when the backend has
/// no sync support; shows a dot while a sync runs.
class DevicesButton extends ConsumerWidget {
  const DevicesButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final sync = ref.watch(syncProvider.select((s) => (s.available, s.running)));
    if (sync.$1 == false) return const SizedBox.shrink();
    return IconButton(
      tooltip: sync.$2 ? 'Devices · syncing…' : 'Devices',
      onPressed: () => showDevicesDialog(context),
      icon: Badge(
        isLabelVisible: sync.$2,
        smallSize: 8,
        backgroundColor: gx.accent,
        child: Icon(Icons.devices_rounded, color: sync.$2 ? gx.accent : gx.muted, size: 20),
      ),
    );
  }
}

/// One-click "Private listening" switch: while on, plays don't feed the
/// recommendations. Hidden until the backend reports the setting.
class PrivateListeningToggle extends ConsumerStatefulWidget {
  const PrivateListeningToggle({super.key, required this.collapsed});
  final bool collapsed;

  @override
  ConsumerState<PrivateListeningToggle> createState() => _PrivateListeningToggleState();
}

class _PrivateListeningToggleState extends ConsumerState<PrivateListeningToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(privateListeningProvider);
    if (enabled == null) return const SizedBox.shrink();
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final color = enabled ? gx.accent : (_hover ? gx.text : gx.muted);
    return Tooltip(
      message: widget.collapsed
          ? 'Private listening ${enabled ? 'on' : 'off'} — songs you play now won\'t affect recommendations'
          : 'Songs you play now won\'t affect recommendations',
      child: Semantics(
        button: true,
        toggled: enabled,
        label: 'Private listening',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: () => ref.read(privateListeningProvider.notifier).toggle(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 0 : 14, vertical: 10),
              decoration: BoxDecoration(
                color: enabled ? gx.accentSoft : (_hover ? gx.text.withValues(alpha: 0.05) : Colors.transparent),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: enabled ? gx.accent.withValues(alpha: 0.4) : gx.outline),
              ),
              child: Row(
                mainAxisAlignment: widget.collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  Icon(enabled ? Icons.visibility_off_rounded : Icons.visibility_outlined, color: color, size: 20),
                  if (!widget.collapsed) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Private listening',
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: text.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: enabled ? gx.accent : gx.text.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(enabled ? 'ON' : 'OFF',
                          style: text.labelSmall?.copyWith(
                              color: enabled ? gx.onAccent : gx.muted, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  final int badge;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final color = widget.selected ? gx.text : (_hover ? gx.text : gx.muted);
    final icon = Badge(
      isLabelVisible: widget.badge > 0,
      label: Text('${widget.badge}'),
      backgroundColor: gx.accent,
      textColor: gx.onAccent,
      child: Icon(widget.icon, color: widget.selected ? gx.accent : color, size: 22),
    );
    return Tooltip(
      message: widget.collapsed ? widget.label : '',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 0 : 14, vertical: 12),
            decoration: BoxDecoration(
              color: widget.selected ? gx.accentSoft : (_hover ? gx.text.withValues(alpha: 0.05) : Colors.transparent),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: widget.collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                icon,
                if (!widget.collapsed) ...[
                  const SizedBox(width: 14),
                  Text(widget.label,
                      style: text.titleSmall?.copyWith(
                          color: color, fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistItem extends StatefulWidget {
  const _PlaylistItem({required this.playlist, required this.collapsed, required this.selected, required this.onTap});
  final Playlist playlist;
  final bool collapsed;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PlaylistItem> createState() => _PlaylistItemState();
}

class _PlaylistItemState extends State<_PlaylistItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final p = widget.playlist;
    return Tooltip(
      message: widget.collapsed ? p.name : '',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(6),
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: widget.selected ? gx.accentSoft : (_hover ? gx.text.withValues(alpha: 0.05) : Colors.transparent),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: widget.collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                PlaylistCover(trackIds: p.coverTrackIds, size: 42, radius: 9, discover: p.isDiscover),
                if (!widget.collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600, color: widget.selected ? gx.accent : gx.text)),
                      Text(p.isDiscover ? 'Made for you' : '${p.trackCount} songs',
                          style: text.bodySmall?.copyWith(color: gx.muted)),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Theme picker: desktop colors (from the Caelestia wallpaper scheme) or the
/// Geonix palette with a light/dark choice.
class _ThemeMenu extends ConsumerWidget {
  const _ThemeMenu({required this.collapsed});
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final settings = ref.watch(themeSettingsProvider);
    final ctrl = ref.read(themeSettingsProvider.notifier);
    final desktopFound = ref.watch(desktopSchemeProvider).asData?.value != null;
    final followingDesktop = settings.source == ThemeSource.desktop && desktopFound;
    final label = followingDesktop ? 'Desktop colors' : 'Geonix ${settings.mode == ThemeMode.light ? 'light' : 'dark'}';

    PopupMenuItem<String> option(String value, IconData icon, String title, {String? subtitle, bool checked = false, bool enabled = true}) =>
        PopupMenuItem<String>(
          value: value,
          enabled: enabled,
          child: Row(children: [
            Icon(icon, size: 18, color: enabled ? gx.text : gx.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: TextStyle(color: enabled ? gx.text : gx.muted)),
                if (subtitle != null) Text(subtitle, style: TextStyle(color: gx.muted, fontSize: 11.5)),
              ]),
            ),
            if (checked) Icon(Icons.check_rounded, size: 18, color: gx.accent),
          ]),
        );

    return PopupMenuButton<String>(
      tooltip: 'Theme',
      position: PopupMenuPosition.over,
      offset: const Offset(0, -150),
      onSelected: (v) {
        switch (v) {
          case 'desktop':
            ctrl.setSource(ThemeSource.desktop);
          case 'geonix':
            ctrl.setSource(ThemeSource.geonix);
          case 'mode':
            ctrl.toggleMode();
        }
      },
      itemBuilder: (_) => [
        option('desktop', Icons.wallpaper_rounded, 'Desktop colors',
            subtitle: desktopFound ? 'Matches your wallpaper' : 'No desktop color scheme found',
            checked: settings.source == ThemeSource.desktop,
            enabled: desktopFound),
        option('geonix', Icons.palette_rounded, 'Geonix purple', checked: settings.source == ThemeSource.geonix || !desktopFound),
        const PopupMenuDivider(),
        option(
          'mode',
          settings.mode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          settings.mode == ThemeMode.dark ? 'Light mode' : 'Dark mode',
          subtitle: followingDesktop ? 'Follows the desktop' : null,
          enabled: !followingDesktop,
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
          Icon(followingDesktop ? Icons.wallpaper_rounded : Icons.palette_rounded, color: gx.muted, size: 20),
          if (!collapsed) ...[
            const SizedBox(width: 10),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: gx.muted))),
          ],
        ]),
      ),
    );
  }
}
