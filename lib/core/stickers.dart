import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
class StickerStore {
  static final Map<bool, List<StickerPack>> _packs = {false: _read(Session.getString('stk_packs')), true: _read(Session.getString('stk_packs_pc'))};
  static final Map<bool, DateTime> _at = {};

  static List<StickerPack> packs(bool pc) => _packs[pc] ?? const [];

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
    } catch (_) {}
  }

  static Future<File> file(int id) async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/stickers');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/$id.stk');
  }

  static final Map<int, Future<File?>> _loading = {};

  /// The file of a sticker: from the phone if it was loaded before, else from the server (and then kept).
  static Future<File?> load(int id, {bool pc = false}) => _loading[id] ??= _load(id, pc).whenComplete(() => _loading.remove(id));

  static Future<File?> _load(int id, bool pc) async {
    try {
      final f = await file(id);
      if (await f.exists() && await f.length() > 0) return f;
      final b = await (pc && PcApi.token != null ? PcApi.bytes(PcApi.room('x/sticker/$id')) : Api.bytes('sticker/$id'));
      if (b == null || b.isEmpty) return null;
      await f.writeAsBytes(b, flush: true);
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
    return AuthImage(cacheKey: 'stk$id', loader: () => StickerStore.bytes(id, pc: pc), width: size, height: size, fit: BoxFit.contain);
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
      final j = Uint8List.fromList(gzip.decode(b));
      if (_json.length > 120) _json.remove(_json.keys.first);
      _json[widget.id] = j;
      setState(() => _data = j);
    } catch (_) {
      setState(() => _failed = true);
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
    try {
      final c = VideoPlayerController.file(f, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      await c.initialize();
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

List<StickerPack> _allPacks(Map? roomPack, bool pc) => [
      ...kStickerPacks,
      ...StickerStore.packs(pc),
      if (roomPack != null && roomPack.isNotEmpty)
        for (final e in roomPack.entries) StickerPack(e.key.toString(), '⭐', [for (final x in (e.value as List)) Sticker(x.toString())]),
    ];

/// Sticker keyboard. Returns the chosen sticker (or null).
Future<Sticker?> pickSticker(BuildContext context, {Map? roomPack, bool pc = false}) async {
  await StickerStore.refresh(pc: pc);
  if (!context.mounted) return null;
  final packs = _allPacks(roomPack, pc);
  return showModalBottomSheet<Sticker>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _StickerSheet(packs, pc: pc),
  );
}

class _StickerSheet extends StatefulWidget {
  final List<StickerPack> packs;
  final void Function(Sticker)? onPick;
  final bool pc;
  const _StickerSheet(this.packs, {this.onPick, this.pc = false});
  @override
  State<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<_StickerSheet> {
  int _i = 0;
  @override
  Widget build(BuildContext context) {
    final pack = widget.packs[_i.clamp(0, widget.packs.length - 1)];
    return SafeArea(
      child: SizedBox(
        height: widget.onPick != null ? null : MediaQuery.of(context).size.height * .55,
        child: Column(children: [
          SizedBox(height: widget.onPick != null ? 6 : 10),
          if (widget.onPick == null) Container(width: 42, height: 4, decoration: BoxDecoration(color: C.g3, borderRadius: BorderRadius.circular(4))),
          SizedBox(height: widget.onPick != null ? 4 : 12),
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 14),
              itemCount: widget.packs.length,
              separatorBuilder: (_, __) => SizedBox(width: 8),
              itemBuilder: (_, k) {
                final sel = k == _i;
                return GestureDetector(
                  onTap: () => setState(() => _i = k),
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 180),
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: sel ? C.accent.withAlpha(46) : C.g1, borderRadius: BorderRadius.circular(22), border: Border.all(color: sel ? C.accent : C.line, width: sel ? 1.6 : 1)),
                    child: Row(children: [Text(widget.packs[k].icon, style: TextStyle(fontSize: 18)), SizedBox(width: 6), Text(widget.packs[k].name, style: TextStyle(fontWeight: sel ? FontWeight.w800 : FontWeight.w600, color: C.text))]),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.all(14),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .95),
              itemCount: pack.items.length,
              itemBuilder: (_, k) {
                final s = pack.items[k];
                return GestureDetector(
                  onTap: () => widget.onPick != null ? widget.onPick!(s) : Navigator.pop(context, s),
                  child: Container(
                    decoration: BoxDecoration(color: C.g1, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
                    child: s.isImage
                        ? Padding(padding: EdgeInsets.all(6), child: StickerImage(s.id, kind: s.kind, pc: widget.pc, size: 100))
                        : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(s.e, style: TextStyle(fontSize: 38)),
                      if (s.cap.isNotEmpty) Padding(padding: EdgeInsets.only(top: 4), child: Text(s.cap, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: C.muted))),
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
  await StickerStore.refresh(pc: pc);
  if (!context.mounted) return;
  final packs = _allPacks(roomPack, pc);
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
                _StickerSheet(packs, pc: pc, onPick: (st) async {
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
