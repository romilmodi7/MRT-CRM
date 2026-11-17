import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/push.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../core/api.dart';
import '../core/call.dart';
import '../core/appearance.dart';
import '../core/config.dart';
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
import 'outbox.dart';
import 'pc_gallery.dart';
import 'pc_models.dart';
import 'pc_profile.dart';
import 'pc_widgets.dart';
import 'room_media_screen.dart';

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

  // opening at the first unread message, keeping the last message above the keyboard
  int _openUnread = 0;                 // unread messages when the chat was opened
  int? _unreadFrom;                    // id of the first unread message (the "unread" line sits above it)
  final _unreadKey = GlobalKey();
  int? _jumpId;                        // a starred message to show
  final _jumpKey = GlobalKey();
  bool _stick = true;                  // the view is at the newest message
  // starred messages and profile photos
  Set<int> _stars = {};
  final Set<int> _sel = {};   // messages picked for copy / delete / restore together
  String _peerPhoto = '', _myPhoto = '';
  final ValueNotifier<String> _statusN = ValueNotifier('');
  late final Poller _starTick = Poller(const Duration(seconds: 25), _loadExtras);
  bool _typingShown = false;
  int _tmp = 0;
  final Map<String, PcMsg> _out = {}; // waiting messages by their outbox id
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

  // fixed when the screen opens: PcApi.owner is reset by the lock, and a late answer must never turn the owner into a "guest" (that sent him to the login screen)
  final bool _isOwner = PcApi.owner;
  bool _locked = false;
  bool get _owner => _isOwner;

  // The owner's private chat locks after 10 minutes without touching the screen, or when the app is closed.
  DateTime _lastTouch = DateTime.now();
  late final Poller _idle = Poller(const Duration(seconds: 15), () async {
    if (_owner && !AwayGuard.keepOpen && !AwayGuard.holding && DateTime.now().difference(_lastTouch).inMinutes >= 10) _lock();
  });
  Map get _room => (widget.info['room'] as Map?) ?? {};
  String get _title => _owner ? (_room['title'] ?? '').toString() : (widget.info['peer_name'] ?? _room['title'] ?? '').toString();
  List<String> get _reactions => ((widget.info['reactions'] as List?) ?? ['❤️', '👍', '😂', '😮', '😢', '🙏']).map((e) => e.toString()).toList();

  @override
  void initState() {
    super.initState();
    awayInit();
    Secure.on();
    PcGallery.source = () => _msgs;
    Future.delayed(Duration(milliseconds: 1500), () { if (mounted) warmStickers(pc: true); });   // stickers ready before the panel opens
    Push.here = 'pc:${((_room['id'] as num?) ?? PcApi.roomId).toInt()}';
    _theme = (_room['theme'] ?? 'aurora').toString();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPalette());
    if (!_owner) PcApi.roomId = ((_room['id'] as num?) ?? 0).toInt();
    PcApi.onLocked = _onLocked;
    _initOutbox();
    _input.addListener(_onTyping);
    _focus.addListener(() {
      if (_focus.hasFocus) _toBottom();   // the typing box opened: the last message stays in view
    });
    _boot();
    _idle.start();
    // first time on this phone: ask "back up your gallery?"; if they said yes before, it starts by itself
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(Duration(milliseconds: 900));
      if (mounted) askBackupOnce(context);
    });
  }

  @override
  void dispose() {
    if (Push.here.startsWith('pc:')) Push.here = '';
    awayDispose();
    Outbox.detach();
    PcGallery.source = null;
    _tick.stop();
    _starTick.stop();
    _statusN.dispose();
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
    _stick = _scroll.position.maxScrollExtent - _scroll.position.pixels < 160;
    if (far != _showFab || (!far && _unseen != 0)) {
      setState(() {
        _showFab = far;
        if (!far) _unseen = 0;
      });
    }
  }

  void _onLocked(String why) {
    if (!mounted || _locked) return;
    if (_owner) {
      _lock();
    } else {
      _signedOut();
    }
  }

  /// Lock: back to the employee chat list. The PIN is needed again.
  void _lock() {
    if (!mounted || _locked) return;
    _locked = true;
    AwayGuard.keepOpen = false;
    _tick.stop();
    _idle.stop();
    PcApi.forget();
    MemCache.clear();
    wipePcTmp();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _signOut() async {
    if (!await confirm(context, 'Sign out of this private chat? You will need the username and password again.', yes: 'Sign out')) return;
    await Push.off();
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

  /// First the unread count, the stars and the photos (the first poll marks everything as read), then the messages.
  Future<void> _boot() async {
    await _loadExtras(first: true);
    if (!mounted) return;
    await _poll();
    if (!mounted) return;
    _tick.start();
    _starTick.start();
  }

  Future<void> _loadExtras({bool first = false}) async {
    try {
      final r = await PcApi.get(PcApi.room('x/open')).timeout(Duration(seconds: 6));
      if (!mounted || !r.ok || r.data is! Map) return;
      final d = r.data as Map;
      final ph = d['photo'] is Map ? d['photo'] as Map : {};
      final stars = ((d['stars'] as List?) ?? []).map((e) => (e as num).toInt()).toSet();
      if (first) _openUnread = (d['unread'] as num?)?.toInt() ?? 0;
      final peer = (ph['peer'] ?? '').toString(), me = (ph['me'] ?? '').toString();
      if (first || peer != _peerPhoto || me != _myPhoto || stars.length != _stars.length || !stars.containsAll(_stars)) {
        setState(() {
          _stars = stars;
          _peerPhoto = peer;
          _myPhoto = me;
        });
      }
    } catch (_) {}
  }

  /// The id of the first unread message: the n-th message of the other person counted from the newest.
  void _markUnread() {
    if (_openUnread <= 0) return;
    var n = 0;
    for (var i = _msgs.length - 1; i >= 0; i--) {
      if (_msgs[i].mine || _msgs[i].id <= 0) continue;
      n++;
      _unreadFrom = _msgs[i].id;
      if (n >= _openUnread) break;
    }
  }

  /// Scroll so that the widget of [key] (the "unread" line or a starred message) is near the top.
  /// The list builds only what is on screen, so we first jump near the place and then look again.
  void _goKey(GlobalKey key, int id, [int tries = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: .15, duration: Duration.zero);
        return;
      }
      final list = _shown;
      final i = list.indexWhere((m) => m.id == id);
      if (i < 0 || tries > 14) {
        if (tries == 0) _settleBottom();
        return;
      }
      final max = _scroll.position.maxScrollExtent;
      final guess = max * (i / (list.length <= 1 ? 1 : list.length - 1)) + (tries.isEven ? 1 : -1) * tries * 260.0;
      _scroll.jumpTo(guess.clamp(0.0, max).toDouble());
      _goKey(key, id, tries + 1);
    });
  }

  /// Show one message of this chat (from the starred list).
  /// Show one message of this chat (a replied-to message, or one from the starred list) and light it up for a moment.
  /// An older message that is not loaded yet is fetched first (page by page).
  Future<void> _jumpTo(int id) async {
    var tries = 0;
    if (_msgs.indexWhere((m) => m.id == id) < 0 && _more) toast(context, 'Finding the message…');
    while (_msgs.indexWhere((m) => m.id == id) < 0 && _more && tries < 25 && mounted) {
      tries++;
      while (_loadingOld) {
        await Future.delayed(Duration(milliseconds: 80));
      }
      await _loadOlder();
    }
    if (!mounted) return;
    if (_msgs.indexWhere((m) => m.id == id) < 0) {
      toast(context, 'That message is no longer in this chat.');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _hits = {};
      _searchOn = false;
      _jumpId = id;
    });
    _goKey(_jumpKey, id);
    Future.delayed(Duration(milliseconds: 2200), () {
      if (mounted && _jumpId == id) setState(() => _jumpId = null);
    });
  }

  /// The keyboard opened or closed: when we were at the newest message (or are typing) it stays in view.
  @override
  void didChangeMetrics() {
    final keep = _stick || _focus.hasFocus;
    if (!keep) return;
    for (final ms in const [40, 160, 320]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

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
    if (added) _msgs.sort((a, b) => _ord(a).compareTo(_ord(b)));
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
    final wasTyping = _peerTyping;
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
    _statusN.value = _status;
    final typing = _focus.hasFocus;   // while typing, a new message is always brought into view
    if (added && incoming && !_first && !_nearBottom() && !typing) setState(() => _unseen += fresh.where((m) => !m.mine).length);
    if (_first) {
      _markUnread();
      if (_unreadFrom != null) {
        setState(() {});
        _goKey(_unreadKey, _unreadFrom!);
      } else {
        _settleBottom();
      }
    } else if (added && (_nearBottom() || typing)) {
      _toBottom();
    } else if (_peerTyping && !wasTyping && (_nearBottom() || typing)) {
      Future.delayed(Duration(milliseconds: 260), _toBottom);   // "typing..." appeared under the last message
    }
    _first = false;
  }

  bool _nearBottom() => !_scroll.hasClients || _scroll.position.maxScrollExtent - _scroll.position.pixels < 160;

  /// Opening the chat: pictures and long messages get their real height a moment after the first frame, so one jump
  /// lands short of the last message. Keep jumping to the end for a short while, until the person scrolls himself.
  bool _userScrolled = false;
  void _settleBottom() {
    for (final ms in const [0, 80, 200, 400, 700, 1100, 1700, 2500]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (!mounted || _userScrolled || !_scroll.hasClients) return;
        final max = _scroll.position.maxScrollExtent;
        if (_scroll.position.pixels < max) _scroll.jumpTo(max);
      });
    }
  }

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
    if (_focus.hasFocus && _input.text.isNotEmpty && !_nearBottom()) _toBottom(jump: true);   // typing: the last message is shown
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

  /// Waiting messages (not yet delivered) stay at the bottom, in the order they were written
  int _ord(PcMsg m) => m.id < 0 ? (1 << 40) - m.id : m.id;

  PcMsg _pendFor(OutItem it) {
    final b = it.body;
    final ts = it.ts ~/ 1000;
    if (it.kind == 'file') {
      final path = it.path ?? '';
      final mime = mimeOf(path);
      final voice = b['voice'] == '1';
      final type = voice ? 'audio' : mime.startsWith('image/') ? 'image' : mime.startsWith('video/') ? 'video' : mime.startsWith('audio/') ? 'audio' : 'file';
      return PcMsg(id: -(++_tmp), mine: true, ts: ts, tick: 0, type: type, pending: !it.failed, failed: it.failed, localPath: path, mediaName: path.split('/').last, dur: int.tryParse('${b['dur'] ?? 0}') ?? 0, size: File(path).existsSync() ? File(path).lengthSync() : 0, body: b['body']?.toString());
    }
    final type = (b['type'] ?? 'text').toString();
    final text = type == 'location' ? jsonEncode(b['body']) : (b['body'] is String ? b['body'] as String : null);
    return PcMsg(id: -(++_tmp), mine: true, ts: ts, tick: 0, type: type, body: text, gif: b['gif']?.toString(), pending: !it.failed, failed: it.failed);
  }

  /// Messages that were not delivered last time (app closed, no network) come back and go on sending
  Future<void> _initOutbox() async {
    await Outbox.load();
    if (!mounted) return;
    Outbox.onSent = _outSent;
    Outbox.onFailed = _outFailed;
    Outbox.onChange = () {
      if (mounted) setState(() {});
    };
    final mine = Outbox.forRoom(PcApi.roomId);
    if (mine.isNotEmpty) {
      setState(() {
        for (final it in mine) {
          final p = _pendFor(it);
          _out[it.cid] = p;
          _msgs.add(p);
          _ids.add(p.id);
        }
        _msgs.sort((a, b) => _ord(a).compareTo(_ord(b)));
      });
      Outbox.pump();
    }
  }

  Future<void> _sendMsg(Map<String, dynamic> body, PcMsg pend) async {
    setState(() {
      _msgs.add(pend);
      _ids.add(pend.id);
    });
    _toBottom();
    final it = await Outbox.add(PcApi.roomId, body);
    _out[it.cid] = pend;
    Outbox.pump();
  }

  void _outSent(OutItem it, Map m) {
    final pend = _out.remove(it.cid);
    if (!mounted) return;
    final real = PcMsg.from(m);
    setState(() {
      if (pend != null) {
        _msgs.remove(pend);
        _ids.remove(pend.id);
      }
      if (!_ids.contains(real.id)) {
        _ids.add(real.id);
        _msgs.add(real);
        _msgs.sort((a, b) => _ord(a).compareTo(_ord(b)));
        if (real.id > _last) _last = real.id;
      }
    });
    _toBottom();
  }

  void _outFailed(OutItem it) {
    final pend = _out[it.cid];
    if (!mounted) return;
    setState(() {
      pend?.pending = false;
      pend?.failed = true;
    });
    toast(context, it.err.isEmpty ? 'Message not sent.' : it.err);
  }

  /// Tap on "Not sent": send again or delete
  Future<void> _retryMsg(PcMsg m) async {
    String? cid;
    for (final e in _out.entries) {
      if (e.value == m) cid = e.key;
    }
    OutItem? it;
    if (cid != null) {
      for (final x in Outbox.forRoom(PcApi.roomId)) {
        if (x.cid == cid) it = x;
      }
    }
    if (it == null) {
      // nothing saved for it: just take it off the screen
      setState(() {
        _msgs.remove(m);
        _ids.remove(m.id);
      });
      if (m.type == 'text') _input.text = m.body ?? '';
      return;
    }
    final item = it;
    final again = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: C.card2,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: Icon(Icons.refresh_rounded), title: Text('Send again'), onTap: () => Navigator.pop(context, true)),
          ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Delete'), onTap: () => Navigator.pop(context, false)),
        ]),
      ),
    );
    if (again == null || !mounted) return;
    if (again) {
      setState(() {
        m.failed = false;
        m.pending = true;
      });
      Outbox.retry(item);
    } else {
      _out.remove(item.cid);
      setState(() {
        _msgs.remove(m);
        _ids.remove(m.id);
      });
      Outbox.discard(item);
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
    final it = await Outbox.addFile(PcApi.roomId, f, {'type': 'media', if (voice) 'voice': '1', if (voice) 'dur': '$dur', if (rep != null) 'reply': '${rep.id}', if (caption != null) 'body': caption});
    pend.localPath = it.path ?? f.path;
    _out[it.cid] = pend;
    Outbox.pump();
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

  Future<void> _emojis() async {
    await showEmojiStickerSheet(
      context,
      pc: true,
      roomPack: widget.info['stickers'] is Map ? widget.info['stickers'] as Map : null,
      onEmoji: (e) {
        insertAtCursor(_input, e);
        if (mounted) setState(() {});
      },
      onSticker: (st) async {
        final body = StickerMsg.encode(st);
        await _sendMsg({'type': 'text', 'body': body}, PcMsg(id: -(++_tmp), mine: true, ts: DateTime.now().millisecondsSinceEpoch ~/ 1000, tick: 0, type: 'text', body: body, pending: true));
      },
    );
  }

  Future<void> _stickers() async {
    final st = await pickSticker(context, pc: true, roomPack: widget.info['stickers'] is Map ? widget.info['stickers'] as Map : null);
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
    PcGifs.sent(url);   // into "This chat" of this room and into my Saved GIFs
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

  // ------------------------------------------------------------------ many messages at once

  List<PcMsg> get _picked => _msgs.where((m) => _sel.contains(m.id)).toList()..sort((a, b) => a.id.compareTo(b.id));

  void _toggleSel(PcMsg m) {
    if (m.id <= 0) return;
    HapticFeedback.selectionClick();
    setState(() => _sel.contains(m.id) ? _sel.remove(m.id) : _sel.add(m.id));
  }

  Future<void> _copySel() async {
    final txt = _picked.where((m) => m.type == 'text' && m.st != 'ghost' && (m.body ?? '').trim().isNotEmpty && StickerMsg.parse(m.body ?? '') == null).map((m) => m.body!.trim()).join('\n\n');
    if (txt.isEmpty) {
      toast(context, 'No text to copy in the chosen messages.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: txt));
    if (!mounted) return;
    setState(_sel.clear);
    toast(context, 'Copied');
  }

  Future<void> _restoreSel() async {
    final ids = _picked.where((m) => m.st == 'ghost').map((m) => m.id).toList();
    if (ids.isEmpty) return;
    final r = await PcApi.post(PcApi.room('delete'), {'ids': ids, 'scope': 'restore'});
    if (!mounted) return;
    if (!r.ok) {
      toast(context, r.msg);
      return;
    }
    setState(() {
      for (final m in _msgs) {
        if (ids.contains(m.id)) m.st = 'ok';
      }
      _sel.clear();
    });
    toast(context, '${ids.length} message${ids.length == 1 ? '' : 's'} restored');
    _poll();
  }

  Future<void> _deleteSel(String scope) async {
    final list = _picked.where((m) => m.st != 'ghost' && (scope == 'me' || m.mine)).toList();
    if (list.isEmpty) return;
    final n = list.length;
    if (!await confirm(context, scope == 'all' ? 'Delete $n message${n == 1 ? '' : 's'} for everyone?' : 'Delete $n message${n == 1 ? '' : 's'} for you?', yes: 'Delete')) return;
    final ids = list.map((m) => m.id).toList();
    final r = await PcApi.post(PcApi.room('delete'), {'ids': ids, 'scope': scope});
    if (!mounted) return;
    if (!r.ok) {
      toast(context, r.msg);
      return;
    }
    setState(() {
      for (final m in list) {
        if (scope == 'me' || !_owner || !_showDeleted) {
          _msgs.remove(m);
          _ids.remove(m.id);
        } else {
          m.st = 'ghost';
        }
      }
      _sel.clear();
    });
    toast(context, '$n message${n == 1 ? '' : 's'} deleted');
  }

  /// the top bar while messages are picked
  Widget _selBar() {
    final p = _picked;
    final texts = p.any((m) => m.type == 'text' && m.st != 'ghost' && StickerMsg.parse(m.body ?? '') == null);
    final live = p.where((m) => m.st != 'ghost').toList();
    final allMine = live.isNotEmpty && live.every((m) => m.mine);
    final ghosts = _owner && p.any((m) => m.st == 'ghost');
    Widget btn(IconData ic, String tip, VoidCallback? on, {Color? color}) => Tooltip(
          message: tip,
          child: InkResponse(
            onTap: on,
            radius: 24,
            child: Container(
              width: 42,
              height: 42,
              margin: EdgeInsets.only(left: 4),
              decoration: BoxDecoration(color: (color ?? C.accent2).withAlpha(on == null ? 12 : 34), borderRadius: BorderRadius.circular(14)),
              child: Icon(ic, size: 21, color: on == null ? C.hint : (color ?? C.accent2)),
            ),
          ),
        );
    return Container(
      margin: EdgeInsets.fromLTRB(10, 6, 10, 6),
      padding: EdgeInsets.fromLTRB(4, 6, 8, 6),
      decoration: BoxDecoration(
        color: C.dark ? C.card2.withAlpha(235) : Colors.white.withAlpha(245),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: C.accent.withAlpha(110)),
        boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Row(children: [
        IconButton(icon: Icon(Icons.close_rounded, color: C.text), tooltip: 'Cancel', onPressed: () => setState(_sel.clear)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${p.length} selected', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.text)),
            Text('Tap messages to add or remove', style: TextStyle(fontSize: 11, color: C.muted)),
          ]),
        ),
        btn(Icons.copy_rounded, 'Copy', texts ? _copySel : null),
        if (ghosts) btn(Icons.restore_rounded, 'Restore', _restoreSel, color: Color(0xFF22C55E)),
        btn(Icons.visibility_off_rounded, 'Delete for me', live.isNotEmpty ? () => _deleteSel('me') : null),
        if (allMine) btn(Icons.delete_forever_rounded, 'Delete for everyone', () => _deleteSel('all'), color: C.danger),
      ]),
    );
  }

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
          if (m.id > 0) _a(Icons.check_circle_outline_rounded, 'Select', 'select'),
          if (isText) _a(Icons.copy_rounded, 'Copy', 'copy'),
          if (m.type == 'gif' && (m.gif ?? '').startsWith('https://') && m.st != 'ghost') _a(Icons.bookmark_add_rounded, 'Save GIF', 'savegif'),
          if (m.id > 0 && m.st != 'ghost') _a(_stars.contains(m.id) ? Icons.star_border_rounded : Icons.star_rounded, _stars.contains(m.id) ? 'Remove star' : 'Star', 'star'),
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
    } else if (action == 'select') {
      HapticFeedback.selectionClick();
      setState(() => _sel.add(m.id));
    } else if (action == 'reply') {
      setState(() {
        _reply = m;
        _editing = null;
      });
      _focus.requestFocus();
    } else if (action == 'savegif') {
      final err = await PcGifs.save(m.gif ?? '');
      if (mounted) toast(context, err ?? 'GIF saved. Find it under GIF → Saved.');
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.body ?? ''));
      if (mounted) toast(context, 'Copied');
    } else if (action == 'star') {
      final r = await PcApi.post(PcApi.room('x/star'), {'id': m.id});
      if (!mounted) return;
      if (r.ok && r.data is Map) {
        setState(() => _stars = (((r.data as Map)['stars'] as List?) ?? []).map((e) => (e as num).toInt()).toSet());
        toast(context, (r.data as Map)['on'] == true ? 'Starred' : 'Star removed');
      } else {
        toast(context, r.msg);
      }
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

  /// One row of a menu: a tinted icon tile, the name, an optional second line and an optional on/off switch.
  Widget _a(IconData i, String t, String v, {Color? color, String? sub, bool? on}) => InkWell(
        onTap: () => Navigator.pop(context, v),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: (color ?? C.accent2).withAlpha(C.dark ? 46 : 30), borderRadius: BorderRadius.circular(13)),
              child: Icon(i, size: 21, color: color ?? C.accent2),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color ?? C.text)),
                if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
            if (on != null) IgnorePointer(child: Switch(value: on, onChanged: (_) {}, activeThumbColor: Colors.white, activeTrackColor: C.accent)),
          ]),
        ),
      );

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
    Widget sec(String t) => Padding(padding: EdgeInsets.fromLTRB(20, 14, 20, 6), child: Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: C.muted)));
    final v = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: C.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .86),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(height: 10),
            Container(width: 42, height: 4, decoration: BoxDecoration(color: C.g3, borderRadius: BorderRadius.circular(4))),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 2),
              child: Row(children: [
                PcAvatar(name: _title, tag: _peerPhoto, size: 40),
                SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_title.isEmpty ? 'Private chat' : _title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('Chat options', style: TextStyle(fontSize: 12.5, color: C.muted)),
                ])),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: 10),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  sec('THIS CHAT'),
                  _a(Icons.search_rounded, 'Search messages', 'search'),
                  _a(Icons.perm_media_rounded, 'Media, links and docs', 'media'),
                  _a(Icons.palette_rounded, 'Chat background', 'theme'),
                  _a(Icons.contrast_rounded, 'Light / Dark mode', 'mode'),
                  if (_owner) _a(_showDeleted ? Icons.visibility_off_rounded : Icons.visibility_rounded, _showDeleted ? 'Hide deleted messages' : 'Show deleted messages', 'deleted'),
                  sec('MORE'),
                  _a(Session.muted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded, Session.muted ? 'Sound is off' : 'Sound is on', 'mute', sub: Session.muted ? 'Tap to turn the message sound on' : 'Tap to turn the message sound off'),
                  _a(Icons.cloud_upload_rounded, 'Gallery backup', 'backup'),
                  _a(Icons.my_location_rounded, 'Share live location', 'loc'),
                  sec('PRIVACY'),
                  if (_owner) _a(AwayGuard.keepOpen ? Icons.lock_open_rounded : Icons.phonelink_lock_rounded, 'Stay unlocked', 'keep', sub: AwayGuard.keepOpen ? 'ON: stays open when you switch apps' : 'OFF: locks when you leave the app', on: AwayGuard.keepOpen),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(ctx, _owner ? 'lock' : 'out'),
                        icon: Icon(_owner ? Icons.lock_rounded : Icons.logout_rounded, size: 20),
                        label: Text(_owner ? 'Lock private chat' : 'Sign out', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _owner ? C.accent : C.danger,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
    if (v == null || !mounted) return;
    if (v == 'search') {
      setState(() => _searchOn = true);
    } else if (v == 'media') {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomMediaScreen(title: _title, showDeleted: _owner && _showDeleted)));
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
      Push.sync();
      if (mounted) toast(context, Session.muted ? 'Message sound is off' : 'Message sound is on');
    } else if (v == 'backup') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => BackupScreen()));
    } else if (v == 'loc') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => LocationScreen()));
    } else if (v == 'keep') {
      setState(() => AwayGuard.keepOpen = !AwayGuard.keepOpen);
      toast(context, AwayGuard.keepOpen ? 'Stay unlocked is ON. Private chat stays open when you switch apps or lock the phone.' : 'Stay unlocked is OFF. Private chat locks when you leave the app.');
    } else if (v == 'lock') {
      _lock();
    } else if (v == 'out') {
      _signOut();
    }
  }

  /// Tapping the name or the photo at the top: contact info (photo, last seen, media, starred, your own photo).
  Future<void> _openProfile() async {
    _statusN.value = _status;
    final room = ((_room['id'] as num?) ?? PcApi.roomId).toInt();
    final res = await Navigator.of(context).push<Map>(MaterialPageRoute(
      builder: (_) => PcProfileScreen(
        name: _title,
        status: _statusN,
        peerTag: _peerPhoto,
        myTag: _myPhoto,
        myName: (widget.info['my_name'] ?? widget.info['name'] ?? '').toString(),
        starCount: _stars.length,
        canCall: _active,
        onCall: (video) => Calls.dial(context, pc: true, room: room, name: _title, video: video),
        onMyPhoto: (t) {
          if (mounted) setState(() => _myPhoto = t);
        },
      ),
    ));
    if (!mounted || res == null) return;
    if (res['do'] == 'search') {
      setState(() => _searchOn = true);
    } else if (res['do'] == 'jump') {
      _jumpTo((res['id'] as num).toInt());
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
      canPop: !_owner && _sel.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_sel.isNotEmpty) {
          setState(_sel.clear);
        } else if (_owner) {
          Navigator.of(context).pop();
        }
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
              AnimatedSwitcher(duration: Duration(milliseconds: 180), child: _sel.isNotEmpty ? KeyedSubtree(key: ValueKey('sel'), child: _selBar()) : KeyedSubtree(key: ValueKey('head'), child: _header())),
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
                    if (n is UserScrollNotification) _userScrolled = true;
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
                            final lit = m.id == _jumpId;
                            return Column(key: lit ? _jumpKey : null, children: [
                              if (newDay && m.ts > 0) _DayChip(dayLabel(m.ts)),
                              if (m.id == _unreadFrom && _hits.isEmpty) _UnreadLine(key: _unreadKey, count: _openUnread),
                              // the message a reply points to lights up for a moment after tapping the quote
                              Builder(builder: (_) {
                                final picking = _sel.isNotEmpty;
                                final on = _sel.contains(m.id);
                                final bubble = AnimatedContainer(
                                  duration: Duration(milliseconds: 450),
                                  curve: Curves.easeOut,
                                  padding: EdgeInsets.symmetric(horizontal: 4),
                                  decoration: BoxDecoration(color: lit ? C.accent.withAlpha(C.dark ? 70 : 45) : Colors.transparent, borderRadius: BorderRadius.circular(16)),
                                  child: PcBubble(m: m, showDeleted: _showDeleted, starred: _stars.contains(m.id), onLongPress: () => picking ? _toggleSel(m) : _actions(m), onRetry: () => _retryMsg(m), onJump: (id) => _jumpTo(id), onSwipeReply: () {
                                    setState(() {
                                      _reply = m;
                                      _editing = null;
                                    });
                                    _focus.requestFocus();
                                  }),
                                );
                                if (!picking) return bubble;
                                // picking messages: a tap anywhere on the row adds / removes it
                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _toggleSel(m),
                                  onLongPress: () => _toggleSel(m),
                                  child: AnimatedContainer(
                                    duration: Duration(milliseconds: 160),
                                    margin: EdgeInsets.symmetric(vertical: 1),
                                    decoration: BoxDecoration(color: on ? C.accent.withAlpha(C.dark ? 60 : 38) : Colors.transparent, borderRadius: BorderRadius.circular(16)),
                                    child: Row(children: [
                                      Padding(
                                        padding: EdgeInsets.only(left: 6, right: 2),
                                        child: AnimatedContainer(
                                          duration: Duration(milliseconds: 160),
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(shape: BoxShape.circle, gradient: on ? C.grad : null, border: on ? null : Border.all(color: C.hint, width: 1.6)),
                                          child: on ? Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
                                        ),
                                      ),
                                      Expanded(child: IgnorePointer(child: bubble)),
                                    ]),
                                  ),
                                );
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
    final room = ((_room['id'] as num?) ?? PcApi.roomId).toInt();
    final live = _peerOnline || _peerTyping;
    return Container(
      margin: EdgeInsets.fromLTRB(8, 4, 8, 6),
      padding: EdgeInsets.fromLTRB(0, 6, 6, 6),
      decoration: BoxDecoration(
        color: C.dark ? C.g1 : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: C.line),
        boxShadow: C.dark ? [] : [BoxShadow(color: Color(0x14101828), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: Row(children: [
        _HeadBtn(
          icon: _owner ? Icons.arrow_back_rounded : Icons.close_rounded,
          plain: true,
          onTap: () => _owner ? Navigator.of(context).pop() : SystemNavigator.pop(),
        ),
        // photo + name + status: tap opens contact info
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _openProfile,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: Row(children: [
                  Stack(clipBehavior: Clip.none, children: [
                    PcAvatar(name: _title, tag: _peerPhoto, size: 42),
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 300),
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: _peerOnline ? C.success : C.hint, border: Border.all(color: C.dark ? C.g1 : Colors.white, width: 2.4)),
                      ),
                    ),
                  ]),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(_title.isEmpty ? 'Private chat' : _title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -.1)),
                      SizedBox(height: 2),
                      Row(children: [
                        if (_owner && AwayGuard.keepOpen) Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.lock_open_rounded, size: 12, color: C.accent2)),
                        Flexible(
                          child: AnimatedSwitcher(
                            duration: Duration(milliseconds: 200),
                            child: Text(
                              _status.isEmpty ? 'tap for contact info' : _status,
                              key: ValueKey(_status),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, height: 1.2, fontWeight: live ? FontWeight.w700 : FontWeight.w500, color: live ? C.success : C.muted),
                            ),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
        SizedBox(width: 4),
        _HeadBtn(icon: Icons.call_rounded, tint: C.success, onTap: _active ? () => Calls.dial(context, pc: true, room: room, name: _title) : null),
        SizedBox(width: 6),
        _HeadBtn(icon: Icons.videocam_rounded, tint: C.accent2, onTap: _active ? () => Calls.dial(context, pc: true, room: room, name: _title, video: true) : null),
        SizedBox(width: 2),
        _HeadBtn(icon: Icons.more_vert_rounded, plain: true, onTap: _menu),
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
          IconButton(onPressed: _active ? _emojis : null, icon: Icon(Icons.emoji_emotions_outlined, color: C.accent2, size: 28)),
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

/// GIFs of the private chat: collections the admin made for this room, "This chat" (every GIF sent here)
/// and "Saved" (own list: the owner one list for all rooms, a guest one per room). Kept on the phone, so it opens at once.
class PcGifs {
  static Map data = _read();
  static String get _key => 'pc_gifs3_${PcApi.roomId}';

  static Map _read() {
    try {
      final j = jsonDecode(Session.getString('pc_gifs3_${PcApi.roomId}') ?? '{}');
      return j is Map ? j : {};
    } catch (_) {
      return {};
    }
  }

  static List<Map> packs() => ((data['packs'] as List?) ?? const []).whereType<Map>().toList();
  static List<Map> list(String which) => ((data[which] as List?) ?? const []).whereType<Map>().toList();

  static Future<String?> _take(ApiRes r) async {
    if (!r.ok) return r.msg;
    if (r.data is Map && (r.data as Map).containsKey('saved')) {
      data = r.data as Map;
      await Session.setString(_key, jsonEncode(data));
    }
    return null;
  }

  static Future<void> refresh() async {
    data = _read();
    await _take(await PcApi.get(PcApi.room('x/gifs')));
  }

  /// keep a GIF in my Saved list
  static Future<String?> save(String url) async => _take(await PcApi.post(PcApi.room('x/gifs'), {'url': url}));

  /// a GIF was sent here: the server puts it in "This chat" and in my Saved list
  static Future<void> sent(String url) async {
    await PcApi.post(PcApi.room('x/gifs/sent'), {'url': url});
  }

  static Future<String?> remove(int id) async => _take(await PcApi.post(PcApi.room('x/gifs/remove'), {'id': id}));
}

class _GifSheet extends StatefulWidget {
  const _GifSheet();
  @override
  State<_GifSheet> createState() => _GifSheetState();
}

class _GifSheetState extends State<_GifSheet> {
  final _q = TextEditingController();
  final _deb = Debouncer(Duration(milliseconds: 500));
  final _scroll = ScrollController();
  List<Map> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _more = false;
  bool _searched = false;
  int _offset = 0;
  int _token = 0; // ignores answers that belong to an older search
  String _err = '';
  String _query = '';
  bool _adult = Session.getBool('gif_adult');
  static const _page = 30;
  String _tab = '';   // p:<id> = an admin collection | chat | saved | search

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _pickTab();
    PcGifs.refresh().then((_) {
      if (!mounted) return;
      setState(_pickTab);
    });
  }

  /// first time: the first admin collection; otherwise the tab is kept while it still exists
  void _pickTab() {
    final ids = PcGifs.packs().map((p) => 'p:${p['id']}').toList();
    if (_tab.isNotEmpty && (ids.contains(_tab) || !_tab.startsWith('p:'))) return;
    _tab = ids.isNotEmpty ? ids.first : (PcGifs.list('chat').isNotEmpty ? 'chat' : 'search');
    if (_tab == 'search') _startSearch();
  }

  void _startSearch() {
    if (_searched) return;
    _searched = true;
    _go('');
  }

  void _open(String t) {
    setState(() => _tab = t);
    if (t == 'search') _startSearch();
  }

  Future<void> _toggleAdult() async {
    if (!_adult) {
      final ok = await confirm(context, 'Show adult (18+) GIFs in search? Turn this on only if you are 18 or older.', yes: 'Show 18+');
      if (!ok) return;
    }
    await Session.setBool('gif_adult', !_adult);
    setState(() => _adult = !_adult);
    _go(_q.text.trim());
  }

  @override
  void dispose() {
    _deb.cancel();
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _saveUrl(String url) async {
    HapticFeedback.selectionClick();
    final err = await PcGifs.save(url);
    if (mounted) {
      toast(context, err ?? 'Saved to your GIFs');
      setState(() {});
    }
  }

  Future<void> _remove(Map g) async {
    final id = (g['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    final ok = await confirm(context, 'Remove this GIF from your saved GIFs?', yes: 'Remove');
    if (!ok) return;
    final err = await PcGifs.remove(id);
    if (mounted) {
      if (err != null) toast(context, err);
      setState(() {});
    }
  }

  /// One page of results. Returns items, an error text and whether more pages exist.
  Future<({List<Map> items, String err, bool more})> _fetch(String q, int offset) async {
    final items = <Map>[];
    String err = '';
    bool more = false;
    if (kGiphyKey.isNotEmpty) {
      // straight from GIPHY (no server setup needed); 18+ switch = rating r, otherwise g
      try {
        final u = Uri.https('api.giphy.com', q.isEmpty ? '/v1/gifs/trending' : '/v1/gifs/search', {
          'api_key': kGiphyKey,
          if (q.isNotEmpty) 'q': q,
          'limit': '$_page',
          'offset': '$offset',
          'rating': _adult ? 'r' : 'g',
        });
        final res = await http.get(u).timeout(Duration(seconds: 12));
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        if (res.statusCode == 200 && j is Map) {
          for (final g in (j['data'] as List? ?? [])) {
            final im = (g as Map)['images'] as Map?;
            final prev = (im?['fixed_height_small'] as Map?)?['url'];
            final full = (im?['fixed_height'] as Map?)?['url'];
            if (prev != null && full != null) items.add({'preview': prev.toString(), 'url': full.toString()});
          }
          final pg = j['pagination'] as Map?;
          final total = (pg?['total_count'] as num?)?.toInt() ?? 0;
          final got = (pg?['count'] as num?)?.toInt() ?? (j['data'] as List? ?? []).length;
          more = got > 0 && (offset + got) < (total > 0 ? total : offset + got + 1) && offset + got < 4000;
        } else {
          err = res.statusCode == 429 ? 'GIF limit reached for now. Try again in a while.' : 'GIF search is not available right now.';
        }
      } catch (_) {
        err = 'GIF search is not reachable. Check your internet.';
      }
    } else {
      final r = await PcApi.get(PcApi.room('gifs'), {'q': q, 'adult': _adult ? '1' : '0', 'offset': '$offset'});
      if (r.ok) {
        items.addAll(((r.json['items'] as List?) ?? []).whereType<Map>());
        more = r.json['more'] == true;
      } else {
        err = r.msg;
      }
    }
    return (items: items, err: err, more: more);
  }

  Future<void> _go(String q) async {
    final t = ++_token;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _err = '';
      _query = q;
      _offset = 0;
      _more = false;
    });
    final r = await _fetch(q, 0);
    if (!mounted || t != _token) return;
    setState(() {
      _loading = false;
      _err = r.err;
      _items = r.items;
      _offset = r.items.length;
      _more = r.more;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_more || _err.isNotEmpty) return;
    final t = _token;
    setState(() => _loadingMore = true);
    final r = await _fetch(_query, _offset);
    if (!mounted || t != _token) return;
    final seen = _items.map((e) => e['url'].toString()).toSet();
    final fresh = r.items.where((e) => !seen.contains(e['url'].toString())).toList();
    setState(() {
      _loadingMore = false;
      _items = [..._items, ...fresh];
      _offset += r.items.length;
      _more = r.more && r.items.isNotEmpty;
    });
  }

  Widget _gif(String url, {VoidCallback? onLong}) => GestureDetector(
        onTap: () => Navigator.pop(context, url),
        onLongPress: onLong,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: C.g1,
            child: Image.network(url, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 360,
                loadingBuilder: (_, child, p) => p == null ? child : Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent2))),
                errorBuilder: (_, __, ___) => Center(child: Icon(Icons.broken_image_outlined, color: C.hint))),
          ),
        ),
      );

  Widget _grid(List<Map> list, {bool saved = false, String empty = ''}) {
    if (list.isEmpty) {
      return Center(child: Padding(padding: EdgeInsets.all(28), child: Text(empty, textAlign: TextAlign.center, style: TextStyle(color: C.muted, height: 1.4))));
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 12),
      cacheExtent: 400,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final url = list[i]['url'].toString();
        return _gif(url, onLong: saved ? () => _remove(list[i]) : () => _saveUrl(url));
      },
    );
  }

  Widget _chip(String t, String icon, String label, int? count) {
    final on = _tab == t;
    return GestureDetector(
      onTap: () => _open(t),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 160),
        height: 36,
        margin: EdgeInsets.only(right: 6),
        padding: EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: on ? LinearGradient(colors: [C.accent, C.accent2]) : null,
          color: on ? null : C.g1,
          borderRadius: BorderRadius.circular(18),
          border: on ? null : Border.all(color: C.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(icon, style: TextStyle(fontSize: 15)),
          SizedBox(width: 5),
          ConstrainedBox(constraints: BoxConstraints(maxWidth: 120), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: on ? Colors.white : C.text))),
          if (count != null && count > 0) ...[
            SizedBox(width: 5),
            Text('$count', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: on ? Colors.white70 : C.muted)),
          ],
        ]),
      ),
    );
  }

  Widget _searchBody() => Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Row(children: [
            Expanded(child: TextField(controller: _q, onChanged: (v) => _deb.run(() => _go(v.trim())), decoration: InputDecoration(hintText: 'Search GIFs', prefixIcon: Icon(Icons.search_rounded, color: C.hint)))),
            SizedBox(width: 10),
            GestureDetector(
              onTap: _toggleAdult,
              child: AnimatedContainer(
                duration: Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(color: _adult ? C.danger.withAlpha(46) : C.g1, borderRadius: BorderRadius.circular(20), border: Border.all(color: _adult ? C.danger : C.line, width: _adult ? 1.6 : 1)),
                child: Text(_adult ? '18+ ON' : '18+ OFF', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: _adult ? C.danger : C.muted)),
              ),
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: C.accent2))
              : _err.isNotEmpty
                  ? Center(child: Padding(padding: EdgeInsets.all(24), child: Text(_err, textAlign: TextAlign.center, style: TextStyle(color: C.muted))))
                  : GridView.builder(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6),
                      itemCount: _items.length + (_loadingMore ? 3 : 0),
                      itemBuilder: (_, i) {
                        if (i >= _items.length) {
                          return Container(decoration: BoxDecoration(color: C.g2, borderRadius: BorderRadius.circular(10)), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent2))));
                        }
                        final url = _items[i]['url'].toString();
                        return GestureDetector(
                          onTap: () => Navigator.pop(context, url),
                          onLongPress: () => _saveUrl(url),
                          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(_items[i]['preview'].toString(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: C.g2))),
                        );
                      },
                    ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final packs = PcGifs.packs();
    final chat = PcGifs.list('chat'), saved = PcGifs.list('saved');
    Widget body;
    String hint = '';
    if (_tab.startsWith('p:')) {
      final p = packs.where((x) => 'p:${x['id']}' == _tab).firstOrNullX;
      body = _grid(((p?['gifs'] as List?) ?? const []).whereType<Map>().toList(), empty: 'No GIFs in this collection yet.');
      hint = 'Tap to send · hold to save';
    } else if (_tab == 'chat') {
      body = _grid(chat, empty: 'GIFs sent in this chat show here.');
      hint = 'Every GIF sent in this chat · hold to save';
    } else if (_tab == 'saved') {
      body = _grid(saved, saved: true, empty: 'GIFs you send are saved here.\nHold a GIF anywhere to save it.');
      hint = 'Your GIFs · hold to remove';
    } else {
      body = _searchBody();
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .6,
        child: Column(children: [
          SizedBox(height: 10),
          Container(width: 42, height: 4, decoration: BoxDecoration(color: C.g3, borderRadius: BorderRadius.circular(4))),
          SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(scrollDirection: Axis.horizontal, padding: EdgeInsets.symmetric(horizontal: 12), children: [
              for (final p in packs) _chip('p:${p['id']}', (p['icon'] ?? '🎞️').toString(), (p['name'] ?? 'GIFs').toString(), ((p['gifs'] as List?) ?? const []).length),
              _chip('chat', '💬', 'This chat', chat.length),
              _chip('saved', '⭐', 'Saved', saved.length),
              _chip('search', '🔍', 'Search', null),
            ]),
          ),
          if (hint.isNotEmpty) Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Align(alignment: Alignment.centerLeft, child: Text(hint, style: TextStyle(fontSize: 11.5, color: C.muted)))),
          SizedBox(height: hint.isEmpty ? 8 : 0),
          Expanded(child: body),
        ]),
      ),
    );
  }
}

