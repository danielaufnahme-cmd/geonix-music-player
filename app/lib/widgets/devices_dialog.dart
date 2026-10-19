import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sync.dart';
import '../state/sync.dart';
import '../theme.dart';
import '../util/format.dart';
import 'dialogs.dart';

Future<void> showDevicesDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const DevicesDialog());

/// Pairing code, paired devices, "Add device" and "Sync now".
class DevicesDialog extends ConsumerStatefulWidget {
  const DevicesDialog({super.key});

  /// Refresh rate of the device list (online dots) while the dialog is open.
  static Duration pollEvery = const Duration(seconds: 5);

  @override
  ConsumerState<DevicesDialog> createState() => _DevicesDialogState();
}

class _DevicesDialogState extends ConsumerState<DevicesDialog> {
  final _code = TextEditingController();
  Timer? _poll;
  bool _loading = false;
  bool _pairing = false;
  String? _pairError;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(DevicesDialog.pollEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      await ref.read(syncProvider.notifier).load();
    } finally {
      _loading = false;
    }
  }

  Future<void> _pair() async {
    if (_pairing) return;
    final code = normalizePairCode(_code.text);
    if (code.length != 6) {
      setState(() => _pairError = 'Type the 6-letter code shown on the other device.');
      return;
    }
    setState(() {
      _pairing = true;
      _pairError = null;
    });
    final error = await ref.read(syncProvider.notifier).pair(code);
    if (!mounted) return;
    setState(() {
      _pairing = false;
      _pairError = error;
      if (error == null) _code.clear();
    });
  }

  Future<void> _remove(SyncDevice d) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Remove ${d.name}?',
      message: 'It stops syncing with this device. No songs or playlists are deleted.',
      confirm: 'Remove',
    );
    if (ok) await ref.read(syncProvider.notifier).remove(d.id);
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final sync = ref.watch(syncProvider);
    final me = sync.status?.thisDevice;

    final Widget body;
    if (sync.available == false) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('This backend does not support device sync yet. Update Geonix on this computer.',
            style: text.bodyMedium?.copyWith(color: gx.muted)),
      );
    } else if (sync.status == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: sync.loadError != null
              ? Text(sync.loadError!, textAlign: TextAlign.center, style: TextStyle(color: gx.muted))
              : const CircularProgressIndicator(),
        ),
      );
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CodeCard(device: me!),
        const SizedBox(height: 20),
        _label(context, 'PAIRED DEVICES'),
        const SizedBox(height: 6),
        if (sync.devices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('No paired devices yet. Type the code shown on your other device below.',
                style: text.bodyMedium?.copyWith(color: gx.muted)),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView(
              shrinkWrap: true,
              children: [for (final d in sync.devices) _DeviceTile(device: d, onRemove: () => _remove(d))],
            ),
          ),
        const SizedBox(height: 16),
        _label(context, 'ADD DEVICE'),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              key: const ValueKey('pair-code-field'),
              controller: _code,
              enabled: !_pairing,
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_PairCodeFormatter()],
              style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 4),
              decoration: InputDecoration(
                hintText: 'Code from the other device',
                hintStyle: TextStyle(color: gx.muted, fontWeight: FontWeight.w400, letterSpacing: 0),
                counterText: '',
                errorText: _pairError,
                errorMaxLines: 3,
              ),
              onChanged: (_) {
                if (_pairError != null) setState(() => _pairError = null);
              },
              onSubmitted: (_) => _pair(),
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilledButton.tonal(
              onPressed: _pairing ? null : _pair,
              child: _pairing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Add'),
            ),
          ),
        ]),
        if (sync.running || sync.progress != null) ...[
          const SizedBox(height: 14),
          _SyncProgress(event: sync.progress, running: sync.running),
        ],
      ]);
    }

    final canSync = sync.available == true && !sync.running && sync.devices.isNotEmpty;
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.devices_rounded, color: gx.accent),
        const SizedBox(width: 12),
        const Expanded(child: Text('Devices')),
      ]),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Sync songs and playlists with your other computers on the same Tailscale network.',
                style: text.bodySmall?.copyWith(color: gx.muted)),
            const SizedBox(height: 16),
            body,
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton.icon(
          onPressed: canSync ? () => ref.read(syncProvider.notifier).run() : null,
          icon: sync.running
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: gx.muted))
              : const Icon(Icons.sync_rounded, size: 18),
          label: Text(sync.running ? 'Syncing…' : 'Sync now'),
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String s) => Text(s,
      style: Theme.of(context)
          .textTheme
          .labelSmall
          ?.copyWith(color: context.gx.muted, fontWeight: FontWeight.w800, letterSpacing: 1.3));
}

