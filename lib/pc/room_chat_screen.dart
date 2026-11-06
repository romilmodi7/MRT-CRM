import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../core/api.dart';
import '../core/appearance.dart';
import '../core/platform.dart';
import '../core/session.dart';
import '../core/stickers.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import '../screens/login_screen.dart';
import 'backup_screen.dart';
import 'backup_service.dart';
import 'location_screen.dart';
import 'pc_models.dart';
import 'pc_widgets.dart';

/// One private room. Used by the owner (opened from the PIN door) and by a room user (signed in with username + password).
class RoomChatScreen extends StatefulWidget {
  final Map<String, dynamic> info;
  const RoomChatScreen({super.key, required this.info});
  @override
  State<RoomChatScreen> createState() => _RoomChatScreenState();
}

class _RoomChatScreenState extends State<RoomChatScreen> with WidgetsBindingObserver, AwayLock<RoomChatScreen> {
  final List<PcMsg> _msgs = [];
  final Set<int> _ids = {};
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  late final Poller _tick = Poller(Duration(seconds: 2), _poll);

  int _last = 0;
  bool _more = true, _loadingOld = false, _first = true;
  bool _showDeleted = false;
  PcMsg? _reply;
  PcMsg? _editing;
  Map? _pin;
  bool _peerOnline = false, _peerTyping = false, _active = true;
  int? _peerSeen;
  String _theme = 'aurora';
  String? _localBg = Session.getString('pc_bg');
  bool _showFab = false;
  int _unseen = 0;
  bool _typingShown = false;
  int _tmp = 0;
  DateTime _lastTyping = DateTime(2000);

  // search
  bool _searchOn = false;
  Set<int> _hits = {};
  final _searchCtl = TextEditingController();

  // voice
  final AudioRecorder _rec = AudioRecorder();
  bool _recording = false;
  DateTime? _recAt;
  Timer? _recTimer;
  int _recSecs = 0;
  double _recDrag = 0;

  bool get _owner => PcApi.owner;

  // The owner's private chat locks after 10 minutes without touching the screen, or when the app is closed.
  DateTime _lastTouch = DateTime.now();
  late final Poller _idle = Poller(const Duration(seconds: 15), () async {
    if (_owner && DateTime.now().difference(_lastTouch).inMinutes >= 10) _lock();
  });
  Map get _room => (widget.info['room'] as Map?) ?? {};
  String get _title => _owner ? (_room['title'] ?? '').toString() : (widget.info['peer_name'] ?? _room['title'] ?? '').toString();
  List<String> get _reactions => ((widget.info['reactions'] as List?) ?? ['❤️', '👍', '😂', '😮', '😢', '🙏']).map((e) => e.toString()).toList();

