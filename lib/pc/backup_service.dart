import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Gallery backup engine. Lives outside any screen, so it can start by itself when the private chat opens.
/// The user's choice is saved on the phone: bk_asked (the question was shown) and bk_on (automatic backup is on).
class BackupService {
  static final ValueNotifier<int> tick = ValueNotifier(0);
  static bool running = false;
  static bool _stop = false;
  static int done = 0, total = 0, skipped = 0, failed = 0;
  static String now = '';

  static String get dev => Session.deviceId;
  static bool get asked => Session.getBool('bk_asked');
  static bool get autoOn => Session.getBool('bk_on');
  static String get scope => Session.getString('bk_scope') ?? 'all';

  static RequestType get _type => scope == 'photos' ? RequestType.image : scope == 'videos' ? RequestType.video : RequestType.common;

  static void _ping() => tick.value++;

  static void stop() {
    _stop = true;
  }

  static Future<void> setScope(String s) async {
    await Session.setString('bk_scope', s);
    if (PcApi.token != null) {
      await PcApi.post(PcApi.room('backup/device'), {'device_id': dev, 'label': 'Phone', 'scope': s, 'enabled': autoOn});
    }
    _ping();
  }

  /// Ask for the gallery permission, switch the backup on (saved) and start. Returns an error text or null.
  static Future<String?> turnOn() async {
    final ps = await AwayGuard.run(() => PhotoManager.requestPermissionExtend());
    if (!ps.hasAccess) {
      await Session.setBool('bk_on', false);
      _ping();
      return 'Allow Photos and videos access to back up your gallery.';
    }
    final r = await PcApi.post(PcApi.room('backup/device'), {'device_id': dev, 'label': 'Phone', 'scope': scope, 'enabled': true});
    if (!r.ok) return r.msg;
    await PcApi.post(PcApi.room('backup/resume'), {'device_id': dev});
    await Session.setBool('bk_asked', true);
    await Session.setBool('bk_on', true);
    _ping();
    run();
    return null;
  }

  static Future<void> turnOff() async {
    _stop = true;
    await Session.setBool('bk_on', false);
    await Session.setBool('bk_asked', true);
    if (PcApi.token != null) await PcApi.post(PcApi.room('backup/disable'), {'device_id': dev});
    _ping();
  }

  /// Called when the private chat opens: if the user allowed it, it starts by itself.
  static Future<void> autoStart() async {
    if (!autoOn || running || PcApi.token == null) return;
    final r = await PcApi.get(PcApi.room('backup/status'), {'device_id': dev});
    if (!r.ok && r.json['registered'] == null) return;
    if (r.json['paused'] == true) return;
    if (r.json['registered'] != true || r.json['enabled'] != true) {
      // switched off from the website, or never registered: register again (the user said yes on this phone)
      final d = await PcApi.post(PcApi.room('backup/device'), {'device_id': dev, 'label': 'Phone', 'scope': scope, 'enabled': true});
      if (!d.ok) return;
    }
    run();
  }

  static Future<void> run() async {
    if (running) return;
    final perm = await AwayGuard.run(() => PhotoManager.requestPermissionExtend());
    if (!perm.hasAccess) return;
    running = true;
    _stop = false;
    done = total = skipped = failed = 0;
    now = 'Reading gallery...';
    _ping();
    try {
      final paths = await PhotoManager.getAssetPathList(onlyAll: true, type: _type);
      if (paths.isEmpty) throw 'empty';
      final all = paths.first;
      final count = await all.assetCountAsync;
      total = count;
      const batch = 40;
      for (var off = 0; off < count && !_stop && PcApi.token != null; off += batch) {
        final assets = await all.getAssetListRange(start: off, end: off + batch > count ? count : off + batch);
        final items = [for (final a in assets) {'local_media_id': a.id, 'size': a.size.width.toInt() * a.size.height.toInt()}];
        final chk = await PcApi.post(PcApi.room('backup/check'), {'device_id': dev, 'items': items});
        if (!chk.ok) break;
        final missing = ((chk.json['missing'] as List?) ?? []).map((e) => e.toString()).toSet();
        skipped += assets.length - assets.where((a) => missing.contains(a.id)).length;
        for (final a in assets) {
          if (_stop || PcApi.token == null) break;
          if (!missing.contains(a.id)) continue;
          final f = await a.originFile;
          if (f == null) {
            failed++;
            continue;
          }
          now = a.title ?? f.path.split('/').last;
          final folder = (a.relativePath ?? '').replaceAll(RegExp(r'/+$'), '').split('/').last;
          final r = await PcApi.upload(PcApi.room('backup/upload'), {
            'device_id': dev,
            'local_media_id': a.id,
            'folder': folder,
            'captured_at': a.createDateTime.toIso8601String(),
          }, [f]);
          if (r.ok) {
            done++;
          } else {
            failed++;
            if (r.code == 401 || r.code == 0) _stop = true;
          }
          _ping();
        }
      }
    } catch (_) {}
    running = false;
    now = '';
    _ping();
  }
}

/// The one-time question shown the first time the private chat opens on a phone.
Future<void> askBackupOnce(BuildContext context) async {
  if (BackupService.asked) {
    BackupService.autoStart();
    return;
  }
  final yes = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: C.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: Container(width: 60, height: 60, decoration: BoxDecoration(gradient: C.grad, shape: BoxShape.circle), child: Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 30)),
      title: Text('Back up your gallery?', textAlign: TextAlign.center),
      content: Text('Do you want to back up all your photos and videos to the private server?\n\nIt starts now and keeps new photos safe. You can switch it off any time in Gallery backup.', textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Yes, back up')),
      ],
    ),
  );
  if (yes == true) {
    final err = await BackupService.turnOn();
    if (err != null && context.mounted) toast(context, err);
  } else {
    await Session.setBool('bk_asked', true);
    await Session.setBool('bk_on', false);
  }
}
