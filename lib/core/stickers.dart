import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'session.dart';
import 'theme.dart';
import 'widgets.dart';

/// One sticker = a big emoji with an optional short caption, or a sticker from a CRM pack (id > 0):
/// a picture (img), an animated Telegram sticker (tgs) or a video sticker (webm).
class Sticker {
  final String e;
  final String cap;
  final int id;      // sticker from a CRM pack (0 = emoji sticker)
  final String kind; // img | tgs | webm
  const Sticker(this.e, [this.cap = '', this.id = 0, this.kind = 'img']);
  bool get isImage => id > 0;
}

class StickerPack {
  final String name;
  final String icon;
  final List<Sticker> items;
  const StickerPack(this.name, this.icon, this.items);
}

/// Built-in sticker packs (no download needed, work offline).
const List<StickerPack> kStickerPacks = [
  StickerPack('Work', '💼', [
    Sticker('👍', 'Done'), Sticker('✅', 'Completed'), Sticker('⏳', 'In progress'), Sticker('📞', 'Call me'),
    Sticker('🙏', 'Thank you'), Sticker('👌', 'Okay'), Sticker('🚀', 'On it'), Sticker('📌', 'Noted'),
    Sticker('🕒', 'Give me 5 min'), Sticker('📎', 'Sending file'), Sticker('🤝', 'Deal'), Sticker('🎯', 'Target hit'),
  ]),
  StickerPack('Happy', '😀', [
    Sticker('😀', 'Hello'), Sticker('😂', 'LOL'), Sticker('😍', 'Love it'), Sticker('🥳', 'Party'),
    Sticker('😎', 'Cool'), Sticker('🤩', 'Wow'), Sticker('😇', 'Blessed'), Sticker('🤗', 'Hug'),
    Sticker('😉', 'Sure'), Sticker('🥰', 'Thanks'), Sticker('😁', 'Great'), Sticker('🙌', 'Yay'),
  ]),
  StickerPack('Mood', '😴', [
    Sticker('😴', 'Sleepy'), Sticker('😭', 'Cry'), Sticker('😡', 'Angry'), Sticker('🤔', 'Thinking'),
    Sticker('😅', 'Oops'), Sticker('🤯', 'Mind blown'), Sticker('😬', 'Awkward'), Sticker('🥺', 'Please'),
    Sticker('😮‍💨', 'Tired'), Sticker('🤒', 'Not well'), Sticker('😤', 'Hmm'), Sticker('🙄', 'Seriously'),
  ]),
  StickerPack('Festival', '🎉', [
    Sticker('🎉', 'Congrats'), Sticker('🎂', 'Happy Birthday'), Sticker('🪔', 'Happy Diwali'), Sticker('🎊', 'Celebrate'),
    Sticker('🌹', 'Best wishes'), Sticker('🎁', 'Gift'), Sticker('✨', 'Shine'), Sticker('🥂', 'Cheers'),
    Sticker('🎆', 'Fireworks'), Sticker('🍰', 'Treat'), Sticker('🏆', 'Winner'), Sticker('🎈', 'Fun'),
  ]),
  StickerPack('Reactions', '👏', [
    Sticker('👏', 'Well done'), Sticker('💪', 'Strong'), Sticker('🔥', 'Fire'), Sticker('💯', '100%'),
    Sticker('❤️', 'Love'), Sticker('👀', 'Looking'), Sticker('🙈', 'Oops'), Sticker('🤞', 'Fingers crossed'),
    Sticker('👋', 'Bye'), Sticker('☕', 'Tea time'), Sticker('🍕', 'Lunch?'), Sticker('🌙', 'Good night'),
  ]),
];

/// A sticker travels as a normal text message: invisible marker + emoji + invisible marker + caption.
/// Old apps / the website simply show "🔥 Fire".
class StickerMsg {
  static const _m = '⁣';

  static const _pre = {'img': 'st', 'tgs': 'sa', 'webm': 'sv'};

  static String encode(Sticker s) => '$_m${s.isImage ? '${_pre[s.kind] ?? 'st'}:${s.id}' : s.e}${s.cap.isEmpty ? '' : '$_m${s.cap}'}';