  @override
  void initState() {
    super.initState();
    awayInit();
    Secure.on();
    _theme = (_room['theme'] ?? 'aurora').toString();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPalette());
    if (!_owner) PcApi.roomId = ((_room['id'] as num?) ?? 0).toInt();
    PcApi.onLocked = _onLocked;
    _input.addListener(_onTyping);
    _poll();
    _tick.start();
    _idle.start();
    // first time on this phone: ask "back up your gallery?"; if they said yes before, it starts by itself
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(Duration(milliseconds: 900));
      if (mounted) askBackupOnce(context);
    });
  }

  @override
  void dispose() {
    awayDispose();
    _tick.stop();
    _idle.stop();
    _recTimer?.cancel();
    _rec.dispose();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    _searchCtl.dispose();
    Secure.off();
    MemCache.clear();
    wipePcTmp();
    WidgetsBinding.instance.addPostFrameCallback((_) => ThemeCtl.apply(WidgetsBinding.instance.platformDispatcher.platformBrightness));
    super.dispose();
  }

  @override
  void onAwayLock() {
    if (_owner) _lock();
  }

  @override
  void onLifecycle(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _tick.start();
      _poll();
    } else if (s == AppLifecycleState.paused) {
      _tick.stop();
    }
  }

  bool get _appDark => ThemeCtl.resolve(WidgetsBinding.instance.platformDispatcher.platformBrightness);

  /// Key of the background in use: this phone's choice, else the room's.
  String get _bgKey {
    final l = _localBg;
    if (l == null || l.isEmpty) return kThemes.containsKey(_theme) ? _theme : 'aurora';
    if (l == 'auto') return _appDark ? 'aurora' : 'pearl';
    return kThemes.containsKey(l) ? l : 'aurora';
  }

  /// Light backgrounds use the light palette for bubbles and text, dark ones the dark palette.
  void _syncPalette() {
    final wantDark = !themeIsLight(_bgKey);
    if (C.dark == wantDark) return;
    C.dark = wantDark;
    ThemeCtl.tick.value++;
    ThemeCtl.rebuildAll();
  }

  Future<void> _setBg(String key) async {
    setState(() => _localBg = key);
    await Session.setString('pc_bg', key);
    if (_owner && key != 'auto') PcApi.post(PcApi.room('theme'), {'theme': key});
    _syncPalette();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final far = _scroll.position.maxScrollExtent - _scroll.position.pixels > 320;
    if (far != _showFab || (!far && _unseen != 0)) {
      setState(() {
        _showFab = far;
        if (!far) _unseen = 0;
      });
    }
  }

  void _onLocked(String why) {
    if (!mounted) return;
    if (_owner) {
      _lock();
    } else {
      _signedOut();
    }
  }

  /// Lock: back to the employee chat list. The PIN is needed again.
  void _lock() {
    if (!mounted) return;
    PcApi.forget();
    MemCache.clear();
    wipePcTmp();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _signOut() async {
    if (!await confirm(context, 'Sign out of this private chat? You will need the username and password again.', yes: 'Sign out')) return;
    await PcApi.post('room/signout');
    _signedOut();
  }

  Future<void> _signedOut() async {
    await Session.clearRoom();
    PcApi.forget();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => LoginScreen()), (_) => false);
  }

  // ------------------------------------------------------------------ polling

  Future<void> _poll() async {
    final q = {'after': '$_last', 'visible': '1', if (_owner && _showDeleted) 'hidden': '1'};
    final r = await PcApi.get(PcApi.room('poll'), q);
    if (!mounted || !r.ok) return;
    final j = r.json;
    final fresh = ((j['messages'] as List?) ?? []).whereType<Map>().map(PcMsg.from).toList();
    var added = false, incoming = false;
    for (final m in fresh) {
      if (_ids.contains(m.id)) continue;
      _ids.add(m.id);
      _msgs.add(m);
      added = true;
      if (!m.mine) incoming = true;
      if (m.id > _last) _last = m.id;
    }
    if (added) _msgs.sort((a, b) => a.id.compareTo(b.id));
    for (final mt in ((j['meta'] as List?) ?? []).whereType<Map>()) {
      final id = (mt['id'] as num?)?.toInt();
      final i = _msgs.indexWhere((x) => x.id == id);
      if (i < 0) continue;
      final m = _msgs[i];
      m.tick = (mt['tick'] as num?)?.toInt() ?? m.tick;
      m.st = (mt['st'] ?? m.st).toString();
      m.note = mt['note']?.toString();
      m.rx = PcMsg.parseRx(mt['rx']);
      if (mt['ed'] == 1) {
        m.edited = true;
        if (mt['body'] != null) m.body = mt['body'].toString();
      }
      if (m.st == 'hide') {
        _msgs.removeAt(i);
        _ids.remove(id);
      } else if (m.st == 'gone' && !_owner) {
        m.type = 'gone';
      }
    }
    if (!_first && incoming) Sound.ping();
    final peer = j['peer'];
    setState(() {
      _pin = j['pin'] is Map ? j['pin'] as Map : null;
      if (peer is Map) {
        _peerOnline = peer['online'] == true;
        _peerTyping = peer['typing'] == true;
        _peerSeen = (peer['seen'] as num?)?.toInt();
      }
      _theme = (j['theme'] ?? _theme).toString();
      _active = j['active'] != false;
    });
    _syncPalette();
    if (added && incoming && !_first && !_nearBottom()) setState(() => _unseen += fresh.where((m) => !m.mine).length);
    if (_first || (added && _nearBottom())) _toBottom(jump: _first);
    _first = false;
  }

  bool _nearBottom() => !_scroll.hasClients || _scroll.position.maxScrollExtent - _scroll.position.pixels < 160;

  void _toBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final t = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(t);
      } else {
        _scroll.animateTo(t, duration: Duration(milliseconds: 260), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _loadOlder() async {
    if (_loadingOld || !_more || _msgs.isEmpty) return;
    _loadingOld = true;
    final before = _msgs.firstWhere((m) => m.id > 0, orElse: () => _msgs.first).id;
    final r = await PcApi.get(PcApi.room('history'), {'before': '$before', if (_owner && _showDeleted) 'hidden': '1'});
    _loadingOld = false;
    if (!mounted || !r.ok) return;
    final old = ((r.json['messages'] as List?) ?? []).whereType<Map>().map(PcMsg.from).where((m) => !_ids.contains(m.id)).toList();
    final oldMax = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    setState(() {
      for (final m in old) {
        _ids.add(m.id);
      }
      _msgs.insertAll(0, old);
      _more = r.json['more'] == true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.pixels + (_scroll.position.maxScrollExtent - oldMax));
    });
  }

  void _onTyping() {
    if (_input.text.isNotEmpty && DateTime.now().difference(_lastTyping).inSeconds >= 3) {
      _lastTyping = DateTime.now();
      PcApi.post(PcApi.room('typing'));
    }
    setState(() {});
  }

  // ------------------------------------------------------------------ sending

  Future<void> _sendText() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    if (_editing != null) {
      final e = _editing!;
      setState(() {
        _editing = null;
        _input.clear();
      });
      final r = await PcApi.post(PcApi.room('edit'), {'id': e.id, 'body': body});
      if (!mounted) return;
      if (r.ok) {
        setState(() {
          e.body = body;
          e.edited = true;
        });
      } else {
        toast(context, r.msg);
      }
      return;
    }
    final rep = _reply;
    _input.clear();
    setState(() => _reply = null);
    await _sendMsg({'type': 'text', 'body': body, if (rep != null) 'reply': rep.id}, PcMsg(id: -(++_tmp), mine: true, ts: DateTime.now().millisecondsSinceEpoch ~/ 1000, tick: 0, type: 'text', body: body, pending: true));
  }

  Future<void> _sendMsg(Map<String, dynamic> body, PcMsg pend) async {
    setState(() {
      _msgs.add(pend);
      _ids.add(pend.id);
    });
    _toBottom();
    final r = await PcApi.post(PcApi.room('send'), body);
    if (!mounted) return;
    _finishSend(r, pend, () => _sendMsg(body, pend));
  }

  void _finishSend(ApiRes r, PcMsg pend, VoidCallback retry) {
    final idx = _msgs.indexOf(pend);
    if (r.ok && r.json['message'] is Map) {
      final real = PcMsg.from(r.json['message'] as Map);
      setState(() {
        if (idx >= 0) _msgs.removeAt(idx);
        _ids.remove(pend.id);
        if (!_ids.contains(real.id)) {
          _ids.add(real.id);
          _msgs.add(real);
          _msgs.sort((a, b) => a.id.compareTo(b.id));
          if (real.id > _last) _last = real.id;
        }
      });
      _toBottom();
    } else {
      setState(() {
        pend.pending = false;
        pend.failed = true;
        pend.body = pend.body;
      });
      toast(context, r.msg);
    }
  }

  Future<void> _sendFile(File f, {bool voice = false, int dur = 0, String? caption}) async {
    final mime = mimeOf(f.path);
    final type = voice ? 'audio' : mime.startsWith('image/') ? 'image' : mime.startsWith('video/') ? 'video' : mime.startsWith('audio/') ? 'audio' : 'file';
    final rep = _reply;
    setState(() => _reply = null);
    final pend = PcMsg(
      id: -(++_tmp), mine: true, ts: DateTime.now().millisecondsSinceEpoch ~/ 1000, tick: 0, type: type, pending: true, localPath: f.path,
      mediaName: f.path.split('/').last, dur: dur, size: f.existsSync() ? f.lengthSync() : 0, body: caption,
    );
    setState(() {
      _msgs.add(pend);
      _ids.add(pend.id);
    });
    _toBottom();
    final r = await PcApi.upload(PcApi.room('send'), {'type': 'media', if (voice) 'voice': '1', if (voice) 'dur': '$dur', if (rep != null) 'reply': '${rep.id}', if (caption != null) 'body': caption}, [f]);
    if (!mounted) return;
    _finishSend(r, pend, () {
      _msgs.remove(pend);
      _ids.remove(pend.id);
      _sendFile(f, voice: voice, dur: dur, caption: caption);
    });
  }

  Future<void> _attach() async {
    final maxMb = ((widget.info['max_mb'] as num?) ?? 50).toInt();
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 14),
          child: Wrap(alignment: WrapAlignment.center, spacing: 22, runSpacing: 18, children: [
            _AttachBtn(Icons.photo_library_rounded, 'Gallery', Color(0xFF7C6CFF), () => Navigator.pop(context, 'gallery')),
            _AttachBtn(Icons.photo_camera_rounded, 'Camera', Color(0xFFFF5FA8), () => Navigator.pop(context, 'camera')),
            _AttachBtn(Icons.videocam_rounded, 'Video', Color(0xFFFF8A5F), () => Navigator.pop(context, 'video')),
            _AttachBtn(Icons.insert_drive_file_rounded, 'File', Color(0xFF22D3EE), () => Navigator.pop(context, 'file')),
            _AttachBtn(Icons.location_on_rounded, 'Location', Color(0xFF36E0A6), () => Navigator.pop(context, 'loc')),
            _AttachBtn(Icons.emoji_emotions_rounded, 'Stickers', Color(0xFFFFB347), () => Navigator.pop(context, 'stk')),
            _AttachBtn(Icons.gif_box_rounded, 'GIF', Color(0xFFB06CFF), () => Navigator.pop(context, 'gif')),
          ]),
        ),
      ),
    );
    if (pick == null || !mounted) return;
    try {
      if (pick == 'gallery') {
        final xs = await AwayGuard.run(() => ImagePicker().pickMultipleMedia(limit: 10));
        for (final x in xs) {
          await _sendIfSmall(File(x.path), maxMb);
        }
      } else if (pick == 'camera') {
        final x = await AwayGuard.run(() => ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 88));
        if (x != null) await _sendIfSmall(File(x.path), maxMb);
      } else if (pick == 'video') {
        final x = await AwayGuard.run(() => ImagePicker().pickVideo(source: ImageSource.camera, maxDuration: Duration(minutes: 5)));
        if (x != null) await _sendIfSmall(File(x.path), maxMb);
      } else if (pick == 'file') {
        final r = await AwayGuard.run(() => FilePicker.platform.pickFiles(allowMultiple: true));
        if (r != null) {
          for (final f in r.files) {
            if (f.path != null) await _sendIfSmall(File(f.path!), maxMb);
          }
        }
      } else if (pick == 'loc') {
        await _sendLocation();
      } else if (pick == 'stk') {
        await _stickers();
      } else if (pick == 'gif') {
        await _gifs();
      }
    } catch (_) {
      if (mounted) toast(context, 'Could not open that. Check the permission in Settings.');
    }
  }

  Future<void> _sendIfSmall(File f, int maxMb) async {
    if (f.lengthSync() > maxMb * 1048576) {
      if (mounted) toast(context, '"${f.path.split('/').last}" is bigger than $maxMb MB.');
      return;
    }
    await _sendFile(f);
  }

  Future<void> _sendLocation() async {
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await AwayGuard.run(() => Geolocator.requestPermission());
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      if (mounted) toast(context, 'Location permission is needed.');
      return;
    }
    if (mounted) toast(context, 'Getting your location...');
    final pos = await Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
    await _sendMsg({'type': 'location', 'body': {'lat': pos.latitude, 'lng': pos.longitude}}, PcMsg(id: -(++_tmp), mine: true, ts: DateTime.now().millisecondsSinceEpoch ~/ 1000, tick: 0, type: 'location', body: '{"lat":${pos.latitude},"lng":${pos.longitude}}', pending: true));
  }

  Future<void> _stickers() async {
    final st = await pickSticker(context, roomPack: widget.info['stickers'] is Map ? widget.info['stickers'] as Map : null);
    if (st == null || !mounted) return;
    final body = StickerMsg.encode(st);
    await _sendMsg({'type': 'text', 'body': body}, PcMsg(id: -(++_tmp), mine: true, ts: DateTime.now().millisecondsSinceEpoch ~/ 1000, tick: 0, type: 'text', body: body, pending: true));
  }

  Future<void> _gifs() async {
    final url = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => const _GifSheet(),
    );
    if (url == null) return;
    await _sendMsg({'type': 'gif', 'gif': url}, PcMsg(id: -(++_tmp), mine: true, ts: DateTime.now().millisecondsSinceEpoch ~/ 1000, tick: 0, type: 'gif', gif: url, pending: true));
  }

  // ------------------------------------------------------------------ voice

  Future<void> _recStart() async {
    try {
      if (!await AwayGuard.run(() => _rec.hasPermission())) {
        if (mounted) toast(context, 'Microphone permission is needed.');
        return;
      }
      final d = await pcTmp();
      final path = '${d.path}/v${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100), path: path);
      HapticFeedback.mediumImpact();
      _recAt = DateTime.now();
      _recTimer = Timer.periodic(Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recSecs = DateTime.now().difference(_recAt!).inSeconds);
      });
      setState(() {
        _recording = true;
        _recSecs = 0;
        _recDrag = 0;
      });
    } catch (_) {
      if (mounted) toast(context, 'Could not start recording.');
    }
  }

  Future<void> _recStop({required bool send}) async {
    if (!_recording) return;
    _recTimer?.cancel();
    final secs = _recAt == null ? 0 : DateTime.now().difference(_recAt!).inSeconds;
    setState(() => _recording = false);
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    if (path == null) return;
    final f = File(path);
    if (!send || secs < 1) {
      if (f.existsSync()) f.deleteSync();
      if (send && mounted) toast(context, 'Hold the mic to record');
      return;
    }
    await _sendFile(f, voice: true, dur: secs);
  }

  // ------------------------------------------------------------------ actions on a message

  Future<void> _actions(PcMsg m) async {
    HapticFeedback.selectionClick();
    final isText = m.type == 'text';
    final canEdit = m.mine && isText && m.st == 'ok';
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 14),
          Wrap(spacing: 6, children: [
            for (final e in _reactions)
              GestureDetector(onTap: () => Navigator.pop(context, 'rx:$e'), child: Padding(padding: EdgeInsets.all(6), child: Text(e, style: TextStyle(fontSize: 30)))),
          ]),
          Divider(color: C.g2),
          if (m.st != 'ghost') _a(Icons.reply_rounded, 'Reply', 'reply'),
          if (isText) _a(Icons.copy_rounded, 'Copy', 'copy'),
          if (canEdit) _a(Icons.edit_rounded, 'Edit', 'edit'),
          _a(Icons.push_pin_rounded, (_pin != null && _pin!['id'] == m.id) ? 'Unpin' : 'Pin', 'pin'),
          if (_owner && m.st == 'ghost') _a(Icons.restore_rounded, 'Restore', 'restore'),
          if (m.st != 'ghost') _a(Icons.visibility_off_rounded, 'Delete for me', 'me'),
          if (m.mine && m.st != 'ghost') _a(Icons.delete_forever_rounded, 'Delete for everyone', 'all', color: C.danger),
          SizedBox(height: 8),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    if (action.startsWith('rx:')) {
      final r = await PcApi.post(PcApi.room('react'), {'id': m.id, 'emoji': action.substring(3)});
      if (mounted && r.ok) setState(() => m.rx = PcMsg.parseRx(r.json['rx']));
    } else if (action == 'reply') {
      setState(() {
        _reply = m;
        _editing = null;
      });
      _focus.requestFocus();
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.body ?? ''));
      if (mounted) toast(context, 'Copied');
    } else if (action == 'edit') {
      setState(() {
        _editing = m;
        _reply = null;
        _input.text = m.body ?? '';
      });
      _focus.requestFocus();
    } else if (action == 'pin') {
      await PcApi.post(PcApi.room('pin'), {'id': m.id});
      _poll();
    } else if (action == 'restore') {
      await PcApi.post(PcApi.room('delete'), {'ids': [m.id], 'scope': 'restore'});
      setState(() => m.st = 'ok');
      _poll();
    } else if (action == 'me' || action == 'all') {
      if (!await confirm(context, action == 'all' ? 'Delete this message for everyone?' : 'Delete this message for you?', yes: 'Delete')) return;
      final r = await PcApi.post(PcApi.room('delete'), {'ids': [m.id], 'scope': action});
      if (!mounted) return;
      if (r.ok) {
        setState(() {
          if (action == 'me' || !_owner) {
            _msgs.remove(m);
            _ids.remove(m.id);
          } else {
            m.st = _showDeleted ? 'ghost' : 'hide';
            if (!_showDeleted) {
              _msgs.remove(m);
              _ids.remove(m.id);
            }
          }
        });
      } else {
        toast(context, r.msg);
      }
    }
  }

  Widget _a(IconData i, String t, String v, {Color? color}) => ListTile(dense: true, leading: Icon(i, color: color ?? C.accent2), title: Text(t, style: TextStyle(color: color ?? C.text)), onTap: () => Navigator.pop(context, v));

  // ------------------------------------------------------------------ search / menu

  Future<void> _runSearch(String q) async {
    q = q.trim();
    if (q.isEmpty) {
      setState(() => _hits = {});
      return;
    }
    final r = await PcApi.get(PcApi.room('search'), {'q': q, if (_owner && _showDeleted) 'hidden': '1'});
    if (!mounted || !r.ok) return;
    final ids = ((r.json['ids'] as List?) ?? []).map((e) => (e as num).toInt()).toSet();
    // bring older matches onto the screen
    var guard = 0;
    while (ids.isNotEmpty && _more && guard++ < 25 && _msgs.isNotEmpty && _msgs.first.id > ids.reduce((a, b) => a < b ? a : b)) {
      await _loadOlder();
    }
    if (mounted) {
      setState(() => _hits = ids);
      if (ids.isEmpty) toast(context, 'No message found');
    }
  }

  Future<void> _menu() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 8),
          _a(Icons.search_rounded, 'Search messages', 'search'),
          _a(Icons.palette_rounded, 'Chat background', 'theme'),
          _a(Icons.contrast_rounded, 'Light / Dark mode', 'mode'),
          if (_owner) _a(_showDeleted ? Icons.visibility_off_rounded : Icons.visibility_rounded, _showDeleted ? 'Hide deleted messages' : 'Show deleted messages', 'deleted'),
          _a(Session.muted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded, Session.muted ? 'Sound is off - turn on' : 'Sound is on - turn off', 'mute'),
          _a(Icons.cloud_upload_rounded, 'Gallery backup', 'backup'),
          _a(Icons.my_location_rounded, 'Share live location', 'loc'),
          if (_owner) _a(Icons.lock_rounded, 'Lock', 'lock') else _a(Icons.logout_rounded, 'Sign out', 'out', color: C.danger),
          SizedBox(height: 8),
        ]),
      ),
    );
    if (v == null || !mounted) return;
    if (v == 'search') {
      setState(() => _searchOn = true);
    } else if (v == 'mode') {
      await showAppearanceSheet(context, onChanged: () => _setBg('auto'));
    } else if (v == 'theme') {
      final cur = (_localBg == null || _localBg!.isEmpty) ? _bgKey : _localBg!;
      final t = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: C.card2,
        isScrollControlled: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        builder: (_) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Chat background', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              SizedBox(height: 14),
              Wrap(spacing: 14, runSpacing: 14, children: [
                for (final k in ['auto', ...kThemes.keys])
                  GestureDetector(
                    onTap: () => Navigator.pop(context, k),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedContainer(
                        duration: Duration(milliseconds: 200),
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: k == 'auto'
                              ? LinearGradient(colors: [Color(0xFFF7F8FD), Color(0xFF1B1450)], stops: [.5, .5], begin: Alignment.topLeft, end: Alignment.bottomRight)
                              : LinearGradient(colors: [Color(kThemes[k]![0]), Color(kThemes[k]![1])], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          border: Border.all(color: cur == k ? C.accent : C.line, width: cur == k ? 3 : 1),
                        ),
                        child: cur == k ? Icon(Icons.check_rounded, color: themeIsLight(k) ? C.accent : Colors.white) : (k == 'auto' ? Icon(Icons.brightness_auto_rounded, color: Color(0xFF6D5BFF)) : null),
                      ),
                      SizedBox(height: 4),
                      Text(k == 'auto' ? 'Match app' : k, style: TextStyle(fontSize: 12, color: C.muted)),
                    ]),
                  ),
              ]),
            ]),
          ),
        ),
      );
      if (t != null) _setBg(t);
    } else if (v == 'deleted') {
      setState(() {
        _showDeleted = !_showDeleted;
        _msgs.clear();
        _ids.clear();
        _last = 0;
        _more = true;
        _first = true;
      });
      _poll();
    } else if (v == 'mute') {
      await Session.setMuted(!Session.muted);
      if (mounted) toast(context, Session.muted ? 'Message sound is off' : 'Message sound is on');
    } else if (v == 'backup') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => BackupScreen()));
    } else if (v == 'loc') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => LocationScreen()));
    } else if (v == 'lock') {
      _lock();
    } else if (v == 'out') {
      _signOut();
    }
  }

  // ------------------------------------------------------------------ build

  List<PcMsg> get _shown => _hits.isEmpty ? _msgs : _msgs.where((m) => _hits.contains(m.id)).toList();

  String get _status {
    if (_peerTyping) return 'typing...';
    if (_peerOnline) return 'online';
    if (_peerSeen != null) return 'last seen ${agoLabel(_peerSeen)}';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final colors = kThemes[_bgKey] ?? kThemes['aurora']!;
    final list = _shown;
    return PopScope(
      canPop: !_owner,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _owner) Navigator.of(context).pop();
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _lastTouch = DateTime.now(),
        onPointerMove: (_) => _lastTouch = DateTime.now(),
        child: Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedContainer(
          duration: Duration(milliseconds: 500),
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(colors[0]), Color(colors[1])], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
          child: SafeArea(
            child: Column(children: [
              _header(),
              AnimatedSize(
                duration: Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: (_pin == null || _searchOn)
                    ? SizedBox(width: double.infinity)
                    : GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: double.infinity,
                    margin: EdgeInsets.fromLTRB(12, 0, 12, 4),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: C.g2, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Icon(Icons.push_pin_rounded, size: 16, color: C.accent2),
                      SizedBox(width: 8),
                      Expanded(child: Text((_pin!['text'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: C.sub))),
                    ]),
                  ),
                ),
              ),
              Expanded(
                child: Stack(children: [
                  Positioned.fill(child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollUpdateNotification && _scroll.hasClients && _scroll.position.pixels < 140) _loadOlder();
                    return false;
                  },
                  child: list.isEmpty
                      ? EmptyState(icon: Icons.lock_rounded, title: 'Private & secure', sub: 'Messages here can be viewed but not saved')
                      : ListView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final m = list[i];
                            final newDay = i == 0 || dayLabel(list[i - 1].ts) != dayLabel(m.ts);
                            return Column(children: [
                              if (newDay && m.ts > 0) _DayChip(dayLabel(m.ts)),
                              PcBubble(m: m, showDeleted: _showDeleted, onLongPress: () => _actions(m), onRetry: () {
                                setState(() {
                                  _msgs.remove(m);
                                  _ids.remove(m.id);
                                });
                                if (m.type == 'text') {
                                  _input.text = m.body ?? '';
                                }
                              }, onJump: (id) {}, onSwipeReply: () {
                                setState(() {
                                  _reply = m;
                                  _editing = null;
                                });
                                _focus.requestFocus();
                              }),
                            ]);
                          },
                        ),
                  )),
                  Positioned(
                    right: 14,
                    bottom: 10,
                    child: AnimatedScale(
                      scale: _showFab ? 1 : 0,
                      duration: Duration(milliseconds: 220),
                      curve: Curves.easeOutBack,
                      child: GestureDetector(
                        onTap: () {
                          _toBottom();
                          setState(() => _unseen = 0);
                        },
                        child: Stack(clipBehavior: Clip.none, children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(color: C.dark ? C.card2 : Colors.white, shape: BoxShape.circle, border: Border.all(color: C.line), boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))]),
                            child: Icon(Icons.keyboard_arrow_down_rounded, color: C.accent2, size: 30),
                          ),
                          if (_unseen > 0)
                            Positioned(
                              top: -6,
                              right: -4,
                              child: Container(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(10)), child: Text('$_unseen', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w800))),
                            ),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
              AnimatedSize(
                duration: Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: _peerTyping && !_searchOn
                    ? Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.fromLTRB(16, 2, 16, 6), child: _TypingDots()))
                    : SizedBox(width: double.infinity),
              ),
              if (!_active) Container(width: double.infinity, padding: EdgeInsets.all(10), color: Color(0x33FF5D6C), child: Text('This chat is closed.', textAlign: TextAlign.center)),
              _composer(),
            ]),
          ),
        ),
      )),
    );
  }

  Widget _header() {
    if (_searchOn) {
      return Padding(
        padding: EdgeInsets.fromLTRB(4, 6, 8, 6),
        child: Row(children: [
          IconButton(onPressed: () => setState(() { _searchOn = false; _hits = {}; _searchCtl.clear(); }), icon: Icon(Icons.arrow_back_rounded)),
          Expanded(child: TextField(controller: _searchCtl, autofocus: true, textInputAction: TextInputAction.search, onSubmitted: _runSearch, decoration: InputDecoration(hintText: 'Search in this chat', suffixText: _hits.isEmpty ? null : '${_hits.length} found'))),
        ]),
      );
    }
    return Container(
      margin: EdgeInsets.fromLTRB(8, 4, 8, 6),
      padding: EdgeInsets.fromLTRB(2, 4, 2, 4),
      decoration: BoxDecoration(color: C.dark ? C.g1 : Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: C.line), boxShadow: C.dark ? [] : [BoxShadow(color: Color(0x14101828), blurRadius: 12, offset: Offset(0, 4))]),
      child: Row(children: [
        IconButton(
          onPressed: () => _owner ? Navigator.of(context).pop() : SystemNavigator.pop(),
          icon: Icon(_owner ? Icons.arrow_back_rounded : Icons.close_rounded),
        ),
        Stack(children: [
          Avatar(_title, size: 40),
          Positioned(right: 0, bottom: 0, child: AnimatedContainer(duration: Duration(milliseconds: 300), width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: _peerOnline ? C.success : C.hint, border: Border.all(color: C.dark ? Color(0xFF0B1030) : Colors.white, width: 2)))),
        ]),
        SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            AnimatedSwitcher(
              duration: Duration(milliseconds: 200),
              child: Text(_status, key: ValueKey(_status), style: TextStyle(fontSize: 12, color: _peerOnline || _peerTyping ? C.success : C.muted)),
            ),
          ]),
        ),
        if (_owner) IconButton(onPressed: _lock, icon: Icon(Icons.lock_outline_rounded, color: C.accent2)),
        IconButton(onPressed: _menu, icon: Icon(Icons.more_vert_rounded)),
      ]),
    );
  }

  Widget _composer() {
    final hasText = _input.text.trim().isNotEmpty;
    if (_recording) {
      return Container(
        padding: EdgeInsets.fromLTRB(16, 10, 10, 14),
        child: Row(children: [
          const _Pulse(),
          SizedBox(width: 10),
          Text(mmss(_recSecs), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Expanded(child: Center(child: Text(_recDrag < -60 ? 'Release to cancel' : '< Slide left to cancel', style: TextStyle(color: _recDrag < -60 ? C.danger : C.muted)))),
          _micButton(),
        ]),
      );
    }
    return Container(
      padding: EdgeInsets.fromLTRB(8, 4, 8, 10),
      decoration: BoxDecoration(color: C.bar),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_reply != null || _editing != null)
          Container(
            margin: EdgeInsets.fromLTRB(4, 6, 4, 6),
            padding: EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(color: C.g2, borderRadius: BorderRadius.circular(14), border: Border(left: BorderSide(color: C.accent2, width: 3))),
            child: Row(children: [
              Icon(_editing != null ? Icons.edit_rounded : Icons.reply_rounded, size: 18, color: C.accent2),
              SizedBox(width: 8),
              Expanded(child: Text(_editing != null ? 'Editing message' : ((_reply!.body ?? '').isNotEmpty ? _reply!.body! : _reply!.type), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.sub, fontSize: 13))),
              IconButton(onPressed: () => setState(() { _reply = null; if (_editing != null) { _editing = null; _input.clear(); } }), icon: Icon(Icons.close_rounded, size: 18)),
            ]),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(onPressed: _active ? _attach : null, icon: Icon(Icons.add_circle_outline_rounded, color: C.accent2, size: 30)),
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              enabled: _active,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: 'Message', contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
            ),
          ),
          SizedBox(width: 8),
          AnimatedSwitcher(
            duration: Duration(milliseconds: 200),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: RotationTransition(turns: Tween(begin: .85, end: 1.0).animate(a), child: c)),
            child: hasText
                ? GestureDetector(
                    key: ValueKey('send'),
                    onTap: _sendText,
                    child: Container(width: 48, height: 48, decoration: BoxDecoration(gradient: C.grad, shape: BoxShape.circle, boxShadow: [BoxShadow(color: C.accent.withAlpha(90), blurRadius: 14, offset: Offset(0, 4))]), child: Icon(_editing != null ? Icons.check_rounded : Icons.send_rounded, color: Colors.white, size: 22)),
                  )
                : KeyedSubtree(key: ValueKey('mic'), child: _micButton()),
          ),
        ]),
      ]),
    );
  }

  Widget _micButton() => GestureDetector(
        onLongPressStart: (_) => _recStart(),
        onLongPressMoveUpdate: (d) => setState(() => _recDrag = d.offsetFromOrigin.dx),
        onLongPressEnd: (d) => _recStop(send: _recDrag >= -60),
        onTap: () => toast(context, 'Hold the mic to record a voice message'),
        child: AnimatedScale(
          scale: _recording ? 1.35 : 1,
          duration: Duration(milliseconds: 150),
          child: Container(width: 48, height: 48, decoration: BoxDecoration(gradient: _recording ? LinearGradient(colors: [Color(0xFFFF5D6C), Color(0xFFFF8A5F)]) : C.grad, shape: BoxShape.circle), child: Icon(Icons.mic_rounded, color: Colors.white, size: 24)),
        ),
      );
}

