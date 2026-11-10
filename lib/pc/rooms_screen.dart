import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/platform.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import 'room_chat_screen.dart';

/// Owner's private side: all rooms (one per person), create / reset / disable / delete.
class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});
  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> with WidgetsBindingObserver, AwayLock<RoomsScreen> {
  @override
  int get awaySeconds => 600;

  List<Map> _rooms = [];
  String _defaultName = 'Admin';
  bool _loading = true;
  late final Poller _tick = Poller(Duration(seconds: 4), _load);

  @override
  void initState() {
    super.initState();
    awayInit();
    Secure.on();
    PcApi.onLocked = (_) => _lock();
    _load();
    _tick.start();
  }

  @override
  void dispose() {
    awayDispose();
    _tick.stop();
    Secure.off();
    super.dispose();
  }

  @override
  void onAwayLock() => _lock();

  @override
  void onLifecycle(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _tick.start();
    if (s == AppLifecycleState.paused) _tick.stop();
  }

  /// Lock = straight back to the employee chat list. The PIN is needed again.
  void _lock() {
    if (!mounted) return;
    AwayGuard.keepOpen = false;
    PcApi.forget();
    MemCache.clear();
    wipePcTmp();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _load() async {
    final r = await PcApi.get('rooms');
    if (!mounted) return;
    if (r.ok && r.data is Map) {
      final d = r.data as Map;
      setState(() {
        _rooms = ((d['rooms'] as List?) ?? []).whereType<Map>().toList();
        _defaultName = (d['default_name'] ?? 'Admin').toString();
        _loading = false;
      });
    } else if (_loading) {
      setState(() => _loading = false);
    }
  }

  Future<void> _open(Map room) async {
    PcApi.roomId = (room['id'] as num).toInt();
    final r = await PcApi.get('rooms/${room['id']}/info');
    if (!mounted) return;
    if (!r.ok || r.data is! Map) {
      toast(context, r.msg);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomChatScreen(info: Map<String, dynamic>.from(r.data as Map))));
    if (mounted) {
      PcApi.roomId = 0;
      _load();
    }
  }

  Future<void> _create() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _CreateSheet(defaultName: _defaultName),
    );
    if (ok == true) _load();
  }

  Future<void> _menu(Map room) async {
    final id = (room['id'] as num).toInt();
    final active = room['active'] == true;
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 10),
          Text(room['title'].toString(), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text('Login: ${room['username'] ?? '-'}', style: TextStyle(color: C.muted)),
          SizedBox(height: 6),
          _tile(Icons.edit_rounded, 'Rename', 'rename'),
          _tile(Icons.key_rounded, 'Reset password', 'pw'),
          _tile(Icons.link_rounded, 'Copy invite link', 'link'),
          _tile(active ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded, active ? 'Close this chat' : 'Re-open this chat', 'toggle'),
          _tile(Icons.delete_outline_rounded, 'Delete chat', 'del', color: C.danger),
          SizedBox(height: 6),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    if (pick == 'link') {
      await Clipboard.setData(ClipboardData(text: room['link'].toString()));
      if (mounted) toast(context, 'Link copied');
    } else if (pick == 'toggle') {
      final r = await PcApi.post('rooms/$id/toggle');
      if (mounted) {
        toast(context, r.ok ? (active ? 'Chat closed' : 'Chat re-opened') : r.msg);
        _load();
      }
    } else if (pick == 'pw') {
      final pw = await askText(context, 'New password (min 6)', hint: 'Password');
      if (pw == null) return;
      final r = await PcApi.post('rooms/$id/password', {'password': pw});
      if (mounted) toast(context, r.ok ? 'Password changed' : r.msg);
    } else if (pick == 'rename') {
      final guest = await askText(context, 'Receiver name', initial: room['guest_name']?.toString() ?? room['title'].toString());
      if (guest == null || !mounted) return;
      final owner = await askText(context, 'Your name in this chat', initial: room['owner_name']?.toString() ?? _defaultName);
      if (owner == null) return;
      final r = await PcApi.post('rooms/$id/rename', {'guest_name': guest, 'owner_name': owner});
      if (mounted) {
        toast(context, r.ok ? 'Saved' : r.msg);
        _load();
      }
    } else if (pick == 'del') {
      if (!await confirm(context, 'Delete this chat and everything in it? This cannot be undone.', yes: 'Delete')) return;
      final r = await PcApi.post('rooms/$id/delete');
      if (mounted) {
        toast(context, r.ok ? 'Deleted' : r.msg);
        _load();
      }
    }
  }

  Widget _tile(IconData i, String t, String v, {Color? color}) => ListTile(
        leading: Icon(i, color: color ?? C.accent2),
        title: Text(t, style: TextStyle(color: color ?? C.text)),
        onTap: () => Navigator.pop(context, v),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _lock();
      },
      child: Aurora(
        child: Scaffold(
          appBar: AppBar(
            title: Row(children: [Icon(Icons.lock_rounded, size: 20, color: C.accent2), SizedBox(width: 10), Text('Private chats', style: TextStyle(fontWeight: FontWeight.w800))]),
            actions: [
              KeepOpenButton(onChanged: () => setState(() {})),
              TextButton.icon(onPressed: _lock, icon: Icon(Icons.lock_outline_rounded, size: 18), label: Text('Lock')),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _create,
            backgroundColor: C.accent,
            icon: Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
            label: Text('New chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          body: _loading
              ? Skeleton()
              : _rooms.isEmpty
                  ? EmptyState(icon: Icons.lock_person_outlined, title: 'No private chats yet', sub: 'Tap New chat to create one for a person')
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: C.accent2,
                      backgroundColor: C.card2,
                      child: ListView.builder(
                        padding: EdgeInsets.fromLTRB(12, 4, 12, 110),
                        itemCount: _rooms.length,
                        itemBuilder: (_, i) {
                          final r = _rooms[i];
                          final unread = (r['unread'] as num?)?.toInt() ?? 0;
                          final online = r['online'] == true;
                          final active = r['active'] == true;
                          return Entrance(
                            index: i,
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: GlassCard(
                                onTap: () => _open(r),
                                onLongPress: () => _menu(r),
                                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(children: [
                                  Stack(children: [
                                    Avatar(r['title'].toString(), size: 52),
                                    if (online) Positioned(right: 0, bottom: 0, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: C.success, shape: BoxShape.circle, border: Border.all(color: C.bg, width: 2)))),
                                  ]),
                                  SizedBox(width: 14),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Row(children: [
                                        Flexible(child: Text(r['title'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                                        if (!active) Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.pause_circle_filled_rounded, size: 16, color: C.hint)),
                                      ]),
                                      SizedBox(height: 3),
                                      Text(r['last']?.toString() ?? 'No messages yet', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: unread > 0 ? C.text : C.muted, fontSize: 14)),
                                    ]),
                                  ),
                                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Text(agoLabel((r['last_at'] as num?)?.toInt()), style: TextStyle(color: C.hint, fontSize: 12)),
                                    SizedBox(height: 6),
                                    if (unread > 0)
                                      Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(12)), child: Text('$unread', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)))
                                    else
                                      SizedBox(height: 22),
                                  ]),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ),
    );
  }
}

