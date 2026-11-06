import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';

import '../core/api.dart';
import '../core/platform.dart';
import '../core/stickers.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import 'pc_models.dart';

Future<Uint8List?> mediaBytes(int id) => PcApi.bytes(PcApi.room('media/$id'));

/// Downloads a message's file into the private temp folder (wiped when the chat closes).
Future<File?> mediaFile(PcMsg m, String ext) async {
  if (m.localPath != null && File(m.localPath!).existsSync()) return File(m.localPath!);
  final b = await mediaBytes(m.id);
  if (b == null) return null;
  final d = await pcTmp();
  final f = File('${d.path}/m${m.id}.$ext');
  await f.writeAsBytes(b, flush: true);
  return f;
}

String extOf(PcMsg m) {
  final n = m.mediaName;
  final i = n.lastIndexOf('.');
  if (i > 0 && i < n.length - 1) return n.substring(i + 1).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (m.type == 'video') return 'mp4';
  if (m.type == 'audio') return 'm4a';
  return 'bin';
}

class PcBubble extends StatelessWidget {
  final PcMsg m;
  final bool showDeleted;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;
  final void Function(int id) onJump;
  final VoidCallback? onSwipeReply;
  const PcBubble({super.key, required this.m, required this.showDeleted, required this.onLongPress, required this.onRetry, required this.onJump, this.onSwipeReply});

  Color get _fg => m.mine ? Colors.white : CB.theirFg;
  Color get _meta => m.mine ? Color(0xCCFFFFFF) : CB.theirMeta;