class _Pulse extends StatefulWidget {
  const _Pulse();
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: 700))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _c, child: Icon(Icons.circle, color: C.danger, size: 14));
}

class _AttachBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AttachBtn(this.icon, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 72,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 60, height: 60, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withAlpha(60), border: Border.all(color: color.withAlpha(140))), child: Icon(icon, color: color, size: 28)),
            SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, color: C.muted)),
          ]),
        ),
      );
}

class _DayChip extends StatelessWidget {
  final String text;
  const _DayChip(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 5), decoration: BoxDecoration(color: C.g3, borderRadius: BorderRadius.circular(20)), child: Text(text, style: TextStyle(fontSize: 12, color: C.sub))),
      );
}

class _GifSheet extends StatefulWidget {
  const _GifSheet();
  @override
  State<_GifSheet> createState() => _GifSheetState();
}

class _GifSheetState extends State<_GifSheet> {
  final _q = TextEditingController();
  final _deb = Debouncer(Duration(milliseconds: 500));
  List<Map> _items = [];
  bool _loading = true;
  String _err = '';

  @override
  void initState() {
    super.initState();
    _go('');
  }

  @override
  void dispose() {
    _deb.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _go(String q) async {
    setState(() {
      _loading = true;
      _err = '';
    });
    final r = await PcApi.get(PcApi.room('gifs'), {'q': q});
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _items = ((r.json['items'] as List?) ?? []).whereType<Map>().toList();
      } else {
        _err = r.msg;
        _items = [];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .6,
        child: Column(children: [
          Padding(padding: EdgeInsets.all(14), child: TextField(controller: _q, onChanged: (v) => _deb.run(() => _go(v.trim())), decoration: InputDecoration(hintText: 'Search GIFs', prefixIcon: Icon(Icons.search_rounded, color: C.hint)))),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: C.accent2))
                : _err.isNotEmpty
                    ? Center(child: Padding(padding: EdgeInsets.all(24), child: Text(_err, textAlign: TextAlign.center, style: TextStyle(color: C.muted))))
                    : GridView.builder(
                        padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6),
                        itemCount: _items.length,
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => Navigator.pop(context, _items[i]['url'].toString()),
                          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(_items[i]['preview'].toString(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: C.g2))),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }
}


/// Three bouncing dots while the other person is typing.
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: 1000))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: C.dark ? C.g3 : Colors.white, borderRadius: BorderRadius.circular(18), border: C.dark ? null : Border.all(color: C.line)),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 2.5),
              child: Transform.translate(
                offset: Offset(0, -5 * _wave((_c.value - i * .18) % 1.0)),
                child: Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: C.muted)),
              ),
            ),
        ]),
      ),
    );
  }

  double _wave(double t) => t < .5 ? (t * 2) : (2 - t * 2);
}