  static Sticker? parse(String? t) {
    if (t == null || !t.startsWith(_m)) return null;
    final p = t.substring(1).split(_m);
    if (p.isEmpty || p[0].isEmpty || p[0].length > 16) return null;
    final cap = p.length > 1 ? p.sublist(1).join(' ') : '';
    final img = RegExp(r'^s([tav]):(\d{1,9})$').firstMatch(p[0]);
    if (img != null) return Sticker('', cap, int.parse(img.group(2)!), {'a': 'tgs', 'v': 'webm'}[img.group(1)] ?? 'img');
    return Sticker(p[0], cap);
  }
}

/// How a sticker looks inside the chat.
class StickerView extends StatelessWidget {
  final Sticker s;
  final bool mine;
  final bool pc;   // shown in the private chat (its stickers are loaded through the room)
  const StickerView(this.s, {super.key, this.mine = false, this.pc = false});
  @override
  Widget build(BuildContext context) {
    if (s.isImage) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        StickerImage(s.id, kind: s.kind, pc: pc, size: 150),
        if (s.cap.isNotEmpty) Padding(padding: EdgeInsets.only(top: 2), child: Text(s.cap, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: C.text))),
      ]);
    }
    return Container(
      padding: EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [C.accent.withAlpha(C.dark ? 60 : 30), C.accent2.withAlpha(C.dark ? 50 : 24)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: C.accent.withAlpha(90)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(s.e, style: TextStyle(fontSize: 62, height: 1.1)),
        if (s.cap.isNotEmpty) ...[
          SizedBox(height: 4),
          Text(s.cap, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.text)),
        ],
      ]),
    );
  }
}

/// Sticker packs made in the CRM ("Chat stickers" screen). Team chat and private chat each keep their own list
/// (private chat also gets the "private chat only" packs). The lists are kept on the phone and refreshed when the
/// sticker panel opens; every sticker file is downloaded once and kept, so it also shows without internet.
class _Job {
  final int id;
  final bool pc;
  _Job(this.id, this.pc);
}

class StickerStore {
  static final Map<bool, List<StickerPack>> _packs = {false: _read(Session.getString('stk_packs')), true: _read(Session.getString('stk_packs_pc'))};
  static final Map<bool, DateTime> _at = {};

  static List<StickerPack> packs(bool pc) => _packs[pc] ?? const [];

  /// goes up when a pack list changes (an open sticker panel redraws itself)
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static List<StickerPack> _read(String? raw) {
    try {
      final j = jsonDecode(raw ?? '');
      return [
        for (final p in ((j as Map)['packs'] as List).whereType<Map>())
          StickerPack((p['name'] ?? 'Pack').toString(), (p['icon'] ?? '⭐').toString(), [
            for (final s in ((p['items'] as List?) ?? const []).whereType<Map>())
              s['img'] == true
                  ? Sticker('', (s['cap'] ?? '').toString(), (s['id'] as num?)?.toInt() ?? 0, (s['k'] ?? 'img').toString())
                  : Sticker((s['e'] ?? '').toString(), (s['cap'] ?? '').toString()),
          ]),
      ];
    } catch (_) {
      return [];
    }
  }

  /// Ask the server for the packs (at most once a minute).
  static Future<void> refresh({bool pc = false}) async {
    final last = _at[pc];
    if (last != null && DateTime.now().difference(last).inSeconds < 60) return;
    if (pc && PcApi.token == null) return;
    try {
      final r = await (pc ? PcApi.get(PcApi.room('x/stickers')) : Api.get('stickers')).timeout(Duration(seconds: 6));
      if (!r.ok || r.data is! Map) return;
      _at[pc] = DateTime.now();
      final key = pc ? 'stk_packs_pc' : 'stk_packs';
      final raw = jsonEncode(r.data);
      if (raw == Session.getString(key)) return;
      await Session.setString(key, raw);
      _packs[pc] = _read(raw);
      changed.value++;
    } catch (_) {}
  }

  /* -------- quick loading: sticker files are fetched in the background, a few at a time, and kept on the phone */
  static final List<_Job> _queue = [];
  static final Set<int> _queued = {};
  static int _running = 0;
  static const int _parallel = 4;