/// Letters only, uppercase, max 6.
class _PairCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final clean = normalizePairCode(newValue.text);
    return TextEditingValue(text: clean, selection: TextSelection.collapsed(offset: clean.length));
  }
}

class _CodeCard extends ConsumerWidget {
  const _CodeCard({required this.device});
  final ThisDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
      decoration: BoxDecoration(
        color: gx.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gx.accent.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(device.name.isEmpty ? 'This device' : 'This device · ${device.name}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: gx.muted)),
            const SizedBox(height: 4),
            SelectableText(
              device.code,
              key: const ValueKey('pair-code'),
              style: text.headlineMedium?.copyWith(
                color: gx.text,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text('Type this code on your other device', style: text.bodySmall?.copyWith(color: gx.muted)),
          ]),
        ),
        IconButton(
          tooltip: 'Copy code',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: device.code));
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Code copied')));
          },
          icon: Icon(Icons.copy_rounded, color: gx.muted),
        ),
        IconButton(
          tooltip: 'New code',
          onPressed: () => ref.read(syncProvider.notifier).newCode(),
          icon: Icon(Icons.refresh_rounded, color: gx.muted),
        ),
      ]),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onRemove});
  final SyncDevice device;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final err = Theme.of(context).colorScheme.error;
    final synced = device.lastSyncAt == null ? 'Never synced' : 'Synced ${formatAgo(device.lastSyncAt!)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Tooltip(
          message: device.online ? 'Online' : 'Offline',
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: device.online ? const Color(0xFF3DDC84) : gx.muted.withValues(alpha: 0.4),
              boxShadow: device.online
                  ? [BoxShadow(color: const Color(0xFF3DDC84).withValues(alpha: 0.5), blurRadius: 6)]
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(device.name.isEmpty ? device.address : device.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text(
              device.lastError != null ? '$synced · ${device.lastError}' : synced,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: device.lastError != null ? err : gx.muted),
            ),
          ]),
        ),
        IconButton(
          tooltip: 'Remove device',
          visualDensity: VisualDensity.compact,
          onPressed: onRemove,
          icon: Icon(Icons.link_off_rounded, color: gx.muted, size: 20),
        ),
      ]),
    );
  }
}

class _SyncProgress extends StatelessWidget {
  const _SyncProgress({required this.event, required this.running});
  final SyncEvent? event;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final text = Theme.of(context).textTheme;
    final e = event;
    final String label;
    if (e == null || e.state == 'started' && e.device.isEmpty) {
      label = 'Starting sync…';
    } else if (e.isError) {
      label = e.device.isEmpty ? 'Sync failed: ${e.message}' : 'Sync with ${e.device} failed: ${e.message}';
    } else if (e.state == 'done') {
      label = e.message.isNotEmpty
          ? e.message
          : (e.done > 0 ? 'Got ${plural(e.done, 'new song')} from ${e.device}' : '${e.device} is in sync');
    } else {
      final who = e.device.isEmpty ? '' : ' with ${e.device}';
      final count = e.total > 0 ? ' · ${e.done}/${e.total}' : '';
      label = e.message.isNotEmpty ? '${e.message}$count' : 'Syncing$who$count';
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (running)
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: e?.fraction, minHeight: 4, color: gx.accent, backgroundColor: gx.accentSoft),
        ),
      const SizedBox(height: 6),
      Text(label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(color: e?.isError == true ? Theme.of(context).colorScheme.error : gx.muted)),
    ]);
  }
}
