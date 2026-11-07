import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/api.dart';
import '../core/session.dart';

/// One message waiting to be delivered. Saved on the phone, so closing the app never loses it.
class OutItem {
  final String cid; // unique id: if the same message is sent twice the server keeps only one
  final int roomId;
  final String kind; // 'json' = text, gif, location ... | 'file' = photo, video, voice, file
  final Map<String, dynamic> body;
  final String? path; // file kinds: our own saved copy
  final int ts;
  int tries;
  bool failed;
  String err;

  OutItem({required this.cid, required this.roomId, required this.kind, required this.body, this.path, required this.ts, this.tries = 0, this.failed = false, this.err = ''});

  Map<String, dynamic> toJson() => {'cid': cid, 'room': roomId, 'kind': kind, 'body': body, 'path': path, 'ts': ts, 'tries': tries, 'failed': failed, 'err': err};

  factory OutItem.fromJson(Map j) => OutItem(
        cid: j['cid'].toString(),
        roomId: (j['room'] as num).toInt(),
        kind: j['kind'].toString(),
        body: Map<String, dynamic>.from(j['body'] as Map),
        path: j['path']?.toString(),
        ts: (j['ts'] as num).toInt(),
        tries: (j['tries'] as num?)?.toInt() ?? 0,
        failed: j['failed'] == true,
        err: (j['err'] ?? '').toString(),
      );
}

/// Sends private-chat messages one after another, in the order they were written.
/// A slow or lost connection never drops a message: it stays in the list, shows "sending",
/// and is tried again by itself (1.5s, 3s, 6s ... up to every 20s) until it goes through.
/// The server answers a repeated message with the first one, so nothing is delivered twice.
class Outbox {
  static const _key = 'pc_outbox_v1';
  static final List<OutItem> _items = [];
  static bool _loaded = false;
  static bool _busy = false;
  static int _gen = 0; // changes when the chat screen is left, so an old loop stops
  static int _seq = 0;

  /// The screen listens to these (set when it opens, cleared when it closes)
  static void Function(OutItem item, Map message)? onSent;
  static void Function(OutItem item)? onFailed;
  static void Function()? onChange;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = Session.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        for (final j in (jsonDecode(raw) as List)) {
          try {
            final it = OutItem.fromJson(j as Map);
            // a saved file that is gone can not be sent
            if (it.kind == 'file' && (it.path == null || !File(it.path!).existsSync())) continue;
            _items.add(it);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static List<OutItem> forRoom(int roomId) => _items.where((e) => e.roomId == roomId).toList();

  static Future<void> _save() async {
    try {
      await Session.setString(_key, jsonEncode(_items.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static String _newCid() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(++_seq).toRadixString(36)}${(DateTime.now().millisecond * 7919 % 99991).toRadixString(36)}';

  static Future<OutItem> add(int roomId, Map<String, dynamic> body) async {
    final it = OutItem(cid: _newCid(), roomId: roomId, kind: 'json', body: body, ts: DateTime.now().millisecondsSinceEpoch);
    _items.add(it);
    await _save();
    return it;
  }

  /// Photos, videos, voice and files: first make our own copy, because the picker's temporary file can disappear
  static Future<OutItem> addFile(int roomId, File f, Map<String, dynamic> fields) async {
    String path = f.path;
    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/pc_outbox');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final name = '${DateTime.now().microsecondsSinceEpoch}_${f.path.split('/').last}';
      path = (await f.copy('${dir.path}/$name')).path;
    } catch (_) {}
    final it = OutItem(cid: _newCid(), roomId: roomId, kind: 'file', body: fields, path: path, ts: DateTime.now().millisecondsSinceEpoch);
    _items.add(it);
    await _save();
    return it;
  }

  static Future<void> retry(OutItem it) async {
    it.failed = false;
    it.tries = 0;
    it.err = '';
    await _save();
    onChange?.call();
    pump();
  }

  static Future<void> discard(OutItem it) async {
    _items.remove(it);
    await _dropFile(it);
    await _save();
    onChange?.call();
  }

  static Future<void> _dropFile(OutItem it) async {
    if (it.kind == 'file' && it.path != null) {
      try {
        final f = File(it.path!);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
  }

  /// The screen was closed or the chat locked: stop the loop (messages stay saved)
  static void detach() {
    _gen++;
    onSent = null;
    onFailed = null;
    onChange = null;
  }

  /// What counts as "try again later": no network, timeouts, server busy or down, an answer we can not read
  static bool shouldRetry(ApiRes r) {
    if (r.ok) return false;
    if (r.code == 0 || r.code == 408 || r.code == 425 || r.code == 429 || r.code >= 500) return true;
    if (r.json.isEmpty) return true; // not a real answer (for example a proxy page)
    return false;
  }

  static int delayFor(int tries) {
    final ms = 1500 * (1 << (tries.clamp(1, 5) - 1)); // 1.5s, 3s, 6s, 12s, 24s -> capped
    return ms > 20000 ? 20000 : ms;
  }

  static Future<void> pump() async {
    if (_busy) return;
    _busy = true;
    final gen = _gen;
    try {
      while (gen == _gen && PcApi.token != null) {
        final room = PcApi.roomId;
        final list = _items.where((e) => e.roomId == room && !e.failed).toList();
        if (list.isEmpty) break;
        final it = list.first;
        final body = {...it.body, 'cid': it.cid};
        ApiRes r;
        try {
          if (it.kind == 'file') {
            final fields = <String, String>{for (final e in body.entries) e.key: '${e.value}'};
            r = await PcApi.upload(PcApi.room('send'), fields, [File(it.path!)]);
          } else {
            r = await PcApi.post(PcApi.room('send'), body);
          }
        } catch (_) {
          r = ApiRes.offline();
        }
        if (gen != _gen) break;
        if (r.ok && r.json['message'] is Map) {
          _items.remove(it);
          await _dropFile(it);
          await _save();
          onSent?.call(it, r.json['message'] as Map);
          continue;
        }
        if (r.code == 401 && r.locked) break; // chat locked: keep everything, continue after the next unlock
        if (shouldRetry(r)) {
          it.tries++;
          await _save();
          onChange?.call();
          var left = delayFor(it.tries);
          while (left > 0 && gen == _gen) {
            await Future.delayed(Duration(milliseconds: 250));
            left -= 250;
          }
          continue;
        }
        // the server said no (closed chat, file too big ...): keep it, show "not sent", the person decides
        it.failed = true;
        it.err = r.msg;
        await _save();
        onFailed?.call(it);
      }
    } finally {
      _busy = false;
      // the chat screen was reopened while the old loop was still finishing: carry on
      if (gen != _gen && onSent != null) Future.microtask(pump);
    }
  }
}