  /// Get these stickers ready (first ones first). Already kept stickers cost nothing.
  static void prefetch(Iterable<Sticker> list, {bool pc = false, bool front = false}) {
    final jobs = [for (final s in list) if (s.isImage && !_queued.contains(s.id)) _Job(s.id, pc)];
    for (final j in jobs) {
      _queued.add(j.id);
    }
    front ? _queue.insertAll(0, jobs) : _queue.addAll(jobs);
    _pump();
  }

  /// The stickers of this pack go to the front of the line (the pack that was just opened).
  static void prefetchPack(StickerPack p, {bool pc = false}) {
    final ids = {for (final s in p.items) if (s.isImage) s.id};
    _queue.removeWhere((j) => ids.contains(j.id));
    _queued.removeAll(ids);
    prefetch(p.items, pc: pc, front: true);
  }

  static void _pump() {
    while (_running < _parallel && _queue.isNotEmpty) {
      final j = _queue.removeAt(0);
      _running++;
      load(j.id, pc: j.pc).whenComplete(() {
        _running--;
        _pump();
      });
    }
  }

  static Future<File> file(int id) async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/stickers');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/$id.stk');
  }

  static final Map<int, Future<File?>> _loading = {};

  /// The file of a sticker: from the phone if it was loaded before, else from the server (and then kept).
  static Future<File?> load(int id, {bool pc = false}) => _loading[id] ??= _load(id, pc).whenComplete(() => _loading.remove(id));

  static final Set<int> _have = {};
  static String? _dir;

  /// true when the sticker file is already on the phone (no waiting)
  static bool has(int id) => _have.contains(id);

  static Future<File?> _load(int id, bool pc) async {
    try {
      _dir ??= '${(await getApplicationSupportDirectory()).path}/stickers';
      final quick = File('$_dir/$id.stk');
      if (_have.contains(id)) return quick;
      final f = await file(id);
      if (await f.exists() && await f.length() > 0) {
        _have.add(id);
        return f;
      }
      final b = await (pc && PcApi.token != null ? PcApi.bytes(PcApi.room('x/sticker/$id')) : Api.bytes('sticker/$id'));
      if (b == null || b.isEmpty) return null;
      await f.writeAsBytes(b, flush: true);
      _have.add(id);
      return f;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> bytes(int id, {bool pc = false}) async {
    final f = await load(id, pc: pc);
    return f == null ? null : f.readAsBytes();
  }
}

/// A sticker from a CRM pack: a still picture, an animated Telegram sticker (Lottie) or a video sticker (loops, no sound).
/// No bubble around it: stickers have a see-through background.
class StickerImage extends StatelessWidget {
  final int id;
  final String kind;
  final bool pc;
  final double size;
  const StickerImage(this.id, {super.key, this.kind = 'img', this.pc = false, this.size = 140});
  @override
  Widget build(BuildContext context) {
    if (kind == 'tgs') return SizedBox(width: size, height: size, child: _TgsSticker(id: id, pc: pc));
    if (kind == 'webm') return SizedBox(width: size, height: size, child: _VideoSticker(id: id, pc: pc));
    return SizedBox(width: size, height: size, child: _AnySticker(id: id, pc: pc));
  }
}

/// A sticker marked as a picture: the file itself says what it really is (a video or animated sticker that was
/// saved as a picture by an older import still plays), so no sticker waits forever.
class _AnySticker extends StatefulWidget {
  final int id;
  final bool pc;
  const _AnySticker({required this.id, required this.pc});
  @override
  State<_AnySticker> createState() => _AnyStickerState();
}

class _AnyStickerState extends State<_AnySticker> {
  static final Map<int, String> _kind = {};   // what each file turned out to be
  File? _f;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final f = await StickerStore.load(widget.id, pc: widget.pc);
    if (!mounted) return;
    if (f == null) {
      setState(() => _failed = true);
      return;
    }
    if (!_kind.containsKey(widget.id)) {
      String k = 'img';
      try {
        final raf = await f.open();
        final h = await raf.read(4);
        await raf.close();
        if (h.length >= 4 && h[0] == 0x1A && h[1] == 0x45 && h[2] == 0xDF && h[3] == 0xA3) {
          k = 'webm';
        } else if (h.length >= 2 && h[0] == 0x1F && h[1] == 0x8B) {
          k = 'tgs';
        }
      } catch (_) {}
      _kind[widget.id] = k;
    }
    if (mounted) setState(() => _f = f);
  }

  @override
  Widget build(BuildContext context) {
    final f = _f;
    if (f == null) return _StickerWait(failed: _failed);
    final k = _kind[widget.id] ?? 'img';
    if (k == 'webm') return _VideoSticker(id: widget.id, pc: widget.pc);
    if (k == 'tgs') return _TgsSticker(id: widget.id, pc: widget.pc);
    return Image.file(f, fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, __, ___) => _StickerWait(failed: true));
  }
}

