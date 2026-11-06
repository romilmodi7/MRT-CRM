import 'package:flutter/material.dart';

import 'theme.dart';

/// One sticker = a big emoji with an optional short caption.
class Sticker {
  final String e;
  final String cap;
  const Sticker(this.e, [this.cap = '']);
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

  static String encode(Sticker s) => '$_m${s.e}${s.cap.isEmpty ? '' : '$_m${s.cap}'}';

  static Sticker? parse(String? t) {
    if (t == null || !t.startsWith(_m)) return null;
    final p = t.substring(1).split(_m);
    if (p.isEmpty || p[0].isEmpty || p[0].length > 16) return null;
    return Sticker(p[0], p.length > 1 ? p.sublist(1).join(' ') : '');
  }
}

/// How a sticker looks inside the chat.
class StickerView extends StatelessWidget {
  final Sticker s;
  final bool mine;
  const StickerView(this.s, {super.key, this.mine = false});
  @override
  Widget build(BuildContext context) {
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

/// Sticker keyboard. Returns the chosen sticker (or null).
Future<Sticker?> pickSticker(BuildContext context, {Map? roomPack}) {
  final packs = [
    ...kStickerPacks,
    if (roomPack != null && roomPack.isNotEmpty)
      for (final e in roomPack.entries)
        StickerPack(e.key.toString(), '⭐', [for (final x in (e.value as List)) Sticker(x.toString())]),
  ];
  return showModalBottomSheet<Sticker>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _StickerSheet(packs),
  );
}

class _StickerSheet extends StatefulWidget {
  final List<StickerPack> packs;
  const _StickerSheet(this.packs);
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
        height: MediaQuery.of(context).size.height * .55,
        child: Column(children: [
          SizedBox(height: 10),
          Container(width: 42, height: 4, decoration: BoxDecoration(color: C.g3, borderRadius: BorderRadius.circular(4))),
          SizedBox(height: 12),
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
                  onTap: () => Navigator.pop(context, s),
                  child: Container(
                    decoration: BoxDecoration(color: C.g1, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
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
