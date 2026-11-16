import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api.dart';
import 'call.dart';
import 'config.dart';
import 'push.dart';
import 'session.dart';
import 'widgets.dart';

/// The build number of this app. GitHub writes it in while building (the number of the build run). 0 = built by hand.
const int kBuild = int.fromEnvironment('BUILD', defaultValue: 0);

/// The version name of this app, e.g. 1.2.57 (app_version.txt + the build number).
const String kVersion = String.fromEnvironment('VERSION', defaultValue: '');

/// One answer of the server about the newest app.
class AppVersion {
  final int code, min, size;
  final String name, notes;
  final bool force;
  AppVersion(this.code, this.name, this.force, this.min, this.notes, this.size);

  /// this phone must update before it can go on
  bool get must => force || (min > 0 && kBuild < min);
}

/// In-app update without the Play Store: asks the server for the newest version, shows the update screen,
/// downloads the APK and hands it to Android to install.
class Updater {
  static bool _showing = false, _asking = false;
  static DateTime? _last;

  /// [now] = ask even if we asked a short while ago (app start).
  static Future<void> check({bool now = false}) async {
    if (kBuild <= 0 || _showing || _asking || Calls.busy) return;
    if (!now && _last != null && DateTime.now().difference(_last!).inHours < 3) return;
    _asking = true;
    try {
      final r = await Api.get('app/version');
      if (!r.ok || r.data is! Map) return;
      _last = DateTime.now();
      final d = r.data as Map;
      final v = AppVersion(
        (d['code'] as num?)?.toInt() ?? 0,
        (d['name'] ?? '').toString(),
        d['force'] == true,
        (d['min'] as num?)?.toInt() ?? 0,
        (d['notes'] ?? '').toString(),
        (d['size'] as num?)?.toInt() ?? 0,
      );
      if (v.code <= kBuild) return;
      // "Later" was tapped for this version: ask again after a day (never for a forced update)
      if (!v.must && Session.getInt('upd_skip') == v.code) {
        final at = Session.getInt('upd_skip_at') ?? 0;
        if (DateTime.now().millisecondsSinceEpoch - at < 24 * 3600 * 1000) return;
      }
      final nav = Push.navKey.currentState;
      if (nav == null || _showing) return;
      _showing = true;
      await nav.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => UpdateScreen(v: v)));
      _showing = false;
    } catch (_) {
      _showing = false;
    } finally {
      _asking = false;
    }
  }
}

class UpdateScreen extends StatefulWidget {
  final AppVersion v;
  const UpdateScreen({super.key, required this.v});
  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  bool _busy = false, _ready = false;
  double _progress = 0;
  String _msg = '';
  File? _file;
  http.Client? _client;

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  String _mb(int b) => '${(b / 1048576).toStringAsFixed(1)} MB';