class _StickerWait extends StatelessWidget {
  final bool failed;
  const _StickerWait({this.failed = false});
  @override
  Widget build(BuildContext context) => Center(
        child: failed
            ? Icon(Icons.broken_image_outlined, color: C.hint)
            : SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent2)),
      );
}

Uint8List _gunzip(Uint8List b) => Uint8List.fromList(gzip.decode(b));

/// Animated Telegram sticker: a .tgs file is a gzipped Lottie animation.
class _TgsSticker extends StatefulWidget {
  final int id;
  final bool pc;
  const _TgsSticker({required this.id, required this.pc});
  @override
  State<_TgsSticker> createState() => _TgsStickerState();
}

class _TgsStickerState extends State<_TgsSticker> {
  static final Map<int, Uint8List> _json = {};   // unpacked animations, so lists scroll smoothly
  Uint8List? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _data = _json[widget.id];
    if (_data == null) _open();
  }

  Future<void> _open() async {
    final b = await StickerStore.bytes(widget.id, pc: widget.pc);
    if (!mounted) return;
    try {
      if (b == null) throw 'none';
      final j = await compute(_gunzip, b);
      if (_json.length > 120) _json.remove(_json.keys.first);
      _json[widget.id] = j;
      if (mounted) setState(() => _data = j);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) return _StickerWait(failed: _failed);
    return Lottie.memory(d, fit: BoxFit.contain, repeat: true, frameRate: FrameRate.max, errorBuilder: (_, __, ___) => _StickerWait(failed: true));
  }
}

/// Video sticker (.webm): plays on a loop without sound.
class _VideoSticker extends StatefulWidget {
  final int id;
  final bool pc;
  const _VideoSticker({required this.id, required this.pc});
  @override
  State<_VideoSticker> createState() => _VideoStickerState();
}

class _VideoStickerState extends State<_VideoSticker> {
  // starting many video players at the same moment makes all of them slow: at most 3 start together
  static int _starting = 0;
  static final List<Completer<void>> _wait = [];
  static Future<void> _slot() async {
    if (_starting < 3) {
      _starting++;
      return;
    }
    final c = Completer<void>();
    _wait.add(c);
    await c.future;
  }

  static void _free() {
    if (_wait.isNotEmpty) {
      _wait.removeAt(0).complete();
    } else {
      _starting--;
    }
  }

  VideoPlayerController? _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final f = await StickerStore.load(widget.id, pc: widget.pc);
    if (!mounted) return;
    if (f == null) {
      setState(() => _failed = true);
      return;
    }
    await _slot();
    if (!mounted) {
      _free();
      return;
    }
    try {
      final c = VideoPlayerController.file(f, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      try {
        await c.initialize().timeout(Duration(seconds: 8));   // a player that never starts must not block the others
      } catch (_) {
        c.dispose();
        rethrow;
      }
      await c.setVolume(0);
      await c.setLooping(true);
      if (!mounted) {
        c.dispose();
        return;
      }
      await c.play();
      setState(() => _c = c);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _free();
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
    if (c == null || !c.value.isInitialized) return _StickerWait(failed: _failed);
    return FittedBox(fit: BoxFit.contain, child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)));
  }
}

