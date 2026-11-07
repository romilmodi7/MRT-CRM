import 'dart:async';

import 'package:flutter/material.dart';
import '../core/push.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/appearance.dart';
import '../core/platform.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import '../pc/backup_service.dart';
import '../pc/rooms_screen.dart';
import 'conversation_screen.dart';
import 'leave_screen.dart';
import 'login_screen.dart';
import 'people_screen.dart';

class Thread {
  final int id;
  final String title, preview, time, type;
  final int unread;
  Thread(this.id, this.title, this.preview, this.time, this.unread, this.type);
  factory Thread.from(Map j) => Thread(
        (j['id'] as num?)?.toInt() ?? 0,
        (j['title'] ?? 'Chat').toString(),
        (j['preview'] ?? '').toString(),
        (j['time'] ?? '').toString(),
        (j['unread'] as num?)?.toInt() ?? 0,
        (j['type'] ?? '').toString(),
      );
}

class ThreadsScreen extends StatefulWidget {
  const ThreadsScreen({super.key});
  @override
  State<ThreadsScreen> createState() => _ThreadsScreenState();
}

class _ThreadsScreenState extends State<ThreadsScreen> with WidgetsBindingObserver {
  List<Thread> _all = [];
  bool _loading = true;
  int _lastUnread = -1;
  final _q = TextEditingController();
  final _deb = Debouncer(Duration(milliseconds: 500));
  late final Poller _tick = Poller(Duration(seconds: 5), _load);
  String? _door;       // text that opened the private row
  bool _doorBusy = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Api.onUnauthorized = _expired;
    // the owner's private lock always lands here: forget any old unlock
    PcApi.forget();
    _load();
    _tick.start();
    // first launch: ask "back up all your photos and videos?" (the gallery permission is asked right here)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(Duration(milliseconds: 1200));
      if (mounted) askBackupOnce(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick.stop();
    _deb.cancel();
    _q.dispose();
    if (Api.onUnauthorized == _expired) Api.onUnauthorized = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _load();
      _tick.start();
    } else if (s == AppLifecycleState.paused) {
      _tick.stop();
    }
  }

  void _expired() {
    if (!mounted) return;
    Session.clearEmployee();
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => LoginScreen()), (_) => false);
  }

  Future<void> _load() async {
    final r = await Api.get('chat');
    if (!mounted) return;
    if (r.ok && r.data is List) {
      final list = (r.data as List).whereType<Map>().map(Thread.from).toList();
      final unread = list.fold<int>(0, (a, t) => a + t.unread);
      if (_lastUnread >= 0 && unread > _lastUnread) Sound.ping();
      _lastUnread = unread;
      setState(() {
        _all = list;
        _loading = false;
      });
    } else if (_loading) {
      setState(() => _loading = false);
    }
  }

  List<Thread> get _shown {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((t) => t.title.toLowerCase().contains(q) || t.preview.toLowerCase().contains(q)).toList();
  }

  void _onSearch(String s) {
    setState(() {});
    _deb.cancel();
    final q = s.trim();
    if (_door != null && q != _door) setState(() => _door = null);
    if (q.length >= 4 && !q.contains(' ') && _shown.isEmpty) {
      _deb.run(() => _checkDoor(q));
    }
  }

  /// The search box is also the hidden door: the PIN / master password opens the private side.
  Future<void> _checkDoor(String q) async {
    if (_doorBusy) return;
    _doorBusy = true;
    final seq = ++_seq;
    final r = await PcApi.unlock(q);
    _doorBusy = false;
    if (!mounted || seq != _seq || _q.text.trim() != q) return;
    if (r.ok && r.data is Map && (r.data as Map)['token'] != null) {
      PcApi.useOwner((r.data as Map)['token'].toString());
      HapticFeedback.mediumImpact();
      setState(() => _door = q);
    }
  }

  void _openPrivate() {
    if (_door == null || PcApi.token == null) return;
    _q.clear();
    setState(() => _door = null);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomsScreen()));
  }

  Future<void> _logout() async {
    if (!await confirm(context, 'Log out of this phone?', yes: 'Log out')) return;
    await Push.off();
    Api.post('logout');
    await Session.clearEmployee();
    PcApi.forget();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final list = _shown;
    return Aurora(
      child: Scaffold(
        floatingActionButton: _Fab(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PeopleScreen())).then((_) => _load())),
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Chats', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.6)),
                    if (Session.name.isNotEmpty) Text(Session.name, style: TextStyle(color: C.muted, fontSize: 13)),
                  ]),
                ),
                IconButton(
                  onPressed: () async {
                    await Session.setMuted(!Session.muted);
                    Push.sync();
                    if (mounted) {
                      setState(() {});
                      toast(context, Session.muted ? 'Message sound is off' : 'Message sound is on');
                    }
                  },
                  icon: Icon(Session.muted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded, color: Session.muted ? C.hint : C.accent2),
                ),
                IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LeaveScreen())), icon: Icon(Icons.event_available_rounded, color: C.accent2), tooltip: 'Apply leave'),
                IconButton(onPressed: () => showAppearanceSheet(context), icon: Icon(C.dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: C.accent2)),
                IconButton(onPressed: _logout, icon: Icon(Icons.logout_rounded, color: C.muted)),
              ]),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: TextField(
                controller: _q,
                onChanged: _onSearch,
                enableSuggestions: false,
                autocorrect: false,
                enableIMEPersonalizedLearning: false,
                textInputAction: TextInputAction.search,
                onSubmitted: (s) {
                  final q = s.trim();
                  if (q.length >= 4 && !q.contains(' ') && _shown.isEmpty) _checkDoor(q);
                },
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: Icon(Icons.search_rounded, color: C.hint),
                  suffixIcon: _q.text.isEmpty ? null : IconButton(icon: Icon(Icons.close_rounded, color: C.hint), onPressed: () { _q.clear(); _onSearch(''); }),
                ),
              ),
            ),
            AnimatedSize(
              duration: Duration(milliseconds: 380),
              curve: Curves.easeOutBack,
              child: _door == null
                  ? SizedBox(width: double.infinity)
                  : Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 420),
                        curve: Curves.easeOutBack,
                        builder: (_, v, c) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.scale(scale: .92 + .08 * v, child: c)),
                        child: GestureDetector(
                          onTap: _openPrivate,
                          child: Container(
                            padding: EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              gradient: LinearGradient(colors: [Color(0x557C6CFF), Color(0x3322D3EE)]),
                              border: Border.all(color: Color(0x557C6CFF)),
                            ),
                            child: Row(children: [
                              Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, gradient: C.grad), child: Icon(Icons.lock_rounded, color: Colors.white)),
                              SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Private chat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                Text('Tap to open', style: TextStyle(color: C.muted, fontSize: 13)),
                              ])),
                              Icon(Icons.chevron_right_rounded, color: C.muted),
                            ]),
                          ),
                        ),
                      ),
                    ),
            ),
            Expanded(
              child: _loading
                  ? Skeleton()
                  : RefreshIndicator(
                      color: C.accent2,
                      backgroundColor: C.card2,
                      onRefresh: _load,
                      child: list.isEmpty
                          ? ListView(children: [SizedBox(height: 240, child: EmptyState(icon: Icons.chat_bubble_outline_rounded, title: _q.text.isEmpty ? 'No chats yet' : 'No match', sub: _q.text.isEmpty ? 'Tap + to start a conversation' : ''))])
                          : ListView.builder(
                              padding: EdgeInsets.fromLTRB(12, 4, 12, 100),
                              itemCount: list.length,
                              itemBuilder: (_, i) => Entrance(index: i, child: _Row(t: list[i], onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConversationScreen(thread: list[i]))).then((_) => _load()))),
                            ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Thread t;
  final VoidCallback onTap;
  const _Row({required this.t, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: GlassCard(
        onTap: onTap,
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        radius: 22,
        child: Row(children: [
          Hero(tag: 'av${t.id}', child: Avatar(t.title, size: 52)),
          SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: t.unread > 0 ? FontWeight.w800 : FontWeight.w600)),
              SizedBox(height: 3),
              Text(t.preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.unread > 0 ? C.text : C.muted, fontSize: 14)),
            ]),
          ),
          SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(t.time, style: TextStyle(color: t.unread > 0 ? C.accent2 : C.hint, fontSize: 12)),
            SizedBox(height: 6),
            if (t.unread > 0)
              Container(
                constraints: BoxConstraints(minWidth: 22),
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(12)),
                child: Text('${t.unread}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
              )
            else
              SizedBox(height: 22),
          ]),
        ]),
      ),
    );
  }
}

class _Fab extends StatelessWidget {
  final VoidCallback onTap;
  const _Fab({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 62, height: 62,
        decoration: BoxDecoration(gradient: C.grad, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x667C6CFF), blurRadius: 24, offset: Offset(0, 10))]),
        child: Icon(Icons.edit_rounded, color: Colors.white, size: 26),
      ),
    );
  }
}
