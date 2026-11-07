import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api.dart';
import '../core/platform.dart';
import '../core/stickers.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import 'project_share_screen.dart';
import 'threads_screen.dart';

class Attach {
  final int id;
  final String name, kind, size;
  Attach(this.id, this.name, this.kind, this.size);
}

class Msg {
  final int id;
  final bool mine;
  final String name, text, time, day;
  final bool edited;
  final List<Attach> files;
  final ShareCard? share;
  Msg(this.id, this.mine, this.name, this.text, this.time, this.day, this.edited, this.files, {this.share});

  factory Msg.from(Map j) => Msg(
        (j['id'] as num?)?.toInt() ?? 0,
        j['mine'] == true,
        (j['name'] ?? '').toString(),
        (j['text'] ?? '').toString(),
        (j['time'] ?? '').toString(),
        (j['day'] ?? '').toString(),
        j['edited'] == true || j['edited'] == 1,
        ((j['attach'] as List?) ?? []).whereType<Map>().map((f) => Attach((f['id'] as num?)?.toInt() ?? 0, (f['name'] ?? 'file').toString(), (f['kind'] ?? 'file').toString(), (f['size'] ?? '').toString())).toList(),
        share: ShareCard.from(j['share']),
      );
}

class ConversationScreen extends StatefulWidget {
  final Thread thread;
  const ConversationScreen({super.key, required this.thread});
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> with WidgetsBindingObserver {
  final List<Msg> _msgs = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<File> _pending = [];
  late final Poller _tick = Poller(Duration(seconds: 4), _load);
  int _last = 0;
  bool _first = true, _canWrite = true, _sending = false;
  String _members = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _tick.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick.stop();
    _input.dispose();
    _scroll.dispose();
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

  Future<void> _load() async {
    final r = await Api.get('chat/${widget.thread.id}?after=$_last');
    if (!mounted || !r.ok || r.data is! Map) return;
    final d = r.data as Map;
    final th = d['thread'];
    if (th is Map) {
      _canWrite = th['canwrite'] != false;
      final m = th['members'];
      if (m is List) _members = m.length > 2 ? '${m.length} members' : '';
    }
    final inc = ((d['messages'] as List?) ?? []).whereType<Map>().map(Msg.from).where((m) => m.id > _last).toList();
    if (inc.isNotEmpty) {
      if (!_first && inc.any((m) => !m.mine)) Sound.ping();
      setState(() {
        _msgs.addAll(inc);
        _last = inc.last.id;
      });
      _toBottom();
    } else if (_first) {
      setState(() {});
    }
    _first = false;
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Duration(milliseconds: 260), curve: Curves.easeOut);
    });
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty && _pending.isEmpty) return;
    final files = List<File>.from(_pending);
    setState(() {
      _sending = true;
      _input.clear();
      _pending.clear();
    });
    final r = files.isEmpty ? await Api.post('chat/${widget.thread.id}', {'body': body}) : await Api.upload('chat/${widget.thread.id}', {'body': body}, files);
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.ok) {
      _load();
    } else {
      setState(() {
        if (_input.text.isEmpty) _input.text = body;
        _pending.addAll(files);
      });
      toast(context, r.msg);
    }
  }

  Future<void> _sticker() async {
    await showEmojiStickerSheet(
      context,
      onEmoji: (e) {
        insertAtCursor(_input, e);
        if (mounted) setState(() {});
      },
      onSticker: (st) async {
        final r = await Api.post('chat/${widget.thread.id}', {'body': StickerMsg.encode(st)});
        if (!mounted) return;
        if (r.ok) {
          _load();
        } else {
          toast(context, r.msg);
        }
      },
    );
  }

  Future<void> _attach() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _Opt(Icons.photo_library_rounded, 'Gallery', Color(0xFF7C6CFF), () => Navigator.pop(context, 'gallery')),
            _Opt(Icons.photo_camera_rounded, 'Camera', Color(0xFFFF5FA8), () => Navigator.pop(context, 'camera')),
            _Opt(Icons.insert_drive_file_rounded, 'File', Color(0xFF22D3EE), () => Navigator.pop(context, 'file')),
          ]),
        ),
      ),
    );
    if (pick == null) return;
    try {
      if (pick == 'gallery') {
        final xs = await ImagePicker().pickMultipleMedia();
        for (final x in xs) {
          if (_pending.length < 5) _pending.add(File(x.path));
        }
      } else if (pick == 'camera') {
        final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 88);
        if (x != null && _pending.length < 5) _pending.add(File(x.path));
      } else {
        final r = await FilePicker.platform.pickFiles(allowMultiple: true);
        if (r != null) {
          for (final f in r.files) {
            if (f.path != null && _pending.length < 5) _pending.add(File(f.path!));
          }
        }
      }
    } catch (_) {
      if (mounted) toast(context, 'Could not open that. Check the permission in Settings.');
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Aurora(
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(children: [
            Hero(tag: 'av${widget.thread.id}', child: Avatar(widget.thread.title, size: 40)),
            SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.thread.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                if (_members.isNotEmpty) Text(_members, style: TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
          ]),
        ),
        body: Column(children: [
          Expanded(
            child: _msgs.isEmpty
                ? EmptyState(icon: Icons.waving_hand_rounded, title: 'Say hello', sub: 'Messages you send appear here')
                : ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) {
                      final m = _msgs[i];
                      final newDay = i == 0 || _msgs[i - 1].day != m.day;
                      return Column(children: [
                        if (newDay && m.day.isNotEmpty) _DayChip(m.day),
                        _Bubble(m: m, showName: !m.mine && m.name.isNotEmpty && (i == 0 || _msgs[i - 1].name != m.name || newDay)),
                      ]);
                    },
                  ),
          ),
          if (_pending.isNotEmpty)
            GestureDetector(
              onTap: () => setState(_pending.clear),
              child: Container(
                width: double.infinity,
                margin: EdgeInsets.fromLTRB(12, 0, 12, 6),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(color: C.g2, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Icon(Icons.attach_file_rounded, color: C.accent2, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text('${_pending.length} file(s) ready - tap send (tap here to clear)', style: TextStyle(color: C.muted, fontSize: 13))),
                ]),
              ),
            ),
          if (_canWrite)
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  IconButton(onPressed: _attach, icon: Icon(Icons.add_circle_outline_rounded, color: C.accent2, size: 30)),
                  IconButton(onPressed: _sticker, icon: Icon(Icons.emoji_emotions_outlined, color: C.accent2, size: 28)),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: 'Message', contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                    ),
                  ),
                  SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sending ? null : _send,
                    child: Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(gradient: C.grad, shape: BoxShape.circle),
                      child: _sending ? Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : Icon(Icons.send_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ]),
              ),
            )
          else
            Padding(padding: EdgeInsets.all(14), child: Text('You can only read this chat.', style: TextStyle(color: C.muted))),
        ]),
      ),
    );
  }
}