  @override
  Widget build(BuildContext context) {
    final mine = m.mine;
    final maxW = MediaQuery.of(context).size.width * .78;

    if (m.type == 'sticker' && (m.mediaName.isEmpty) && (m.body ?? '').isNotEmpty) {
      return _wrap(context, mine, child: Text(m.body!, style: TextStyle(fontSize: 64)), bare: true, maxW: maxW);
    }
    if (m.type == 'sticker') {
      return _wrap(context, mine, child: AuthImage(cacheKey: 'p${m.id}', loader: () => mediaBytes(m.id), width: 150, height: 150, fit: BoxFit.contain), bare: true, maxW: maxW);
    }
    final stk = m.type == 'text' ? StickerMsg.parse(m.body) : null;
    if (stk != null) {
      return _wrap(context, mine, child: StickerView(stk, mine: mine), bare: true, maxW: maxW);
    }
    if (m.type == 'gone') {
      return _wrap(context, mine, maxW: maxW, child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block_rounded, size: 16, color: C.hint),
        SizedBox(width: 6),
        Flexible(child: Text(m.note ?? 'This message was deleted', style: TextStyle(fontStyle: FontStyle.italic, color: C.muted))),
      ]));
    }

    final children = <Widget>[];
    if (m.reply != null) children.add(_quote(m.reply!));
    switch (m.type) {
      case 'image':
        children.add(_image(context));
        break;
      case 'video':
        children.add(_video(context));
        break;
      case 'audio':
        children.add(VoiceBubble(m: m));
        break;
      case 'file':
        children.add(_file(context));
        break;
      case 'gif':
        children.add(ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(m.gif ?? '', width: 220, fit: BoxFit.cover, errorBuilder: (_, __, ___) => SizedBox(width: 220, height: 120, child: Center(child: Text('GIF', style: TextStyle(color: C.muted))))),
        ));
        break;
      case 'location':
        children.add(_location());
        break;
      case 'contact':
        children.add(_contact(context));
        break;
      default:
        if ((m.body ?? '').isNotEmpty) children.add(LinkText(m.body!, style: TextStyle(fontSize: 15.5, height: 1.3, color: _fg)));
    }
    if (m.isMedia && (m.body ?? '').isNotEmpty) {
      children.add(Padding(padding: EdgeInsets.only(top: 6), child: LinkText(m.body!, style: TextStyle(fontSize: 15, color: _fg))));
    }
    if (m.note != null && m.note!.isNotEmpty) {
      children.add(Padding(padding: EdgeInsets.only(top: 4), child: Text(m.note!, style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFFFFB3BB)))));
    }
    children.add(SizedBox(height: 3));
    children.add(Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
      if (m.edited) Text('edited  ', style: TextStyle(fontSize: 11, color: _meta)),
      Text(m.ts == 0 ? '' : clock(m.ts), style: TextStyle(fontSize: 11, color: _meta)),
      if (mine) ...[SizedBox(width: 4), _ticks()],
    ]));

    final grouped = <String, int>{};
    final mineRx = <String>{};
    for (final r in m.rx) {
      grouped[r.e] = (grouped[r.e] ?? 0) + 1;
      if (r.mine) mineRx.add(r.e);
    }

    return _wrap(context, mine, maxW: maxW, ghost: m.st == 'ghost', failed: m.failed, rxRow: grouped.isEmpty
        ? null
        : Wrap(spacing: 4, children: [
            for (final e in grouped.entries)
              _Pop(key: ValueKey('rx${m.id}${e.key}${e.value}'), child: Container(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: mineRx.contains(e.key) ? C.accent2 : C.g3)),
                child: Text(e.value > 1 ? '${e.key} ${e.value}' : e.key, style: TextStyle(fontSize: 13)),
              )),
          ]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children));
  }

  Widget _ticks() {
    if (m.pending) return SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.6, color: C.sub));
    if (m.failed) return Icon(Icons.error_outline_rounded, size: 14, color: Color(0xFFFFB3BB));
    return Icon(m.tick >= 2 ? Icons.done_all_rounded : Icons.done_rounded, size: 15, color: m.tick >= 3 ? Color(0xFF7DF3FF) : Color(0xCCFFFFFF));
  }

  Widget _wrap(BuildContext context, bool mine, {required Widget child, required double maxW, bool bare = false, bool ghost = false, bool failed = false, Widget? rxRow}) {
    final shadow = bare
        ? <BoxShadow>[]
        : [BoxShadow(color: mine ? C.accent.withAlpha(C.dark ? 70 : 60) : Color(C.dark ? 0x00000000 : 0x14101828), blurRadius: mine ? 14 : 6, offset: Offset(0, 4))];
    return TweenAnimationBuilder<double>(
      key: ValueKey('b${m.id}'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset((mine ? 26 : -26) * (1 - v), 12 * (1 - v)), child: Transform.scale(scale: .92 + .08 * v, alignment: mine ? Alignment.bottomRight : Alignment.bottomLeft, child: c)),
      ),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: _SwipeReply(
          enabled: onSwipeReply != null && !m.pending && m.st != 'ghost',
          onTrigger: () => onSwipeReply?.call(),
          child: GestureDetector(
            onLongPress: m.pending ? null : onLongPress,
            onTap: failed ? onRetry : null,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 3),
              child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                Container(
                  constraints: BoxConstraints(maxWidth: maxW),
                  padding: bare ? EdgeInsets.zero : EdgeInsets.fromLTRB(12, 8, 12, 6),
                  decoration: bare
                      ? null
                      : BoxDecoration(
                          gradient: mine ? C.gradMe : null,
                          color: mine ? null : (CB.theirBg ?? (C.dark ? C.g3 : Colors.white)),
                          boxShadow: shadow,
                          borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(mine ? 20 : 6), bottomRight: Radius.circular(mine ? 6 : 20)),
                          border: ghost ? Border.all(color: Color(0x88FF5D6C)) : null,
                        ),
                  child: Opacity(opacity: ghost ? .65 : 1, child: DefaultTextStyle.merge(style: TextStyle(color: _fg), child: child)),
                ),
                if (rxRow != null) Transform.translate(offset: Offset(0, -6), child: rxRow),
                if (failed) Padding(padding: EdgeInsets.only(top: 2), child: Text('Not sent - tap to retry', style: TextStyle(fontSize: 11, color: C.danger))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quote(ReplyRef r) => GestureDetector(
        onTap: r.gone ? null : () => onJump(r.id),
        child: Container(
          margin: EdgeInsets.only(bottom: 6),
          padding: EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(color: C.g2, borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: C.accent2, width: 3))),
          child: Text(r.gone ? 'Message deleted' : r.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: r.gone ? C.hint : C.sub, fontStyle: r.gone ? FontStyle.italic : FontStyle.normal)),
        ),
      );

  Widget _image(BuildContext context) {
    final local = m.localPath;
    final w = Widget_imageSize;
    final img = local != null && m.id < 0
        ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(File(local), width: w, height: 200, fit: BoxFit.cover, errorBuilder: (_, __, ___) => SizedBox(width: w, height: 200)))
        : AuthImage(cacheKey: 'p${m.id}', loader: () => mediaBytes(m.id), width: w, height: 200, radius: BorderRadius.circular(14));
    return GestureDetector(
      onTap: m.id < 0 ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImageViewerPage(cacheKey: 'p${m.id}', loader: () => mediaBytes(m.id), title: ''))),
      child: img,
    );
  }

  static const double Widget_imageSize = 230;

  Widget _video(BuildContext context) => GestureDetector(
        onTap: m.id < 0 ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPage(m: m))),
        child: Container(
          width: 230, height: 150,
          decoration: BoxDecoration(color: Color(0xFF0B0E22), borderRadius: BorderRadius.circular(14)),
          child: Stack(alignment: Alignment.center, children: [
            Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0x66FFFFFF)), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38)),
            Positioned(left: 10, bottom: 8, child: Text('Video${m.size > 0 ? '  ${fmtSize(m.size)}' : ''}', style: TextStyle(fontSize: 12, color: C.sub))),
          ]),
        ),
      );

  Widget _file(BuildContext context) => GestureDetector(
        onTap: m.id < 0 ? null : () async {
          toast(context, 'Opening...');
          final f = await mediaFile(m, extOf(m));
          if (f == null) {
            if (context.mounted) toast(context, 'Could not open the file.');
            return;
          }
          await OpenFilex.open(f.path);
        },
        child: Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(color: Color(0x22000000), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.insert_drive_file_rounded, color: C.sub),
            SizedBox(width: 8),
            Flexible(child: Text('${m.mediaName}${m.size > 0 ? '  (${fmtSize(m.size)})' : ''}', style: TextStyle(fontSize: 14))),
          ]),
        ),
      );

  Map<String, dynamic> _json() {
    try {
      final d = jsonDecode(m.body ?? '{}');
      return d is Map<String, dynamic> ? d : {};
    } catch (_) {
      return {};
    }
  }

  Widget _location() {
    final j = _json();
    final lat = (j['lat'] as num?)?.toDouble(), lng = (j['lng'] as num?)?.toDouble();
    return GestureDetector(
      onTap: lat == null || lng == null ? null : () => openMap(lat, lng),
      child: Container(
        width: 210,
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(color: Color(0x22000000), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, gradient: C.grad), child: Icon(Icons.location_on_rounded, color: Colors.white)),
          SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Location', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(lat == null ? '' : '${lat.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}', style: TextStyle(fontSize: 12, color: C.sub)),
            Text('Tap to open in Maps', style: TextStyle(fontSize: 11, color: C.accent2)),
          ])),
        ]),
      ),
    );
  }

  Widget _contact(BuildContext context) {
    final j = _json();
    return GestureDetector(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: (j['phone'] ?? '').toString()));
        if (context.mounted) toast(context, 'Number copied');
      },
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(color: Color(0x22000000), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Avatar((j['name'] ?? '?').toString(), size: 38),
          SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((j['name'] ?? '').toString(), style: TextStyle(fontWeight: FontWeight.w700)),
            Text((j['phone'] ?? '').toString(), style: TextStyle(fontSize: 13, color: C.sub)),
          ]),
        ]),
      ),
    );
  }
}