// packs made in the CRM always come first, in the order set there (Chat stickers → "Show first"); then the built-in ones
List<StickerPack> _allPacks(Map? roomPack, bool pc) => [
      ...StickerStore.packs(pc),
      ...kStickerPacks,
      if (roomPack != null && roomPack.isNotEmpty)
        for (final e in roomPack.entries) StickerPack(e.key.toString(), '⭐', [for (final x in (e.value as List)) Sticker(x.toString())]),
    ];

/// Called when a chat opens: the sticker list is refreshed and the first CRM pack is fetched in the background,
/// so the sticker panel opens at once with its stickers ready.
void warmStickers({bool pc = false}) {
  StickerStore.refresh(pc: pc).whenComplete(() {
    final list = StickerStore.packs(pc);
    if (list.isNotEmpty) StickerStore.prefetch(list.first.items, pc: pc);
  });
}

/// Sticker keyboard. Returns the chosen sticker (or null). Opens at once with the packs kept on the phone;
/// the list is refreshed in the background.
Future<Sticker?> pickSticker(BuildContext context, {Map? roomPack, bool pc = false}) async {
  StickerStore.refresh(pc: pc);
  return showModalBottomSheet<Sticker>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _StickerSheet(roomPack: roomPack, pc: pc),
  );
}

