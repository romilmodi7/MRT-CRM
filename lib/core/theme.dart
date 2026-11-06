import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'session.dart';

class C {
  /// true = dark palette, false = light (white, professional) palette.
  static bool dark = true;
  static Color _p(int d, int l) => Color(dark ? d : l);

  static Color get bg => _p(0xFF070A1C, 0xFFF4F6FB);
  static Color get bg2 => _p(0xFF0B1030, 0xFFFFFFFF);
  static Color get card => _p(0xFF141A44, 0xFFFFFFFF);
  static Color get card2 => _p(0xFF1B2257, 0xFFFFFFFF);
  static Color get stroke => _p(0xFF2A3170, 0xFFE3E7F1);
  static Color get accent => ThemeCtl.accentPair != null ? Color(ThemeCtl.accentPair![0]) : _p(0xFF7C6CFF, 0xFF4F46E5);
  static Color get accent2 => ThemeCtl.accentPair != null ? Color(ThemeCtl.accentPair![1]) : _p(0xFF22D3EE, 0xFF2563EB);
  static Color get rose => _p(0xFFFF5FA8, 0xFFDB2777);
  static Color get text => _p(0xFFEEF0FF, 0xFF111827);
  static Color get sub => _p(0xB3FFFFFF, 0xFF4B5563);
  static Color get muted => _p(0xFF9AA1C9, 0xFF6B7280);
  static Color get hint => _p(0xFF7F87B5, 0xFF9CA3AF);
  static Color get danger => _p(0xFFFF5D6C, 0xFFDC2626);
  static Color get success => _p(0xFF36E0A6, 0xFF16A34A);
  // translucent surfaces
  static Color get g1 => _p(0x14FFFFFF, 0xFFFFFFFF);
  static Color get g2 => _p(0x22FFFFFF, 0xFFEBEEF6);
  static Color get g3 => _p(0x33FFFFFF, 0xFFDDE2EF);
  static Color get line => _p(0x1FFFFFFF, 0xFFE3E7F1);
  static Color get bar => _p(0x33000000, 0xFFFFFFFF);
  static LinearGradient get grad => ThemeCtl.accentPair != null
      ? LinearGradient(colors: [accent, accent2], begin: Alignment.topLeft, end: Alignment.bottomRight)
      : dark
      ? LinearGradient(colors: [Color(0xFF7C6CFF), Color(0xFF22D3EE)], begin: Alignment.topLeft, end: Alignment.bottomRight)
      : LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF4F46E5)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  /// Colour of the bubbles you send (sender): your own choice, else follows the colour theme.
  static LinearGradient get gradMe => ThemeCtl.minePair != null
      ? LinearGradient(colors: [Color(ThemeCtl.minePair![0]), Color(ThemeCtl.minePair![1])], begin: Alignment.topLeft, end: Alignment.bottomRight)
      : ThemeCtl.accentPair != null
      ? LinearGradient(colors: [accent, accent2], begin: Alignment.topLeft, end: Alignment.bottomRight)
      : dark
      ? LinearGradient(colors: [Color(0xFF6D5BFF), Color(0xFF4F7CFF)], begin: Alignment.topLeft, end: Alignment.bottomRight)
      : LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF4F46E5)], begin: Alignment.topLeft, end: Alignment.bottomRight);
}

class CB {
  /// background of received bubbles, null = use the standard one
  static Color? get theirBg => ThemeCtl.theirColor == null ? null : Color(ThemeCtl.theirColor!);
  /// text colour that stays readable on a received bubble
  static Color get theirFg => theirBg == null ? C.text : (theirBg!.computeLuminance() > .5 ? Color(0xFF111827) : Colors.white);
  static Color get theirMeta => theirBg == null ? C.muted : theirFg.withAlpha(170);
}