/// Voice message: play / pause with a progress bar. The file is downloaded to the private temp folder only.
class VoiceBubble extends StatefulWidget {
  final PcMsg m;
  const VoiceBubble({super.key, required this.m});
  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  AudioPlayer? _p;
  bool _loading = false, _playing = false;
  Duration _pos = Duration.zero;
  StreamSubscription? _s1, _s2;

  @override
  void dispose() {
    _s1?.cancel();
    _s2?.cancel();
    _p?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (widget.m.id < 0 && widget.m.localPath == null) return;
    try {
      if (_p == null) {
        setState(() => _loading = true);
        final f = await mediaFile(widget.m, extOf(widget.m));
        if (f == null) {
          if (mounted) {
            setState(() => _loading = false);
            toast(context, 'Could not load the voice message.');
          }
          return;
        }
        final p = AudioPlayer();
        await p.setFilePath(f.path);
        _p = p;
        _s1 = p.positionStream.listen((x) {
          if (mounted) setState(() => _pos = x);
        });
        _s2 = p.playerStateStream.listen((s) {
          if (s.processingState == ProcessingState.completed) {
            p.pause();
            p.seek(Duration.zero);
          }
          if (mounted) setState(() => _playing = s.playing && s.processingState != ProcessingState.completed);
        });
        if (mounted) setState(() => _loading = false);
      }
      if (_p!.playing) {
        await _p!.pause();
      } else {
        _p!.play();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, 'Could not play this voice message.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.m.dur > 0 ? widget.m.dur : 1;
    final frac = (_pos.inMilliseconds / (total * 1000)).clamp(0.0, 1.0);
    final fg = widget.m.mine ? Colors.white : C.accent;
    final track = widget.m.mine ? Color(0x44FFFFFF) : C.g3;
    return SizedBox(
      width: 220,
      child: Row(children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: track),
            child: _loading
                ? Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                : Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: fg, size: 28),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: frac, minHeight: 4, backgroundColor: track, color: fg)),
            SizedBox(height: 6),
            Row(children: [
              Icon(Icons.mic_rounded, size: 13, color: C.sub),
              SizedBox(width: 3),
              Text(_playing || _pos > Duration.zero ? mmss(_pos.inSeconds) : mmss(widget.m.dur), style: TextStyle(fontSize: 12, color: C.sub)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Plays a video from the private temp folder.
class VideoPage extends StatefulWidget {
  final PcMsg m;
  const VideoPage({super.key, required this.m});
  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  VideoPlayerController? _c;
  String _err = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final f = await mediaFile(widget.m, extOf(widget.m));
    if (f == null) {
      if (mounted) setState(() => _err = 'Could not load the video.');
      return;
    }
    try {
      final c = VideoPlayerController.file(f);
      await c.initialize();
      c.setLooping(false);
      c.addListener(() {
        if (mounted) setState(() {});
      });
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _c = c);
      c.play();
    } catch (_) {
      if (mounted) setState(() => _err = 'This video cannot be played.');
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(
          child: _err.isNotEmpty
              ? Text(_err, style: TextStyle(color: C.sub))
              : c == null
                  ? CircularProgressIndicator(color: C.accent2)
                  : GestureDetector(
                      onTap: () => c.value.isPlaying ? c.pause() : c.play(),
                      child: AspectRatio(aspectRatio: c.value.aspectRatio, child: Stack(alignment: Alignment.center, children: [
                        VideoPlayer(c),
                        if (!c.value.isPlaying) Container(width: 70, height: 70, decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0x88000000)), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48)),
                      ])),
                    ),
        ),
        if (c != null) Positioned(left: 16, right: 16, bottom: 30, child: VideoProgressIndicator(c, allowScrubbing: true, colors: VideoProgressColors(playedColor: C.accent2))),
        SafeArea(child: Padding(padding: EdgeInsets.all(8), child: IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: Colors.white, size: 28)))),
      ]),
    );
  }
}


