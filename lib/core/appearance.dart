import 'package:flutter/material.dart';

import 'theme.dart';

/// Appearance: Light / Dark / Auto, colour theme, and the colours of sent / received chat bubbles.
/// Used from both the employee chat and the private chat.
Future<void> showAppearanceSheet(BuildContext context, {VoidCallback? onChanged}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card2,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .92),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _AppearanceSheet(onChanged),
  );
}

class _AppearanceSheet extends StatefulWidget {
  final VoidCallback? onChanged;
  _AppearanceSheet(this.onChanged);
  @override
  State<_AppearanceSheet> createState() => _AppearanceSheetState();
}

class _AppearanceSheetState extends State<_AppearanceSheet> {
  void _changed() {
    widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  Widget _title(String t, [String? sub]) => Padding(
        padding: EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: C.text)),
          if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: C.muted)),
        ]),
      );

  Widget _opt(ThemeMode m, String label, IconData icon, Color a, Color b) {
    final sel = ThemeCtl.mode == m;
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          await ThemeCtl.set(m);
          _changed();
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: EdgeInsets.symmetric(horizontal: 5),
          padding: EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? C.accent.withAlpha(36) : C.g1,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? C.accent : C.line, width: sel ? 2 : 1),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 50,
              height: 62,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight), border: Border.all(color: C.line)),
              child: Icon(icon, color: m == ThemeMode.light ? Color(0xFF4F46E5) : Colors.white, size: 24),
            ),
            SizedBox(height: 8),
            Text(label, style: TextStyle(fontWeight: sel ? FontWeight.w800 : FontWeight.w500, color: C.text)),
          ]),
        ),
      ),
    );
  }

  Widget _dot(Widget fill, bool sel, VoidCallback onTap, {String? tip}) => Tooltip(
        message: tip ?? '',
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Duration(milliseconds: 180),
            width: 46,
            height: 46,
            padding: EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: sel ? C.accent : Colors.transparent, width: 2.4)),
            child: ClipOval(child: Stack(fit: StackFit.expand, children: [fill, if (sel) Center(child: Icon(Icons.check_rounded, color: Colors.white, size: 22, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]))])),
          ),
        ),
      );

  Widget _grad(int a, int b) => DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(a), Color(b)], begin: Alignment.topLeft, end: Alignment.bottomRight)));

  Widget _auto(IconData i) => DecoratedBox(decoration: BoxDecoration(color: C.g3), child: Icon(i, size: 20, color: C.text));

  @override
  Widget build(BuildContext context) {
    final acc = ThemeCtl.accentPair;
    final mine = ThemeCtl.minePair;
    final their = ThemeCtl.theirColor;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(14, 18, 14, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Text('Appearance', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          SizedBox(height: 14),
          Row(children: [
            _opt(ThemeMode.light, 'Light', Icons.light_mode_rounded, Color(0xFFFFFFFF), Color(0xFFE8EEFB)),
            _opt(ThemeMode.dark, 'Dark', Icons.dark_mode_rounded, Color(0xFF0A1030), Color(0xFF1B1450)),
            _opt(ThemeMode.system, 'Auto', Icons.brightness_auto_rounded, Color(0xFF6D5BFF), Color(0xFF22D3EE)),
          ]),
          _title('Colour theme', 'Buttons, highlights and icons'),
          Wrap(spacing: 4, runSpacing: 4, children: [
            _dot(_auto(Icons.restart_alt_rounded), acc == null, () async { await ThemeCtl.setAccent(null); _changed(); }, tip: 'Standard'),
            for (final a in kAccents)
              _dot(_grad(a[1] as int, a[2] as int), acc != null && acc[0] == a[1], () async { await ThemeCtl.setAccent([a[1] as int, a[2] as int]); _changed(); }, tip: a[0] as String),
          ]),
          _title('Sender bubble', 'Messages you send'),
          Wrap(spacing: 4, runSpacing: 4, children: [
            _dot(_auto(Icons.restart_alt_rounded), mine == null, () async { await ThemeCtl.setMine(null); _changed(); }, tip: 'Standard'),
            for (final a in kMineBubbles)
              _dot(_grad(a[1] as int, a[2] as int), mine != null && mine[0] == a[1], () async { await ThemeCtl.setMine([a[1] as int, a[2] as int]); _changed(); }, tip: a[0] as String),
          ]),
          _title('Receiver bubble', 'Messages you receive'),
          Wrap(spacing: 4, runSpacing: 4, children: [
            _dot(_auto(Icons.restart_alt_rounded), their == null, () async { await ThemeCtl.setTheirs(null); _changed(); }, tip: 'Standard'),
            for (final a in kTheirBubbles)
              _dot(DecoratedBox(decoration: BoxDecoration(color: Color(a[1] as int), border: Border.all(color: C.line), shape: BoxShape.circle)), their == a[1], () async { await ThemeCtl.setTheirs(a[1] as int); _changed(); }, tip: a[0] as String),
          ]),
          _title('Preview'),
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(color: C.g1, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.line)),
            child: Column(children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(color: CB.theirBg ?? (C.dark ? C.g3 : Colors.white), border: C.dark ? null : Border.all(color: C.line), borderRadius: BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomRight: Radius.circular(18), bottomLeft: Radius.circular(5))),
                  child: Text('Good morning! Is the report ready?', style: TextStyle(color: CB.theirFg)),
                ),
              ),
              SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(gradient: C.gradMe, borderRadius: BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(5))),
                  child: Text('Yes, sending it now 👍', style: TextStyle(color: Colors.white)),
                ),
              ),
            ]),
          ),
          SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              onPressed: () async {
                await ThemeCtl.resetColors();
                _changed();
              },
              icon: Icon(Icons.restart_alt_rounded, size: 18),
              label: Text('Reset all colours'),
            ),
          ),
        ]),
      ),
    );
  }
}