extension _FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNullX => isEmpty ? null : first;
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

/// The line above the first unread message when a chat is opened.
class _UnreadLine extends StatelessWidget {
  final int count;
  const _UnreadLine({super.key, required this.count});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(child: Container(height: 1, color: C.accent.withAlpha(90))),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 10),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: C.accent.withAlpha(40), borderRadius: BorderRadius.circular(20), border: Border.all(color: C.accent.withAlpha(120))),
            child: Text(count == 1 ? '1 unread message' : '$count unread messages', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.accent2)),
          ),
          Expanded(child: Container(height: 1, color: C.accent.withAlpha(90))),
        ]),
      );
}

/// Round button of the private chat's top bar: tinted (calls) or plain (back, menu). Greyed out when [onTap] is null.
class _HeadBtn extends StatelessWidget {
  final IconData icon;
  final Color? tint;
  final bool plain;
  final VoidCallback? onTap;
  const _HeadBtn({required this.icon, this.tint, this.plain = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final off = onTap == null;
    final c = off ? C.hint : (tint ?? C.text);
    return Material(
      color: plain ? Colors.transparent : c.withAlpha(C.dark ? 40 : 26),
      shape: CircleBorder(),
      child: InkWell(
        customBorder: CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: plain ? 40 : 38, height: plain ? 40 : 38, child: Icon(icon, size: plain ? 23 : 20, color: c)),
      ),
    );
  }
}