class _CreateSheet extends StatefulWidget {
  final String defaultName;
  const _CreateSheet({required this.defaultName});
  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  late final _owner = TextEditingController(text: widget.defaultName);
  final _guest = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String _err = '';
  Map? _done;

  String _gen() {
    const abc = 'abcdefghjkmnpqrstuvwxyzACDEFGHJKLMNPQRTUVWXYZ2346789';
    final n = DateTime.now().microsecondsSinceEpoch;
    var s = '';
    var x = n;
    for (var i = 0; i < 10; i++) {
      x = (x * 1103515245 + 12345) & 0x7fffffff;
      s += abc[x % abc.length];
    }
    return s;
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _err = '';
    });
    final r = await PcApi.post('rooms', {'owner_name': _owner.text.trim(), 'guest_name': _guest.text.trim(), 'username': _user.text.trim(), 'password': _pass.text.trim()});
    if (!mounted) return;
    if (r.ok && r.data is Map) {
      setState(() {
        _done = r.data as Map;
        _busy = false;
      });
    } else {
      setState(() {
        _busy = false;
        _err = r.msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 20, 22, 22 + bottom),
      child: SingleChildScrollView(
        child: _done != null
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_rounded, color: C.success, size: 54),
                SizedBox(height: 10),
                Text('Chat created', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                SizedBox(height: 12),
                GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Username:  ${_done!['username']}', style: TextStyle(fontSize: 16)),
                  SizedBox(height: 6),
                  Text('Password:  ${_done!['password']}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ])),
                SizedBox(height: 14),
                GradientButton(
                  label: 'Copy login details',
                  icon: Icons.copy_rounded,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: 'Username: ${_done!['username']}\nPassword: ${_done!['password']}\nLink: ${_done!['link']}'));
                    if (context.mounted) toast(context, 'Copied');
                  },
                ),
                TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Done')),
              ])
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('New private chat', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                SizedBox(height: 14),
                TextField(controller: _guest, decoration: InputDecoration(hintText: 'Receiver name')),
                SizedBox(height: 10),
                TextField(controller: _owner, decoration: InputDecoration(hintText: 'Your name in this chat')),
                SizedBox(height: 10),
                TextField(controller: _user, autocorrect: false, decoration: InputDecoration(hintText: 'Login username (letters, numbers . _ -)')),
                SizedBox(height: 10),
                TextField(controller: _pass, autocorrect: false, decoration: InputDecoration(hintText: 'Password (min 6)', suffixIcon: IconButton(icon: Icon(Icons.auto_awesome_rounded, color: C.accent2), onPressed: () => setState(() => _pass.text = _gen())))),
                if (_err.isNotEmpty) Padding(padding: EdgeInsets.only(top: 10), child: Text(_err, style: TextStyle(color: Color(0xFFFFB3BB)))),
                SizedBox(height: 16),
                GradientButton(label: 'Create', busy: _busy, onTap: _go),
              ]),
      ),
    );
  }
}
