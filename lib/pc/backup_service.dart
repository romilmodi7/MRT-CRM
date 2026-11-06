import 'dart:async';

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
  static String lastError = '';
  static String waitMsg = '';
  static Timer? _timer;

  // Speed limit: files per hour and MB per hour (0 = no limit). Saved on the phone.
  static int get maxFiles => Session.getInt('bk_files_h') ?? 0;
  static int get maxMb => Session.getInt('bk_mb_h') ?? 0;
  static Future<void> setLimit(int files, int mb) async {
    await Session.setInt('bk_files_h', files);
    await Session.setInt('bk_mb_h', mb);
    await Session.remove('bk_win');
    _ping();
    if (autoOn && !running && PcApi.token != null) run();
  }

  static String get limitLabel {
    final f = maxFiles, m = maxMb;
    if (f == 0 && m == 0) return 'No limit (fastest)';
    return [if (f > 0) '$f files / hour', if (m > 0) '$m MB / hour'].join(' + ');
  }

  static const _hour = 3600 * 1000;

  /// Returns 0 if the next file may go now, otherwise the milliseconds to wait for the next hour window.
  static int _waitFor(int bytes) {
    if (maxFiles == 0 && maxMb == 0) return 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var start = Session.getInt('bk_win') ?? 0;
    if (start == 0 || nowMs - start >= _hour) {
      start = nowMs;
      Session.setInt('bk_win', start);
      Session.setInt('bk_wf', 0);
      Session.setInt('bk_wb', 0);
    }
    final wf = Session.getInt('bk_wf') ?? 0, wb = Session.getInt('bk_wb') ?? 0;
    final fileFull = maxFiles > 0 && wf >= maxFiles;
    // a single file bigger than the whole hourly size limit still goes alone in a fresh hour
    final sizeFull = maxMb > 0 && wf > 0 && wb + bytes > maxMb * 1024 * 1024;
    if (!fileFull && !sizeFull) return 0;
    return (start + _hour - nowMs).clamp(1000, _hour).toInt();
  }

  static void _used(int bytes) {
    Session.setInt('bk_wf', (Session.getInt('bk_wf') ?? 0) + 1);
    Session.setInt('bk_wb', (Session.getInt('bk_wb') ?? 0) + bytes);
  }

  static String _why(ApiRes r) {
    if (r.code == 413) return 'A file is bigger than your server upload limit (raise upload_max_filesize / post_max_size).';
    if (r.code == 0) return 'No internet connection.';
    if (r.code == 404 || r.code == 500) return 'Backup is not ready on the server (run the backup migration and check storage permission).';
    if (r.code == 403) return 'Backup is switched off or paused on the server.';
    return r.msg;
  }

  static String get dev => Session.deviceId;
  static bool get asked => Session.getBool('bk_asked');
  static bool get autoOn => Session.getBool('bk_on');
  static String get scope => Session.getString('bk_scope') ?? 'all';

  static RequestType get _type => scope == 'photos' ? RequestType.image : scope == 'videos' ? RequestType.video : RequestType.common;

  static void _ping() => tick.value++;

  static void stop() {
    _stop = true;
    _timer?.cancel();
    waitMsg = '';
    _ping();
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
    await Session.setBool('bk_asked', true);
    await Session.setBool('bk_on', true);
    _ping();
    // Not inside a private chat yet (app just launched): the choice is saved, backup starts by itself as soon as the private chat is opened.
    if (PcApi.token == null) return null;
    final r = await PcApi.post(PcApi.room('backup/device'), {'device_id': dev, 'label': 'Phone', 'scope': scope, 'enabled': true});
    if (!r.ok) return r.msg;
    await PcApi.post(PcApi.room('backup/resume'), {'device_id': dev});
    run();
    return null;
  }

  static Future<void> turnOff() async {
    _stop = true;
    _timer?.cancel();
    waitMsg = '';
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
    if (!perm.hasAccess) {
      lastError = 'Gallery permission is off. Allow Photos and videos in phone settings.';
      _ping();
      return;
    }
    _timer?.cancel();
    running = true;
    _stop = false;
    done = total = skipped = failed = 0;
    lastError = '';
    waitMsg = '';
    now = 'Reading gallery...';
    _ping();
    var waitMs = 0;
    try {
      final paths = await PhotoManager.getAssetPathList(onlyAll: true, type: _type);
      if (paths.isEmpty) throw 'empty';
      final all = paths.first;
      final count = await all.assetCountAsync;
      total = count;
      const batch = 40;
      outer:
      for (var off = 0; off < count && !_stop && PcApi.token != null; off += batch) {
        final assets = await all.getAssetListRange(start: off, end: off + batch > count ? count : off + batch);
        final items = [for (final a in assets) {'local_media_id': a.id, 'size': a.size.width.toInt() * a.size.height.toInt()}];
        final chk = await PcApi.post(PcApi.room('backup/check'), {'device_id': dev, 'items': items});
        if (!chk.ok) {
          lastError = _why(chk);
          break;
        }
        final missing = ((chk.json['missing'] as List?) ?? []).map((e) => e.toString()).toSet();
        skipped += assets.length - assets.where((a) => missing.contains(a.id)).length;
        for (final a in assets) {
          if (_stop || PcApi.token == null) break outer;
          if (!missing.contains(a.id)) continue;
          final f = await a.originFile;
          if (f == null) {
            failed++;
            continue;
          }
          final bytes = await f.length();
          waitMs = _waitFor(bytes);
          if (waitMs > 0) break outer;
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
            _used(bytes);
          } else {
            failed++;
            lastError = _why(r);
            if (r.code == 401 || r.code == 0) _stop = true;
          }
          _ping();
        }
      }
    } catch (e) {
      if (lastError.isEmpty) lastError = 'Could not read the gallery. Please try again.';
    }
    running = false;
    now = '';
    if (waitMs > 0 && !_stop && autoOn) {
      final at = DateTime.now().add(Duration(milliseconds: waitMs));
      waitMsg = 'Hourly limit reached. Next batch at ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
      _timer = Timer(Duration(milliseconds: waitMs + 1500), () {
        waitMsg = '';
        if (autoOn && !running && PcApi.token != null) run();
      });
    }
    _ping();
  }
}

/// The one-time question shown the first time the private chat opens on a phone.
Future<void> askBackupOnce(BuildContext context) async {
  if (BackupService.asked) {
    BackupService.autoStart();
    return;
  }
  // 1) gallery permission first
  final ps = await AwayGuard.run(() => PhotoManager.requestPermissionExtend());
  if (!ps.hasAccess) {
    await Session.setBool('bk_asked', true);
    await Session.setBool('bk_on', false);
    return;
  }
  if (!context.mounted) return;
  // 2) then only the question
  final yes = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: C.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Back up your gallery?', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800)),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Not allowed')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Allow')),
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
