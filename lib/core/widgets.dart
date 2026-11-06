import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform.dart';
import 'theme.dart';
import 'util.dart';

/// Small in-memory picture cache (nothing is written to the phone's storage / gallery).
class MemCache {
  static final Map<String, Uint8List> _m = {};
  static int _bytes = 0;
  static const _max = 60 * 1024 * 1024;

  static Uint8List? get(String k) {
    final v = _m.remove(k);
    if (v != null) _m[k] = v;
    return v;
  }

  static void put(String k, Uint8List v) {
    final old = _m.remove(k);
    if (old != null) _bytes -= old.length;
    _m[k] = v;
    _bytes += v.length;
    while (_bytes > _max && _m.isNotEmpty) {
      final first = _m.keys.first;
      _bytes -= _m.remove(first)!.length;
    }
  }

  static void clear() {
    _m.clear();
    _bytes = 0;
  }
}

/// A picture fetched with the login (header) and kept only in memory.
class AuthImage extends StatefulWidget {
  final String cacheKey;
  final Future<Uint8List?> Function() loader;
  final double? width, height;
  final BoxFit fit;
  final BorderRadius radius;
  final bool fullRes; // full-screen viewer: decode at the real size so zoom stays sharp
  const AuthImage({super.key, required this.cacheKey, required this.loader, this.width, this.height, this.fit = BoxFit.cover, this.radius = BorderRadius.zero, this.fullRes = false});
  @override
  State<AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<AuthImage> {
  Uint8List? _b;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = MemCache.get(widget.cacheKey);
    if (c != null) {
      _b = c;
      return;
    }
    if (mounted) setState(() => _failed = false);
    final b = await widget.loader();
    if (!mounted) return;
    if (b == null || b.isEmpty) {
      setState(() => _failed = true);
    } else {
      MemCache.put(widget.cacheKey, b);
      setState(() => _b = b);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget inner;
    if (_b != null) {
      inner = Image.memory(_b!, width: widget.width, height: widget.height, fit: widget.fit, gaplessPlayback: true,
          cacheWidth: (widget.fullRes || widget.width == null) ? null : (widget.width! * MediaQuery.of(context).devicePixelRatio).round(),
          errorBuilder: (_, __, ___) => _box(Icon(Icons.broken_image_outlined, color: C.muted)));
    } else if (_failed) {
      inner = GestureDetector(
        onTap: () {
          setState(() => _failed = false);
          _load();
        },
        child: _box(Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.refresh_rounded, color: C.muted), SizedBox(height: 4), Text('Tap to retry', style: TextStyle(color: C.muted, fontSize: 11))])),
      );
    } else {
      inner = _box(SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent2)));
    }
    return ClipRRect(borderRadius: widget.radius, child: inner);
  }

  Widget _box(Widget c) => Container(width: widget.width, height: widget.height, color: C.g2, alignment: Alignment.center, child: c);
}

/// Text where every web link is tappable (Instagram / YouTube open in their own app).
class LinkText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const LinkText(this.text, {super.key, required this.style});
  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final List<TapGestureRecognizer> _r = [];

  void _dispose() {
    for (final r in _r) {
      r.dispose();
    }
    _r.clear();
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _dispose();
    final spans = <InlineSpan>[];
    // link colour follows the text colour: light text (on blue / dark bubbles) -> light cyan, dark text (white bubbles) -> strong blue
    final lightText = (widget.style.color ?? C.text).computeLuminance() > .5;
    final linkColor = lightText ? Color(0xFFBDF1FF) : Color(0xFF1D4ED8);
    var i = 0;
    for (final m in kUrlRe.allMatches(widget.text)) {
      if (m.start > i) spans.add(TextSpan(text: widget.text.substring(i, m.start)));
      final url = m.group(0)!;
      final rec = TapGestureRecognizer()..onTap = () => openLink(url);
      _r.add(rec);
      spans.add(TextSpan(text: url, recognizer: rec, style: TextStyle(color: linkColor, decoration: TextDecoration.underline, decorationColor: linkColor, fontWeight: FontWeight.w600)));
      i = m.end;
    }
    if (i < widget.text.length) spans.add(TextSpan(text: widget.text.substring(i)));
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}

