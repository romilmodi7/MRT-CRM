import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';

/// Gallery backup. Runs while this screen is open (and the app is in the foreground).
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  Map<String, dynamic>? _st;
  bool _loading = true, _running = false, _stop = false;
  String _scope = 'all';
  int _done = 0, _total = 0, _skipped = 0, _failed = 0;
  String _now = '';

  String get _dev => Session.deviceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _stop = true;
    super.dispose();
  }

  Future<void> _load() async {
    final r = await PcApi.get(PcApi.room('backup/status'), {'device_id': _dev});
    if (!mounted) return;
    setState(() {
      _loading = false;
      _st = r.json;
      if (r.json['scope'] != null) _scope = r.json['scope'].toString();
    });
  }

  bool get _registered => _st?['registered'] == true;
  bool get _enabled => _st?['enabled'] == true;
  bool get _paused => _st?['paused'] == true;

  Future<void> _enable() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.hasAccess) {
      if (!mounted) return;
      toast(context, 'Allow Photos and videos access to back up your gallery.');
      PhotoManager.openSetting();
      return;
    }
    final r = await PcApi.post(PcApi.room('backup/device'), {'device_id': _dev, 'label': 'Phone', 'scope': _scope, 'enabled': true});
    if (!mounted) return;
    if (!r.ok) {
      toast(context, r.msg);
      return;
    }
    await _load();
    _run();
  }

  Future<void> _flag(String what) async {
    await PcApi.post(PcApi.room('backup/$what'), {'device_id': _dev});
    await _load();
    if (what == 'resume') _run();
  }

  Future<void> _setScope(String s) async {
    setState(() => _scope = s);
    if (_registered) await PcApi.post(PcApi.room('backup/device'), {'device_id': _dev, 'label': 'Phone', 'scope': s, 'enabled': _enabled});
  }

  RequestType get _type => _scope == 'photos' ? RequestType.image : _scope == 'videos' ? RequestType.video : RequestType.common;

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _stop = false;
      _done = _total = _skipped = _failed = 0;
      _now = 'Reading gallery...';
    });
    try {
      final paths = await PhotoManager.getAssetPathList(onlyAll: true, type: _type);
      if (paths.isEmpty) throw 'empty';
      final all = paths.first;
      final count = await all.assetCountAsync;
      _total = count;
      const batch = 40;
      for (var off = 0; off < count && !_stop && mounted; off += batch) {
        final assets = await all.getAssetListRange(start: off, end: off + batch > count ? count : off + batch);
        final items = [for (final a in assets) {'local_media_id': a.id, 'size': a.size.width.toInt() * a.size.height.toInt()}];
        final chk = await PcApi.post(PcApi.room('backup/check'), {'device_id': _dev, 'items': items});
        if (!chk.ok) {
          if (mounted) toast(context, chk.msg);
          break;
        }
        final missing = ((chk.json['missing'] as List?) ?? []).map((e) => e.toString()).toSet();
        _skipped += assets.length - assets.where((a) => missing.contains(a.id)).length;
        for (final a in assets) {
          if (_stop || !mounted) break;
          if (!missing.contains(a.id)) continue;
          final f = await a.originFile;
          if (f == null) {
            _failed++;
            continue;
          }
          setState(() => _now = a.title ?? f.path.split('/').last);
          final folder = (a.relativePath ?? '').replaceAll(RegExp(r'/+$'), '').split('/').last;
          final r = await PcApi.upload(PcApi.room('backup/upload'), {
            'device_id': _dev,
            'local_media_id': a.id,
            'folder': folder,
            'captured_at': a.createDateTime.toIso8601String(),
          }, [f]);
          if (r.ok) {
            _done++;
          } else {
            _failed++;
            if (r.code == 401 || r.code == 0) {
              _stop = true;
              if (mounted) toast(context, r.msg);
            }
          }
          if (mounted) setState(() {});
        }
      }
    } catch (_) {
      if (mounted) toast(context, 'Backup stopped unexpectedly. Try again.');
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _now = '';
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final recent = ((_st?['recent'] as List?) ?? []).whereType<Map>().toList();
    return Scaffold(
      appBar: AppBar(title: Text('Gallery backup')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: C.accent2))
          : ListView(padding: EdgeInsets.all(18), children: [
              GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(_enabled && !_paused ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: _enabled && !_paused ? C.success : C.muted, size: 34),
                    SizedBox(width: 14),
                    Expanded(child: Text(!_registered || !_enabled ? 'Backup is off' : _paused ? 'Paused' : _running ? 'Backing up...' : 'Backup is on', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                  ]),
                  SizedBox(height: 10),
                  Text('${_st?['file_count'] ?? 0} files  -  ${fmtSize((_st?['total_bytes'] as num?) ?? 0)}', style: TextStyle(color: C.muted)),
                  if (_st?['last_run_at'] != null) Text('Last run: ${_st!['last_run_at']}', style: TextStyle(color: C.muted, fontSize: 12)),
                  if (_running) ...[
                    SizedBox(height: 14),
                    LinearProgressIndicator(value: _total == 0 ? null : ((_done + _skipped + _failed) / _total).clamp(0, 1).toDouble(), color: C.accent2, backgroundColor: C.g2, minHeight: 6),
                    SizedBox(height: 8),
                    Text('$_done uploaded  -  $_skipped already saved${_failed > 0 ? '  -  $_failed failed' : ''}', style: TextStyle(fontSize: 12, color: C.muted)),
                    Text(_now, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.hint)),
                  ],
                ]),
              ),
              SizedBox(height: 16),
              Text('What to back up', style: TextStyle(fontWeight: FontWeight.w700, color: C.muted)),
              SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final s in {'all': 'Photos + videos', 'photos': 'Photos only', 'videos': 'Videos only'}.entries)
                  ChoiceChip(label: Text(s.value), selected: _scope == s.key, onSelected: _running ? null : (_) => _setScope(s.key), selectedColor: C.accent, labelStyle: TextStyle(color: Colors.white)),
              ]),
              SizedBox(height: 18),
              if (!_registered || !_enabled)
                GradientButton(label: 'Turn on backup', icon: Icons.cloud_upload_rounded, onTap: _enable)
              else ...[
                if (_running)
                  OutlinedButton.icon(onPressed: () => setState(() => _stop = true), icon: Icon(Icons.stop_rounded), label: Text('Stop for now'))
                else
                  GradientButton(label: 'Back up now', icon: Icons.sync_rounded, onTap: _paused ? () => _flag('resume') : _run),
                SizedBox(height: 10),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => _flag(_paused ? 'resume' : 'pause'), child: Text(_paused ? 'Resume' : 'Pause'))),
                  SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        if (await confirm(context, 'Turn backup off for this phone?', yes: 'Turn off')) {
                          _stop = true;
                          await _flag('disable');
                        }
                      },
                      style: OutlinedButton.styleFrom(foregroundColor: C.danger),
                      child: Text('Turn off'),
                    ),
                  ),
                ]),
              ],
              SizedBox(height: 10),
              Text('Backup runs while the app is open. Keep this screen open until it finishes.', style: TextStyle(color: C.hint, fontSize: 12)),
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