/// Ready-made colour themes (accent pair), sender and receiver bubble colours.
const List<List<Object>> kAccents = [
  ['Violet', 0xFF7C6CFF, 0xFF22D3EE],
  ['Ocean', 0xFF2563EB, 0xFF06B6D4],
  ['Emerald', 0xFF059669, 0xFF34D399],
  ['Sunset', 0xFFF97316, 0xFFEC4899],
  ['Rose', 0xFFE11D48, 0xFFFB7185],
  ['Gold', 0xFFD97706, 0xFFFBBF24],
  ['Indigo', 0xFF4338CA, 0xFF818CF8],
  ['Teal', 0xFF0F766E, 0xFF2DD4BF],
  ['Graphite', 0xFF374151, 0xFF6B7280],
];
const List<List<Object>> kMineBubbles = [
  ['Blue', 0xFF2563EB, 0xFF4F46E5],
  ['Violet', 0xFF6D5BFF, 0xFF4F7CFF],
  ['Green', 0xFF059669, 0xFF10B981],
  ['Orange', 0xFFEA580C, 0xFFF97316],
  ['Pink', 0xFFDB2777, 0xFFE879F9],
  ['Red', 0xFFDC2626, 0xFFEF4444],
  ['Teal', 0xFF0F766E, 0xFF14B8A6],
  ['Dark', 0xFF1F2937, 0xFF374151],
];
const List<List<Object>> kTheirBubbles = [
  ['White', 0xFFFFFFFF],
  ['Grey', 0xFFE5E7EB],
  ['Sky', 0xFFDBEAFE],
  ['Mint', 0xFFD1FAE5],
  ['Peach', 0xFFFFE4D6],
  ['Lilac', 0xFFEDE9FE],
  ['Slate', 0xFF334155],
  ['Navy', 0xFF1E3A8A],
  ['Plum', 0xFF581C87],
];

/// App appearance: system / light / dark + colour theme + bubble colours. Saved on the phone.
class ThemeCtl {
  static List<int>? accentPair;   // null = standard colours
  static List<int>? minePair;     // sender bubble
  static int? theirColor;         // receiver bubble

  static List<int>? _pair(String? v) {
    if (v == null || v.isEmpty) return null;
    final p = v.split(',').map(int.tryParse).toList();
    return p.length == 2 && p[0] != null && p[1] != null ? [p[0]!, p[1]!] : null;
  }

  static Future<void> setAccent(List<int>? p) async {
    accentPair = p;
    await Session.setString('th_accent', p == null ? '' : '${p[0]},${p[1]}');
    refresh();
  }

  static Future<void> setMine(List<int>? p) async {
    minePair = p;
    await Session.setString('th_mine', p == null ? '' : '${p[0]},${p[1]}');
    refresh();
  }

  static Future<void> setTheirs(int? c) async {
    theirColor = c;
    await Session.setString('th_their', c == null ? '' : '$c');
    refresh();
  }

  static Future<void> resetColors() async {
    accentPair = null;
    minePair = null;
    theirColor = null;
    await Session.setString('th_accent', '');
    await Session.setString('th_mine', '');
    await Session.setString('th_their', '');
    refresh();
  }

  /// repaint everything after a colour change
  static void refresh() {
    tick.value++;
    rebuildAll();
  }

  static ThemeMode mode = ThemeMode.system;
  static final ValueNotifier<int> tick = ValueNotifier(0);

  static void load() {
    final v = Session.getString('theme_mode');
    mode = v == 'light' ? ThemeMode.light : v == 'dark' ? ThemeMode.dark : ThemeMode.system;
    accentPair = _pair(Session.getString('th_accent'));
    minePair = _pair(Session.getString('th_mine'));
    theirColor = int.tryParse(Session.getString('th_their') ?? '');
  }

  static bool resolve(Brightness system) => mode == ThemeMode.system ? system == Brightness.dark : mode == ThemeMode.dark;

  static Future<void> set(ThemeMode m) async {
    mode = m;
    await Session.setString('theme_mode', m == ThemeMode.light ? 'light' : m == ThemeMode.dark ? 'dark' : 'system');
    apply(WidgetsBinding.instance.platformDispatcher.platformBrightness);
  }

  /// Switch palette and rebuild everything that is on screen.
  static void apply(Brightness system) {
    final d = resolve(system);
    final changed = C.dark != d;
    C.dark = d;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: d ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: d ? Color(0xFF0A1030) : Colors.white,
      systemNavigationBarIconBrightness: d ? Brightness.light : Brightness.dark,
    ));
    tick.value++;
    if (changed) rebuildAll();
  }

  static void rebuildAll() {
    void v(Element e) {
      e.markNeedsBuild();
      e.visitChildren(v);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(v);
  }
}