/// Small bounce when a reaction appears.
class _Pop extends StatelessWidget {
  final Widget child;
  const _Pop({super.key, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.4, end: 1),
        duration: Duration(milliseconds: 420),
        curve: Curves.elasticOut,
        builder: (_, v, c) => Transform.scale(scale: v, child: c),
        child: child,
      );
}

/// Drag a message sideways to reply to it (like WhatsApp).
class _SwipeReply extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final VoidCallback onTrigger;
  const _SwipeReply({required this.child, required this.enabled, required this.onTrigger});
  @override
  State<_SwipeReply> createState() => _SwipeReplyState();
}

class _SwipeReplyState extends State<_SwipeReply> {
  double _dx = 0;
  bool _fired = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final p = (_dx / 70).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) {
        setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, 90.0));
        if (_dx >= 70 && !_fired) {
          _fired = true;
          HapticFeedback.mediumImpact();
          widget.onTrigger();
        }
      },
      onHorizontalDragEnd: (_) => setState(() {
        _dx = 0;
        _fired = false;
      }),
      onHorizontalDragCancel: () => setState(() {
        _dx = 0;
        _fired = false;
      }),
      child: Stack(alignment: Alignment.centerLeft, children: [
        Positioned(left: 4, child: Opacity(opacity: p, child: Transform.scale(scale: .6 + .4 * p, child: Icon(Icons.reply_rounded, color: C.accent2)))),
        AnimatedContainer(duration: Duration(milliseconds: _dx == 0 ? 180 : 0), transform: Matrix4.translationValues(_dx, 0, 0), child: widget.child),
      ]),
    );
  }
}
