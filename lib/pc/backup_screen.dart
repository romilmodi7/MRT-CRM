import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import 'backup_service.dart';

/// Gallery backup: one switch (on = backs up by itself whenever the private chat is open), what to back up, progress.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  Map<String, dynamic>? _st;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    BackupService.tick.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    BackupService.tick.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final r = await PcApi.get(PcApi.room('backup/status'), {'device_id': BackupService.dev});
    if (!mounted) return;
    setState(() {
      _loading = false;
      _st = r.json;
    });
  }

  Future<void> _switch(bool on) async {
    if (on) {
      final err = await BackupService.turnOn();
      if (err != null && mounted) toast(context, err);
    } else {
      if (!await confirm(context, 'Turn gallery backup off for this phone?', yes: 'Turn off')) return;
      await BackupService.turnOff();
    }
    await _load();
  }

  Future<void> _custom() async {
    final f = TextEditingController(text: BackupService.maxFiles > 0 ? '${BackupService.maxFiles}' : '');
    final m = TextEditingController(text: BackupService.maxMb > 0 ? '${BackupService.maxMb}' : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.card2,
        title: Text('Custom speed'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: f, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Files per hour (empty = no limit)')),
          SizedBox(height: 8),
          TextField(controller: m, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'MB per hour (empty = no limit)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Save')),
        ],
      ),
    );
    if (ok == true) await BackupService.setLimit(int.tryParse(f.text.trim()) ?? 0, int.tryParse(m.text.trim()) ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final recent = ((_st?['recent'] as List?) ?? []).whereType<Map>().toList();
    final on = BackupService.autoOn;
    final run = BackupService.running;
    final tot = BackupService.total;
    return Scaffold(
      appBar: AppBar(title: Text('Gallery backup')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: C.accent2))
          : ListView(padding: EdgeInsets.all(18), children: [
              GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(on ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: on ? C.success : C.muted, size: 34),
                    SizedBox(width: 14),
                    Expanded(child: Text(!on ? 'Backup is off' : run ? 'Backing up...' : 'Backup is on', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                    Switch(value: on, onChanged: _switch, activeColor: C.accent2),
                  ]),
                  SizedBox(height: 10),
                  Text('${_st?['file_count'] ?? 0} files  -  ${fmtSize((_st?['total_bytes'] as num?) ?? 0)}', style: TextStyle(color: C.muted)),
                  if (_st?['last_run_at'] != null) Text('Last run: ${_st!['last_run_at']}', style: TextStyle(color: C.muted, fontSize: 12)),
                  if (run) ...[
                    SizedBox(height: 14),
                    LinearProgressIndicator(value: tot == 0 ? null : ((BackupService.done + BackupService.skipped + BackupService.failed) / tot).clamp(0, 1).toDouble(), color: C.accent2, backgroundColor: C.g2, minHeight: 6),
                    SizedBox(height: 8),
                    Text('${BackupService.done} uploaded  -  ${BackupService.skipped} already saved${BackupService.failed > 0 ? '  -  ${BackupService.failed} failed' : ''}', style: TextStyle(fontSize: 12, color: C.muted)),
                    Text(BackupService.now, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.hint)),
                  ],
                  if (BackupService.waitMsg.isNotEmpty) ...[
                    SizedBox(height: 10),
                    Row(children: [Icon(Icons.schedule_rounded, size: 16, color: C.accent2), SizedBox(width: 6), Expanded(child: Text(BackupService.waitMsg, style: TextStyle(fontSize: 12, color: C.accent2)))]),
                  ],
                  if (BackupService.lastError.isNotEmpty) ...[
                    SizedBox(height: 10),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.info_outline_rounded, size: 16, color: C.danger), SizedBox(width: 6), Expanded(child: Text(BackupService.lastError, style: TextStyle(fontSize: 12, color: C.danger)))]),
                  ],
                ]),
              ),
              SizedBox(height: 16),
              Text('What to back up', style: TextStyle(fontWeight: FontWeight.w700, color: C.muted)),
              SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final s in {'all': 'Photos + videos', 'photos': 'Photos only', 'videos': 'Videos only'}.entries)
                  ChoiceChip(label: Text(s.value), selected: BackupService.scope == s.key, onSelected: run ? null : (_) => BackupService.setScope(s.key), selectedColor: C.accent, labelStyle: TextStyle(color: BackupService.scope == s.key ? Colors.white : C.text)),
              ]),
              SizedBox(height: 18),
              Text('Backup speed', style: TextStyle(fontWeight: FontWeight.w700, color: C.muted)),
              SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final o in const [
                  ['No limit', 0, 0],
                  ['10 files / hour', 10, 0],
                  ['30 files / hour', 30, 0],
                  ['50 MB / hour', 0, 50],
                  ['200 MB / hour', 0, 200],
                ])
                  ChoiceChip(
                    label: Text(o[0] as String),
                    selected: BackupService.maxFiles == o[1] && BackupService.maxMb == o[2],
                    onSelected: (_) => BackupService.setLimit(o[1] as int, o[2] as int),
                    selectedColor: C.accent,
                    labelStyle: TextStyle(color: BackupService.maxFiles == o[1] && BackupService.maxMb == o[2] ? Colors.white : C.text),
                  ),
                ActionChip(label: Text('Custom'), onPressed: _custom),
              ]),
              SizedBox(height: 4),
              Text('Now: ${BackupService.limitLabel}. When the limit is reached it waits and continues in the next hour (while the app is open).', style: TextStyle(color: C.hint, fontSize: 12)),
              SizedBox(height: 18),
              if (on)
                run
                    ? OutlinedButton.icon(onPressed: BackupService.stop, icon: Icon(Icons.stop_rounded), label: Text('Stop for now'))
                    : GradientButton(label: 'Back up now', icon: Icons.sync_rounded, onTap: () async { await BackupService.run(); _load(); }),
              SizedBox(height: 10),
              Text('When the switch is on, backup starts by itself every time you open the private chat. It runs while the app is open.', style: TextStyle(color: C.hint, fontSize: 12)),
              if (recent.isNotEmpty) ...[
                SizedBox(height: 22),
                Text('Recently backed up', style: TextStyle(fontWeight: FontWeight.w700, color: C.muted)),
                for (final m in recent)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.image_rounded, color: C.accent2),
                    title: Text((m['filename'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${m['folder_name'] ?? ''}  -  ${fmtSize((m['size'] as num?) ?? 0)}', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ]),
    );
  }
}