ThemeData appTheme() {
  final base = C.dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  final scheme = C.dark
      ? ColorScheme.dark(primary: C.accent, secondary: C.accent2, surface: C.card, error: C.danger)
      : ColorScheme.light(primary: C.accent, secondary: C.accent2, surface: C.card, error: C.danger);
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: scheme,
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
    appBarTheme: AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, centerTitle: false, foregroundColor: C.text),
    iconTheme: IconThemeData(color: C.text),
    dividerColor: C.line,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.dark ? C.card2 : Color(0xFF1F2937),
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.dark ? Color(0x14FFFFFF) : Colors.white,
      hintStyle: TextStyle(color: C.hint),
      contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: C.dark ? BorderSide.none : BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: C.accent, width: 1.4)),
    ),
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
    }),
  );
}

/// Night-blue aurora behind every screen.
class Aurora extends StatelessWidget {
  final Widget child;
  const Aurora({super.key, required this.child});

  Widget _glow(Color c, double size, {double? top, double? left, double? right, double? bottom}) => Positioned(
        top: top, left: left, right: right, bottom: bottom,
        child: IgnorePointer(
          child: Container(
            width: size, height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c, c.withAlpha(0)])),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(colors: C.dark ? [Color(0xFF070A1C), Color(0xFF0A1030), Color(0xFF06182A)] : [Color(0xFFF7F8FD), Color(0xFFEFF2FA), Color(0xFFE8EEFB)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        ),
      ),
      _glow(C.dark ? Color(0x667C6CFF) : Color(0x334F46E5), 460, top: -170, left: -150),
      _glow(C.dark ? Color(0x5522D3EE) : Color(0x262563EB), 480, bottom: -190, right: -170),
      _glow(C.dark ? Color(0x33FF5FA8) : Color(0x1ADB2777), 300, top: 220, right: -150),
      Positioned.fill(child: child),
    ]);
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.radius = 22, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: C.g1,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: C.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class GradientButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final IconData? icon;
  const GradientButton({super.key, required this.label, this.onTap, this.busy = false, this.icon});
  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.busy;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: enabled ? widget.onTap : null,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: Duration(milliseconds: 110),
        child: Opacity(
          opacity: enabled ? 1 : 0.6,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: C.grad,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: Color(0x557C6CFF), blurRadius: 22, offset: Offset(0, 8))],
            ),
            child: widget.busy
                ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (widget.icon != null) ...[Icon(widget.icon, color: Colors.white, size: 20), SizedBox(width: 8)],
                    Text(widget.label, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: .3)),
                  ]),
          ),
        ),
      ),
    );
  }
}

/// Round avatar with the person's initials and a colour made from the name.
class Avatar extends StatelessWidget {
  final String name;
  final double size;
  const Avatar(this.name, {super.key, this.size = 48});

  static const _pairs = [
    [Color(0xFF7C6CFF), Color(0xFF4F7CFF)], [Color(0xFF22D3EE), Color(0xFF3B82F6)], [Color(0xFFFF5FA8), Color(0xFFFF8A5F)],
    [Color(0xFF36E0A6), Color(0xFF22D3EE)], [Color(0xFFFFB347), Color(0xFFFF5F6D)], [Color(0xFFB06CFF), Color(0xFFFF5FA8)],
  ];

  @override
  Widget build(BuildContext context) {
    final n = name.trim();
    final init = n.isEmpty ? '?' : n.split(RegExp(r'\s+')).take(2).map((w) => w.characters.first.toUpperCase()).join();
    final pair = _pairs[(n.isEmpty ? 0 : n.codeUnits.fold<int>(0, (a, b) => a + b)) % _pairs.length];
    return Container(
      width: size, height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: pair, begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Text(init, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * .36)),
    );
  }
}

/// Fades + slides a list row in (staggered by index).
class Entrance extends StatelessWidget {
  final int index;
  final Widget child;
  const Entrance({super.key, required this.index, required this.child});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + (index > 8 ? 8 : index) * 45),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 22 * (1 - v)), child: c)),
      child: child,
    );
  }
}

void toast(BuildContext c, String m) {
  if (!c.mounted) return;
  ScaffoldMessenger.of(c).hideCurrentSnackBar();
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m), duration: Duration(seconds: 3)));
}