class _StickerSheet extends StatefulWidget {
  final Map? roomPack;
  final void Function(Sticker)? onPick;
  final bool pc;
  const _StickerSheet({this.roomPack, this.onPick, this.pc = false});
  @override
  State<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<_StickerSheet> {
  int _i = 0;
  final _grid = ScrollController();

  @override
  void initState() {
    super.initState();
    StickerStore.changed.addListener(_onChange);
    _warm();
  }

  @override
  void dispose() {
    StickerStore.changed.removeListener(_onChange);
    _grid.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
    _warm();
  }

  List<StickerPack> get _packs => _allPacks(widget.roomPack, widget.pc);

  void _warm() {
    final p = _packs;
    if (p.isEmpty) return;
    StickerStore.prefetchPack(p[_i.clamp(0, p.length - 1)], pc: widget.pc);
  }

  void _open(int k) {
    if (k == _i) return;
    setState(() => _i = k);
    if (_grid.hasClients) _grid.jumpTo(0);
    _warm();
  }

  @override
  Widget build(BuildContext context) {
    final packs = _packs;
    if (packs.isEmpty) return SizedBox.shrink();
    final i = _i.clamp(0, packs.length - 1);
    final pack = packs[i];
    final crm = StickerStore.packs(widget.pc).length;
    final w = MediaQuery.of(context).size.width;
    final cols = w >= 600 ? 6 : (w >= 400 ? 4 : 3);
    return SafeArea(
      child: SizedBox(
        height: widget.onPick != null ? null : MediaQuery.of(context).size.height * .55,
        child: Column(children: [
          if (widget.onPick == null) ...[
            SizedBox(height: 10),
            Container(width: 42, height: 4, decoration: BoxDecoration(color: C.g3, borderRadius: BorderRadius.circular(4))),
            SizedBox(height: 8),
          ],
          // pack bar: small icon tabs like Telegram; the name of the open pack shows under it
          Container(
            height: 52,
            margin: EdgeInsets.fromLTRB(10, 2, 10, 0),
            decoration: BoxDecoration(color: C.g1, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 5),
              itemCount: packs.length,
              itemBuilder: (_, k) {
                final sel = k == i;
                final p = packs[k];
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  // a thin line between the CRM packs and the built-in ones
                  if (k == crm && crm > 0) Container(width: 1, height: 24, margin: EdgeInsets.symmetric(horizontal: 5), color: C.line),
                  Tooltip(
                    message: p.name,
                    child: GestureDetector(
                      onTap: () => _open(k),
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 160),
                        width: 42,
                        height: 42,
                        margin: EdgeInsets.symmetric(horizontal: 2),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: sel ? LinearGradient(colors: [C.accent.withAlpha(70), C.accent2.withAlpha(55)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                          borderRadius: BorderRadius.circular(13),
                          border: sel ? Border.all(color: C.accent, width: 1.4) : null,
                        ),
                        child: Text(p.icon, maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontSize: sel ? 23 : 21, height: 1.1)),
                      ),
                    ),
                  ),
                ]);
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Row(children: [
              Expanded(child: Text(pack.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.text))),
              SizedBox(width: 8),
              Text('${pack.items.length}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: C.muted)),
            ]),
          ),
          Expanded(
            child: GridView.builder(
              key: PageStorageKey('stk-$i'),
              controller: _grid,
              padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
              cacheExtent: 300,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 8, crossAxisSpacing: 8),
              itemCount: pack.items.length,
              itemBuilder: (_, k) {
                final s = pack.items[k];
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => widget.onPick != null ? widget.onPick!(s) : Navigator.pop(context, s),
                  child: Container(
                    decoration: BoxDecoration(color: C.g1.withAlpha(140), borderRadius: BorderRadius.circular(14)),
                    padding: EdgeInsets.all(4),
                    child: s.isImage
                        ? StickerImage(s.id, kind: s.kind, pc: widget.pc, size: 88)
                        : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(s.e, style: TextStyle(fontSize: 32)),
                            if (s.cap.isNotEmpty) Padding(padding: EdgeInsets.only(top: 2), child: Text(s.cap, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: C.muted))),
                          ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}


/// Put text (an emoji) into a text box where the cursor is.
void insertAtCursor(TextEditingController c, String t) {
  final v = c.value;
  final sel = v.selection;
  final start = sel.isValid ? sel.start : v.text.length;
  final end = sel.isValid ? sel.end : v.text.length;
  final text = v.text.replaceRange(start, end, t);
  c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: start + t.length));
}

const Map<String, String> kEmojiGroups = {
  '😀': '😀 😃 😄 😁 😆 😅 😂 🤣 🥲 😊 😇 🙂 🙃 😉 😌 😍 🥰 😘 😗 😙 😚 😋 😛 😝 😜 🤪 🤨 🧐 🤓 😎 🤩 🥳 😏 😒 😞 😔 😟 😕 🙁 ☹️ 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😱 😨 😰 😥 😓 🤗 🤔 🤭 🤫 🤥 😶 😐 😑 😬 🙄 😯 😦 😧 😮 😲 🥱 😴 🤤 😪 😵 🤐 🥴 🤢 🤮 🤧 😷 🤒 🤕 🤑 🤠 😈 👿 👹 👺 🤡 💩 👻 💀 👽 🤖',
  '👍': '👍 👎 👌 🤌 🤏 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ ✋ 🤚 🖐️ 🖖 👋 🤝 🙏 ✍️ 💅 🤳 💪 🦾 🙌 👏 🤲 👐 🫶 🫡 🫰 👀 👁️ 👅 👄 🧠 🦷 👂 👃',
  '❤️': '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ☮️ ✝️ ☪️ 🕉️ ☸️ ✡️ 🔯 🕎 ☯️ ♈ ♉ ♊ ♋ ♌ ♍ ♎ ♏ ♐ ♑ ♒ ♓ 💯 ✅ ❌ ❓ ❗ ⚠️ 🔥 ✨ ⭐ 🌟 💫 ⚡ 💥 💢 💦 💨 🎉 🎊',
  '🐶': '🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🙈 🙉 🙊 🐔 🐧 🐦 🐤 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🐛 🦋 🐌 🐞 🐜 🐢 🐍 🦎 🐙 🦑 🦐 🦀 🐠 🐟 🐬 🐳 🐋 🦈 🐊 🐅 🐆 🦓 🦍 🐘 🦛 🐪 🐫 🦒 🦘 🐃 🐂 🐄 🐎 🐖 🐏 🐑 🐐 🦌 🐕 🐩 🐈 🐓 🦃 🕊️ 🐇 🐁 🐀 🌵 🌲 🌳 🌴 🌱 🌿 🍀 🍁 🍂 🍃 🌺 🌻 🌹 🌷 🌼 🌸',
  '🍕': '🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥒 🌶️ 🌽 🥕 🥔 🍞 🥐 🥖 🧀 🥚 🍳 🥞 🥓 🍔 🍟 🍕 🌭 🥪 🌮 🌯 🥗 🍝 🍜 🍲 🍛 🍣 🍱 🥟 🍤 🍙 🍚 🍘 🍥 🍦 🍧 🍨 🍩 🍪 🎂 🍰 🧁 🍫 🍬 🍭 🍮 ☕ 🍵 🥛 🍼 🍺 🍻 🥂 🍷 🥃 🍸 🍹 🥤',
  '⚽': '⚽ 🏀 🏈 ⚾ 🎾 🏐 🏉 🎱 🏓 🏸 🥅 🏏 ⛳ 🏹 🎣 🥊 🥋 ⛸️ 🎿 🏂 🏆 🥇 🥈 🥉 🎖️ 🎯 🎮 🎲 🧩 🎭 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🎷 🎺 🎸 🎻 📱 💻 🖥️ ⌚ 📷 📞 ☎️ 📺 🔋 🔌 💡 🔦 📚 📖 📝 ✏️ 📌 📎 ✂️ 🔒 🔑 💼 💰 💳 🎁 🛒',
  '🚗': '🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚚 🚜 🏍️ 🚲 🛵 ✈️ 🚀 🛸 🚁 ⛵ 🚤 🚢 🚂 🚆 🚇 🏠 🏡 🏢 🏬 🏥 🏦 🏨 🏫 ⛪ 🕌 🛕 🗼 🗽 🌅 🌄 🌇 🌃 🌉 🌍 🌎 🌏 🌙 ☀️ ⛅ ☁️ 🌧️ ⛈️ ❄️ ☃️ 🌈 🌊 🔥 ⛰️ 🏖️ 🏝️',
};

class _EmojiPanel extends StatefulWidget {
  final void Function(String) onPick;
  const _EmojiPanel(this.onPick);
  @override
  State<_EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<_EmojiPanel> {
  String _g = kEmojiGroups.keys.first;
  @override
  Widget build(BuildContext context) {
    final list = kEmojiGroups[_g]!.split(' ').where((e) => e.isNotEmpty).toList();
    return Column(children: [
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 10),
          children: [
            for (final k in kEmojiGroups.keys)
              GestureDetector(
                onTap: () => setState(() => _g = k),
                child: Container(
                  width: 44,
                  margin: EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _g == k ? C.accent.withAlpha(50) : Colors.transparent, borderRadius: BorderRadius.circular(14)),
                  child: Text(k, style: TextStyle(fontSize: 22)),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: GridView.builder(
          padding: EdgeInsets.fromLTRB(10, 4, 10, 10),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, mainAxisSpacing: 2, crossAxisSpacing: 2),
          itemCount: list.length,
          itemBuilder: (_, i) => InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => widget.onPick(list[i]),
            child: Center(child: Text(list[i], style: TextStyle(fontSize: 26))),
          ),
        ),
      ),
    ]);
  }
}

/// Emoji keyboard + sticker packs in one sheet. Emojis go into the message box (the sheet stays open); a sticker is sent at once.
Future<void> showEmojiStickerSheet(BuildContext context, {required void Function(String) onEmoji, required Future<void> Function(Sticker) onSticker, Map? roomPack, bool pc = false}) async {
  StickerStore.refresh(pc: pc);
  // with packs from the CRM the panel opens on Stickers (the CRM packs always come first)
  final first = StickerStore.packs(pc).isNotEmpty ? 1 : 0;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (sheetCtx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(sheetCtx).size.height * .5,
        child: DefaultTabController(
          length: 2,
          initialIndex: first,
          child: Column(children: [
            SizedBox(height: 8),
            Container(width: 42, height: 4, decoration: BoxDecoration(color: C.g3, borderRadius: BorderRadius.circular(4))),
            TabBar(
              labelColor: C.accent,
              unselectedLabelColor: C.muted,
              indicatorColor: C.accent,
              dividerColor: Colors.transparent,
              tabs: [Tab(text: 'Emoji'), Tab(text: 'Stickers')],
            ),
            Expanded(
              child: TabBarView(children: [
                _EmojiPanel(onEmoji),
                _StickerSheet(roomPack: roomPack, pc: pc, onPick: (st) async {
                  Navigator.pop(sheetCtx);
                  await onSticker(st);
                }),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
}