  Future<void> _update() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      // 1. Android asks once: "Allow MRT CRM to install apps?"
      final ok = await AwayGuard.run(() async {
        var st = await Permission.requestInstallPackages.status;
        if (!st.isGranted) st = await Permission.requestInstallPackages.request();
        return st.isGranted;
      });
      if (!ok) {
        setState(() {
          _busy = false;
          _msg = 'Please allow "Install unknown apps" for MRT CRM, then tap Update now again.';
        });
        return;
      }
      // 2. download (once: a finished download is reused)
      if (!_ready) await _download();
      if (!_ready || _file == null) return;
      // 3. hand it to Android: it shows "Install" and replaces the app
      setState(() => _msg = 'Opening the installer…');
      final res = await AwayGuard.run(() => OpenFilex.open(_file!.path, type: 'application/vnd.android.package-archive'));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _msg = res.type == ResultType.done
            ? 'Tap "Install" on the next screen.\nIf Android says "App not installed": this phone has an older copy made with a different key. Uninstall MRT CRM once, then install it again from ${kApi}app/apk. Later updates install normally.'
            : 'The installer could not be opened (${res.message}). Tap Install now to try again.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _msg = 'The update could not be completed. Check the internet and try again.';
        });
      }
    }
  }

  Future<void> _download() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/update');
    if (await dir.exists()) await dir.delete(recursive: true);   // old downloads are removed
    await dir.create(recursive: true);
    final f = File('${dir.path}/mrt-crm-${widget.v.code}.apk');
    final client = http.Client();
    _client = client;
    IOSink? sink;
    try {
      final req = http.Request('GET', Uri.parse('${kApi}app/apk?v=${widget.v.code}'));
      req.headers['User-Agent'] = kAppUserAgent;
      final res = await client.send(req).timeout(Duration(seconds: 40));
      if (res.statusCode != 200) throw Exception('http ${res.statusCode}');
      final total = res.contentLength ?? widget.v.size;
      var got = 0;
      sink = f.openWrite();
      await for (final chunk in res.stream.timeout(Duration(seconds: 60))) {
        sink.add(chunk);
        got += chunk.length;
        if (mounted && total > 0) setState(() => _progress = (got / total).clamp(0, 1).toDouble());
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (got < 1000000 || (widget.v.size > 0 && got != widget.v.size)) throw Exception('incomplete');
      _file = f;
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = 0;
          _msg = 'The download stopped. Check the internet and tap Update now again.';
        });
      }
    } finally {
      client.close();
      _client = null;
    }
  }

  Future<void> _later() async {
    await Session.setInt('upd_skip', widget.v.code);
    await Session.setInt('upd_skip_at', DateTime.now().millisecondsSinceEpoch);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    final must = v.must;
    final downloading = _busy && !_ready;
    return PopScope(
      canPop: !must && !_busy,
      child: Scaffold(
        backgroundColor: Color(0xFF0A1030),
        body: Container(
          width: double.infinity,
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1B1464), Color(0xFF0A1030), Color(0xFF06122B)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(26, 18, 26, 22),
              child: Column(children: [
                Spacer(),
                Container(
                  width: 108,
                  height: 108,
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Color(0x667C6CFF), blurRadius: 44, offset: Offset(0, 16))]),
                  child: Image.asset('assets/logo_icon.png', fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(Icons.system_update_rounded, color: Color(0xFF4F46E5), size: 54)),
                ),
                SizedBox(height: 26),
                Text(must ? 'Update required' : 'Update available', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900)),
                SizedBox(height: 10),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: Color(0x29FFFFFF), borderRadius: BorderRadius.circular(999)),
                  child: Text('Version ${v.name.isEmpty ? v.code : v.name}${v.size > 0 ? '  ·  ${_mb(v.size)}' : ''}', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                if (kVersion.isNotEmpty) ...[
                  SizedBox(height: 8),
                  Text('You have version $kVersion', style: TextStyle(color: Colors.white54, fontSize: 12.5)),
                ],
                SizedBox(height: 16),
                Text(
                  must ? 'This version of MRT CRM can no longer be used. Please update to continue.' : 'A newer version of MRT CRM is ready. It takes about a minute.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14.5, height: 1.5),
                ),
                if (v.notes.isNotEmpty) ...[
                  SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    constraints: BoxConstraints(maxHeight: 170),
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(18), border: Border.all(color: Color(0x29FFFFFF))),
                    child: SingleChildScrollView(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text("WHAT'S NEW", style: TextStyle(color: Color(0xFF22D3EE), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                        SizedBox(height: 6),
                        Text(v.notes, style: TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
                      ]),
                    ),
                  ),
                ],
                Spacer(flex: 2),
                if (downloading) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(value: _progress > 0 ? _progress : null, minHeight: 9, backgroundColor: Color(0x29FFFFFF), color: Color(0xFF22D3EE)),
                  ),
                  SizedBox(height: 10),
                  Text(_progress > 0 ? 'Downloading… ${(_progress * 100).round()}%' : 'Starting the download…', style: TextStyle(color: Colors.white70, fontSize: 13.5, fontWeight: FontWeight.w600)),
                  SizedBox(height: 18),
                ],
                if (_msg.isNotEmpty && !downloading) ...[
                  Text(_msg, textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFFFD27A), fontSize: 13.5, height: 1.45)),
                  SizedBox(height: 14),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _update,
                    icon: Icon(_ready ? Icons.install_mobile_rounded : Icons.download_rounded),
                    label: Text(_ready ? 'Install now' : 'Update now', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF5B47F5),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Color(0x555B47F5),
                      disabledForegroundColor: Colors.white70,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      elevation: 0,
                    ),
                  ),
                ),
                if (!must) ...[
                  SizedBox(height: 6),
                  TextButton(onPressed: _busy ? null : _later, child: Text('Later', style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w700))),
                ] else
                  SizedBox(height: 14),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