/// Pulsing placeholder rows while a list loads.
class Skeleton extends StatefulWidget {
  final int rows;
  const Skeleton({super.key, this.rows = 6});
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: 1100))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => ListView.builder(
        physics: NeverScrollableScrollPhysics(),
        itemCount: widget.rows,
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemBuilder: (_, i) => Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, color: Color.fromRGBO(255, 255, 255, .06 + .06 * _c.value))),
            SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 13, width: 140, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Color.fromRGBO(255, 255, 255, .06 + .06 * _c.value))),
                SizedBox(height: 9),
                Container(height: 11, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Color.fromRGBO(255, 255, 255, .04 + .05 * _c.value))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  const EmptyState({super.key, required this.icon, required this.title, this.sub = ''});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84, height: 84,
            decoration: BoxDecoration(shape: BoxShape.circle, color: C.g1, border: Border.all(color: C.g2)),
            child: Icon(icon, color: C.accent2, size: 38),
          ),
          SizedBox(height: 18),
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (sub.isNotEmpty) ...[SizedBox(height: 6), Text(sub, textAlign: TextAlign.center, style: TextStyle(color: C.muted))],
        ]),
      ),
    );
  }
}

/// Full-screen picture viewer: pinch to zoom, close with the X. No save / share anywhere.
/// Full-screen photo viewer: edge to edge, status bar hidden, pinch / double-tap zoom, swipe down to close.
class ImageViewerPage extends StatefulWidget {
  final String cacheKey;
  final Future<Uint8List?> Function() loader;
  final String title;
  const ImageViewerPage({super.key, required this.cacheKey, required this.loader, this.title = ''});
  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> with SingleTickerProviderStateMixin {
  final _tc = TransformationController();
  late final AnimationController _zoomAnim = AnimationController(vsync: this, duration: Duration(milliseconds: 220));
  Animation<Matrix4>? _zoomTween;
  Offset _dTap = Offset.zero;
  double _dragY = 0;
  bool _bars = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _zoomAnim.addListener(() {
      if (_zoomTween != null) _tc.value = _zoomTween!.value;
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _zoomAnim.dispose();
    _tc.dispose();
    super.dispose();
  }

  bool get _zoomed => _tc.value.getMaxScaleOnAxis() > 1.02;

  void _doubleTap() {
    final end = _zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
          ..translate(-_dTap.dx * 1.5, -_dTap.dy * 1.5)
          ..scale(2.5));
    _zoomTween = Matrix4Tween(begin: _tc.value, end: end).animate(CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOut));
    _zoomAnim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final fade = (1 - (_dragY.abs() / 400)).clamp(0.25, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withAlpha((255 * fade).round()),
      body: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _bars = !_bars),
            onDoubleTapDown: (d) => _dTap = d.localPosition,
            onDoubleTap: _doubleTap,
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
              child: InteractiveViewer(
                transformationController: _tc,
                minScale: 1,
                maxScale: 6,
                clipBehavior: Clip.none,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: Center(child: AuthImage(cacheKey: widget.cacheKey, loader: widget.loader, width: size.width, height: size.height, fit: BoxFit.contain, fullRes: true)),
                ),
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: Duration(milliseconds: 180),
          top: _bars ? 0 : -120,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 4, left: 8, right: 16, bottom: 18),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xCC000000), Color(0x00000000)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28)),
              Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, decoration: TextDecoration.none))),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Confirmation dialog in the app's style.
Future<bool> confirm(BuildContext c, String msg, {String yes = 'Yes', String no = 'Cancel'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      backgroundColor: C.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      content: Text(msg, style: TextStyle(fontSize: 16)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(no)),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(yes, style: TextStyle(color: C.accent2, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  return r == true;
}

Future<String?> askText(BuildContext c, String title, {String initial = '', String hint = '', bool obscure = false}) async {
  final ctl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: c,
    builder: (_) => AlertDialog(
      backgroundColor: C.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(title),
      content: TextField(controller: ctl, autofocus: true, obscureText: obscure, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: Text('OK', style: TextStyle(color: C.accent2, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  return (r == null || r.isEmpty) ? null : r;
}

/// Runs a timer only while the screen is alive and the app is in front.
class Poller {
  Timer? _t;
  final Duration every;
  final Future<void> Function() fn;
  bool _busy = false;
  Poller(this.every, this.fn);

  void start() {
    stop();
    _t = Timer.periodic(every, (_) async {
      if (_busy) return;
      _busy = true;
      try {
        await fn();
      } catch (_) {}
      _busy = false;
    });
  }

  void stop() {
    _t?.cancel();
    _t = null;
  }
}

/// Locks the owner's private screens after the app was away for a while.
mixin AwayLock<T extends StatefulWidget> on State<T>, WidgetsBindingObserver {
  DateTime? _left;
  int get awaySeconds => 45;
  void onAwayLock();

  void awayInit() => WidgetsBinding.instance.addObserver(this);
  void awayDispose() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) _left = DateTime.now();
    if (s == AppLifecycleState.resumed) {
      final l = _left;
      _left = null;
      if (l != null && DateTime.now().difference(l).inSeconds > awaySeconds) onAwayLock();
    }
    onLifecycle(s);
  }

  void onLifecycle(AppLifecycleState s) {}
}
