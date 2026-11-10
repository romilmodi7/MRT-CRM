import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import 'pc_models.dart';
import 'pc_widgets.dart';

/// Photo / video viewer of the private chat: swipe left or right to move to the next or the earlier photo or video
/// (like WhatsApp), pinch or double-tap to zoom, drag down to close.
class PcGallery {
  /// The open chat hands its messages here, so a tap on any photo in the chat can swipe through all of them.
  static List<PcMsg> Function()? source;

  static bool _viewable(PcMsg m) => (m.type == 'image' || m.type == 'video') && m.id > 0 && !m.pending && !m.failed && m.st != 'hide' && m.st != 'gone';

  /// from a bubble in the chat (messages are oldest first)
  static void openFromChat(BuildContext context, PcMsg m) {
    final all = (source?.call() ?? <PcMsg>[]).where(_viewable).toList();
    final i = all.indexWhere((e) => e.id == m.id);
    open(context, i < 0 ? [m] : all, i < 0 ? 0 : i);
  }

  static void open(BuildContext context, List<PcMsg> items, int index) {
    if (items.isEmpty) return;
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      transitionDuration: Duration(milliseconds: 180),
      reverseTransitionDuration: Duration(milliseconds: 150),
      pageBuilder: (_, __, ___) => PcGalleryPage(items: items, index: index.clamp(0, items.length - 1)),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }
}

class PcGalleryPage extends StatefulWidget {
  final List<PcMsg> items;
  final int index;
  const PcGalleryPage({super.key, required this.items, required this.index});
  @override
  State<PcGalleryPage> createState() => _PcGalleryPageState();
}

class _PcGalleryPageState extends State<PcGalleryPage> {
  late final PageController _pc = PageController(initialPage: widget.index);
  late int _cur = widget.index;
  bool _zoomed = false, _bars = true;
  double _dragY = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pc.dispose();
    super.dispose();
  }

  PcMsg get _m => widget.items[_cur];

  @override
  Widget build(BuildContext context) {
    final fade = (1 - (_dragY.abs() / 420)).clamp(0.2, 1.0);
    final n = widget.items.length;
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.black.withAlpha((255 * fade).round()),
      body: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _bars = !_bars),
            onVerticalDragUpdate: (d) {
              if (!_zoomed) setState(() => _dragY += d.delta.dy);
            },
            onVerticalDragEnd: (d) {
              if (_dragY.abs() > 110 || (d.primaryVelocity ?? 0).abs() > 900) {
                Navigator.pop(context);
              } else {
                setState(() => _dragY = 0);
              }
            },
            child: Transform.translate(
              offset: Offset(0, _dragY),
              child: PageView.builder(
                controller: _pc,
                physics: _zoomed ? NeverScrollableScrollPhysics() : BouncingScrollPhysics(),
                itemCount: n,
                onPageChanged: (i) => setState(() {
                  _cur = i;
                  _zoomed = false;
                  _dragY = 0;
                }),
                itemBuilder: (_, i) {
                  final m = widget.items[i];
                  return m.type == 'video'
                      ? _VideoPoster(m: m)
                      : _ZoomPage(key: ValueKey('g${m.id}'), m: m, onZoom: (z) {
                          if (i == _cur && z != _zoomed) setState(() => _zoomed = z);
                        });
                },
              ),
            ),
          ),
        ),
        // top bar: close, who / when, counter
        AnimatedPositioned(
          duration: Duration(milliseconds: 180),
          top: _bars ? 0 : -140,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.only(top: top + 4, left: 6, right: 16, bottom: 22),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xCC000000), Color(0x00000000)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_m.mine ? 'You' : 'Them', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, decoration: TextDecoration.none)),
                  Text('${dayLabel(_m.ts)} · ${clock(_m.ts)}', style: TextStyle(color: Colors.white70, fontSize: 12.5, decoration: TextDecoration.none)),
                ]),
              ),
              if (n > 1)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(color: Color(0x44FFFFFF), borderRadius: BorderRadius.circular(20)),
                  child: Text('${_cur + 1} / $n', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800, decoration: TextDecoration.none)),
                ),
            ]),
          ),
        ),
        // caption
        if ((_m.body ?? '').isNotEmpty)
          AnimatedPositioned(
            duration: Duration(milliseconds: 180),
            bottom: _bars ? 0 : -160,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(18, 24, 18, bottom + 16),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0x00000000), Color(0xCC000000)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
              child: Text(_m.body!, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 15, height: 1.35, decoration: TextDecoration.none)),
            ),
          ),
        // arrows hint on the first view
        if (n > 1 && _bars) ...[
          if (_cur > 0) Positioned(left: 4, top: 0, bottom: 0, child: IgnorePointer(child: Center(child: Icon(Icons.chevron_left_rounded, color: Colors.white38, size: 34)))),
          if (_cur < n - 1) Positioned(right: 4, top: 0, bottom: 0, child: IgnorePointer(child: Center(child: Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 34)))),
        ],
      ]),
    );
  }
}

class _ZoomPage extends StatefulWidget {
  final PcMsg m;
  final void Function(bool zoomed) onZoom;
  const _ZoomPage({super.key, required this.m, required this.onZoom});
  @override
  State<_ZoomPage> createState() => _ZoomPageState();
}

class _ZoomPageState extends State<_ZoomPage> with SingleTickerProviderStateMixin {
  final _tc = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: Duration(milliseconds: 220));
  Animation<Matrix4>? _tween;
  Offset _tap = Offset.zero;
  bool _was = false;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      if (_tween != null) _tc.value = _tween!.value;
    });
    _tc.addListener(() {
      final z = _tc.value.getMaxScaleOnAxis() > 1.02;
      if (z != _was) {
        _was = z;
        widget.onZoom(z);
      }
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _double() {
    final zoomed = _tc.value.getMaxScaleOnAxis() > 1.02;
    final end = zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
          ..translate(-_tap.dx * 1.5, -_tap.dy * 1.5)
          ..scale(2.5));
    _tween = Matrix4Tween(begin: _tc.value, end: end).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final m = widget.m;
    return GestureDetector(
      onDoubleTapDown: (d) => _tap = d.localPosition,
      onDoubleTap: _double,
      child: InteractiveViewer(
        transformationController: _tc,
        minScale: 1,
        maxScale: 6,
        clipBehavior: Clip.none,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Center(child: AuthImage(cacheKey: 'p${m.id}', loader: () => mediaBytes(m.id), width: size.width, height: size.height, fit: BoxFit.contain, fullRes: true)),
        ),
      ),
    );
  }
}

/// A video inside the swipe gallery: poster with a play button (the player opens on tap, so only one video is loaded at a time).
class _VideoPoster extends StatelessWidget {
  final PcMsg m;
  const _VideoPoster({required this.m});
  @override
  Widget build(BuildContext context) => Center(
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPage(m: m))),
          child: Container(
            width: MediaQuery.of(context).size.width - 40,
            height: 250,
            decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1B1450), Color(0xFF0B0E22)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(22)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 72, height: 72, decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0x66FFFFFF)), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48)),
              SizedBox(height: 12),
              Text('Video${m.size > 0 ? '  ·  ${fmtSize(m.size)}' : ''}', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
              SizedBox(height: 4),
              Text('Tap to play', style: TextStyle(color: Colors.white38, fontSize: 12, decoration: TextDecoration.none)),
            ]),
          ),
        ),
      );
}