class _Opt extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Opt(this.icon, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 62, height: 62, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withAlpha(60), border: Border.all(color: color.withAlpha(140))), child: Icon(icon, color: color, size: 28)),
          SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 13, color: C.muted)),
        ]),
      );
}

class _DayChip extends StatelessWidget {
  final String text;
  const _DayChip(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(20)),
          child: Text(text, style: TextStyle(fontSize: 12, color: C.muted)),
        ),
      );
}

class _Bubble extends StatelessWidget {
  final Msg m;
  final bool showName;
  const _Bubble({required this.m, required this.showName});

  Future<void> _openFile(BuildContext c, Attach a) async {
    toast(c, 'Opening...');
    final b = await Api.bytes('chat/file/${a.id}');
    if (b == null) {
      if (c.mounted) toast(c, 'Could not open the file.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final safe = a.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final f = File('${dir.path}/${a.id}_$safe');
    await f.writeAsBytes(b);
    await OpenFilex.open(f.path);
  }

  @override
  Widget build(BuildContext context) {
    final mine = m.mine;
    final maxW = MediaQuery.of(context).size.width * .78;
    final stk = m.files.isEmpty ? StickerMsg.parse(m.text) : null;
    if (stk != null) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 3),
          child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (showName) Padding(padding: EdgeInsets.only(bottom: 2, left: 4), child: Text(m.name, style: TextStyle(color: C.accent2, fontSize: 12, fontWeight: FontWeight.w700))),
            StickerView(stk, mine: mine),
            Padding(padding: EdgeInsets.only(top: 2, left: 4, right: 4), child: Text(m.time, style: TextStyle(fontSize: 11, color: C.muted))),
          ]),
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      builder: (_, v, c) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.scale(scale: .94 + .06 * v, alignment: mine ? Alignment.bottomRight : Alignment.bottomLeft, child: c)),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 3),
          constraints: BoxConstraints(maxWidth: maxW),
          padding: EdgeInsets.fromLTRB(14, 9, 14, 7),
          decoration: BoxDecoration(
            gradient: mine ? C.gradMe : null,
            color: mine ? null : (CB.theirBg ?? C.g2),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(mine ? 20 : 6), bottomRight: Radius.circular(mine ? 6 : 20)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (showName) Padding(padding: EdgeInsets.only(bottom: 2), child: Text(m.name, style: TextStyle(color: C.accent2, fontSize: 12, fontWeight: FontWeight.w700))),
            for (final a in m.files)
              Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: a.kind == 'image'
                    ? GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImageViewerPage(cacheKey: 'e${a.id}', loader: () => Api.bytes('chat/file/${a.id}'), title: a.name))),
                        child: AuthImage(cacheKey: 'e${a.id}', loader: () => Api.bytes('chat/file/${a.id}'), width: 230, height: 170, radius: BorderRadius.circular(14)),
                      )
                    : GestureDetector(
                        onTap: () => _openFile(context, a),
                        child: Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Color(0x22000000), borderRadius: BorderRadius.circular(12)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.insert_drive_file_rounded, color: mine ? Colors.white70 : C.sub),
                            SizedBox(width: 8),
                            Flexible(child: Text('${a.name}${a.size.isEmpty ? '' : '  (${a.size})'}', style: TextStyle(fontSize: 14, color: mine ? Colors.white : CB.theirFg))),
                          ]),
                        ),
                      ),
              ),
            if (m.share != null) ShareCardView(m.share!, mine: mine),
            if (m.text.isNotEmpty) LinkText(m.text, style: TextStyle(fontSize: 15.5, height: 1.3, color: mine ? Colors.white : CB.theirFg)),
            SizedBox(height: 3),
            Align(
              alignment: Alignment.centerRight,
              child: Text('${m.edited ? 'edited  ' : ''}${m.time}', style: TextStyle(fontSize: 11, color: mine ? Color(0xCCFFFFFF) : CB.theirMeta)),
            ),
          ]),
        ),
      ),
    );
  }
}
