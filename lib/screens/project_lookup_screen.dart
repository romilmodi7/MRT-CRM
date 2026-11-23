import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/platform.dart';
import '../core/theme.dart';
import 'project_share_screen.dart' show lvBadge, lvColor;

/// ₹1,25,000 (Indian grouping, no paise unless there are any)
String inr(num? v) {
  final n = (v ?? 0).toDouble();
  final neg = n < 0;
  final a = n.abs();
  final whole = a.truncate();
  final paise = ((a - whole) * 100).round();
  var s = whole.toString();
  if (s.length > 3) {
    final last = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    s = '${parts.join(',')},$last';
  }
  return '${neg ? '-' : ''}₹$s${paise > 0 ? '.${paise.toString().padLeft(2, '0')}' : ''}';
}

BoxDecoration _deco({Color? edge, double r = 18}) => BoxDecoration(
      color: C.dark ? C.g1 : Colors.white,
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: edge ?? C.line),
      boxShadow: C.dark ? null : [BoxShadow(color: Color(0x10111827), blurRadius: 14, offset: Offset(0, 6))],
    );

Widget _chip(String t, {Color? fg, Color? bg}) => Container(
      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg ?? C.g2, borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg ?? C.sub)),
    );

Color _stateColor(String k) => switch (k) {
      'done' => C.success,
      'delayed' => C.danger,
      'hold' => Color(0xFFF59E0B),
      _ => C.accent2,
    };

Widget _empty(String t, {IconData icon = Icons.inbox_rounded}) => Padding(
      padding: EdgeInsets.symmetric(vertical: 44),
      child: Center(child: Column(children: [Icon(icon, size: 42, color: C.hint), SizedBox(height: 8), Text(t, textAlign: TextAlign.center, style: TextStyle(color: C.muted))])),
    );

/* =====================================================================
 |  1. Search: type a project name, code or client
 * ===================================================================== */
class ProjectLookupScreen extends StatefulWidget {
  const ProjectLookupScreen({super.key});
  @override
  State<ProjectLookupScreen> createState() => _ProjectLookupScreenState();
}

class _ProjectLookupScreenState extends State<ProjectLookupScreen> {
  final _q = TextEditingController();
  Timer? _deb;
  List<Map> _rows = [];
  bool _loading = true;
  String _err = '';
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _deb?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onType(String v) {
    _deb?.cancel();
    _deb = Timer(Duration(milliseconds: 350), () => _search(v.trim()));
    setState(() {});
  }

  Future<void> _search(String q) async {
    final my = ++_seq;
    setState(() => _loading = true);
    final r = await Api.get('project-lookup?q=${Uri.encodeQueryComponent(q)}');
    if (!mounted || my != _seq) return; // an older answer arriving late
    setState(() {
      _loading = false;
      if (r.ok && r.data is List) {
        _rows = (r.data as List).whereType<Map>().toList();
        _err = '';
      } else {
        _rows = [];
        _err = r.msg;
      }
    });
  }

  Widget _card(Map p) {
    final state = (p['state'] ?? '').toString();
    final sc = _stateColor(state);
    final prog = ((p['progress'] as num?) ?? 0).clamp(0, 100).toDouble();
    final sub = [p['code'], p['client']].where((e) => e != null && e.toString().isNotEmpty).join(' · ');
    final team = ((p['team'] as List?) ?? []).map((e) => e.toString()).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: _deco(),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              FocusScope.of(context).unfocus();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectFullScreen(id: (p['id'] as num).toInt(), name: (p['name'] ?? '').toString())));
            },
            child: Padding(
              padding: EdgeInsets.all(13),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    child: Icon(Icons.folder_special_rounded, color: Colors.white, size: 23),
                  ),
                  SizedBox(width: 11),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((p['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: C.text)),
                      if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: C.muted)),
                    ]),
                  ),
                  _chip((p['stateLabel'] ?? '').toString(), fg: sc, bg: sc.withAlpha(30)),
                  Icon(Icons.chevron_right_rounded, color: C.hint),
                ]),
                SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: LinearProgressIndicator(value: prog / 100, minHeight: 6, backgroundColor: C.g2, valueColor: AlwaysStoppedAnimation(sc)),
                    ),
                  ),
                  SizedBox(width: 9),
                  Text('${prog.round()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.sub)),
                  if ((p['due'] ?? '').toString().isNotEmpty) ...[SizedBox(width: 10), Icon(Icons.event_rounded, size: 14, color: C.hint), SizedBox(width: 3), Text(p['due'].toString(), style: TextStyle(fontSize: 12, color: C.muted))],
                  for (final t in team.take(4))
                    Container(
                      margin: EdgeInsets.only(left: 4),
                      width: 22, height: 22,
                      decoration: BoxDecoration(gradient: C.gradMe, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text(t, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Aurora(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, title: Text('Project lookup', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: C.text))),
        body: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _q,
              autofocus: true,
              onChanged: _onType,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => _search(v.trim()),
              style: TextStyle(color: C.text, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Type project name, code or client…',
                prefixIcon: Icon(Icons.search_rounded, color: C.accent2),
                suffixIcon: _q.text.isEmpty ? null : IconButton(icon: Icon(Icons.close_rounded, color: C.hint), onPressed: () { _q.clear(); _search(''); setState(() {}); }),
                filled: true,
                fillColor: C.dark ? C.g1 : Colors.white,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: C.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: C.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: C.accent, width: 1.6)),
              ),
            ),
          ),
          if (_loading) LinearProgressIndicator(minHeight: 2, color: C.accent2, backgroundColor: Colors.transparent),
          Expanded(
            child: _err.isNotEmpty
                ? _empty(_err, icon: Icons.lock_outline_rounded)
                : (!_loading && _rows.isEmpty)
                    ? _empty(_q.text.isEmpty ? 'No projects.' : 'No project matches "${_q.text}".', icon: Icons.search_off_rounded)
                    : ListView.builder(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(16, 6, 16, 30),
                        itemCount: _rows.length,
                        itemBuilder: (_, i) => _card(_rows[i]),
                      ),
          ),
        ]),
      ),
    );
  }
}

/* =====================================================================
 |  2. Everything about one project: one tab per part (+ Payments behind the accounting password)
 * ===================================================================== */
class ProjectFullScreen extends StatefulWidget {
  final int id;
  final String name;
  const ProjectFullScreen({super.key, required this.id, required this.name});
  @override
  State<ProjectFullScreen> createState() => _ProjectFullScreenState();
}

class _ProjectFullScreenState extends State<ProjectFullScreen> {
  Map<String, dynamic>? _d;
  String _err = '';
  bool _loading = true;
  int _tab = 0;
  final Set<String> _shown = {};

  // payments tab
  Map? _money;
  bool _moneyLoading = false, _locked = false, _unlocking = false;
  String _moneyErr = '';
  final _pin = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await Api.get('project-lookup/${widget.id}');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok && r.data is Map) {
        _d = Map<String, dynamic>.from(r.data as Map);
        _err = '';
      } else {
        _err = r.msg;
      }
    });
    if (_money != null || _isMoneyTab) _loadMoney();
  }

  Future<void> _loadMoney() async {
    setState(() { _moneyLoading = true; _moneyErr = ''; });
    final r = await Api.get('project-lookup/${widget.id}/money');
    if (!mounted) return;
    setState(() {
      _moneyLoading = false;
      _locked = r.code == 423 || r.locked;
      if (r.ok && r.data is Map) {
        _money = r.data as Map;
      } else if (!_locked) {
        _moneyErr = r.msg;
      }
    });
  }

  Future<void> _unlock() async {
    final pin = _pin.text.trim();
    if (pin.isEmpty) { toast(context, 'Enter your accounting password'); return; }
    setState(() => _unlocking = true);
    final r = await Api.post('accounting/unlock', {'pin': pin});
    if (!mounted) return;
    setState(() => _unlocking = false);
    if (r.ok) {
      _pin.clear();
      FocusScope.of(context).unfocus();
      _loadMoney();
    } else {
      toast(context, r.msg);
    }
  }

  List<String> get _keys => [...((_d?['keys'] as List?) ?? []).map((e) => e.toString()), 'money'];
  List<String> get _labels => [...((_d?['labels'] as List?) ?? []).map((e) => e.toString()), 'Payments'];
  List<int> get _counts => [...((_d?['counts'] as List?) ?? []).map((e) => (e as num).toInt()), -1];
  bool get _isMoneyTab => _keys.isNotEmpty && _tab == _keys.length - 1;
  Map get _p => (_d?['project'] as Map?) ?? {};

  Future<void> _copy(String v) async {
    await Clipboard.setData(ClipboardData(text: v));
    if (mounted) toast(context, 'Copied');
  }

  String _url(String v) => RegExp(r'^https?://', caseSensitive: false).hasMatch(v) ? v : 'http://$v';

  IconData _icon(String k) => switch (k) {
        'issues' => Icons.bug_report_rounded,
        'solved' => Icons.task_alt_rounded,
        'points' => Icons.push_pin_rounded,
        'care' => Icons.health_and_safety_rounded,
        'plan' => Icons.event_note_rounded,
        'server' => Icons.dns_rounded,
        'ftp' => Icons.cloud_upload_rounded,
        'database' => Icons.storage_rounded,
        'domain' => Icons.language_rounded,
        'client' => Icons.person_rounded,
        'money' => Icons.currency_rupee_rounded,
        _ => Icons.folder_rounded,
      };

  Widget _round(IconData i, VoidCallback onTap) => Padding(
        padding: EdgeInsets.only(left: 6),
        child: Material(
          color: C.g2,
          shape: CircleBorder(),
          child: InkWell(customBorder: CircleBorder(), onTap: onTap, child: SizedBox(width: 36, height: 36, child: Icon(i, size: 18, color: C.sub))),
        ),
      );

  /* ---------- header ---------- */
  Widget _hero() {
    final p = _p;
    final sc = _stateColor((p['state'] ?? '').toString());
    final prog = ((p['progress'] as num?) ?? 0).clamp(0, 100).toDouble();
    final sub = [p['code'], p['client']].where((e) => e != null && e.toString().isNotEmpty).join(' · ');
    final team = ((p['team'] as List?) ?? []).map((e) => e.toString()).toList();
    final mobile = (p['mobile'] ?? '').toString();
    final renew = (p['domainRenewal'] ?? '').toString();
    Widget stat(String v, String l, Color c) => Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: C.dark ? Color(0x22000000) : Color(0xB3FFFFFF), borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text(v, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: c)),
              SizedBox(height: 1),
              Text(l, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.muted)),
            ]),
          ),
        );
    final cn = _counts;
    int count(String k) { final i = _keys.indexOf(k); return i >= 0 && i < cn.length ? cn[i] : 0; }
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [C.accent.withAlpha(C.dark ? 70 : 38), C.accent2.withAlpha(C.dark ? 40 : 22)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: C.accent.withAlpha(C.dark ? 80 : 60)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: C.accent.withAlpha(90), blurRadius: 14, offset: Offset(0, 6))]),
            alignment: Alignment.center,
            child: Icon(Icons.folder_special_rounded, color: Colors.white, size: 26),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((p['name'] ?? widget.name).toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18.5, color: C.text, height: 1.2)),
              if (sub.isNotEmpty) Padding(padding: EdgeInsets.only(top: 2), child: Text(sub, style: TextStyle(color: C.sub, fontSize: 13))),
            ]),
          ),
          _chip((p['stateLabel'] ?? '').toString(), fg: sc, bg: sc.withAlpha(34)),
        ]),
        SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: LinearProgressIndicator(value: prog / 100, minHeight: 7, backgroundColor: C.dark ? Color(0x33000000) : Color(0xB3FFFFFF), valueColor: AlwaysStoppedAnimation(sc)),
            ),
          ),
          SizedBox(width: 10),
          Text('${prog.round()}% issues solved', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.sub)),
        ]),
        SizedBox(height: 12),
        Row(children: [
          stat('${p['openIssues'] ?? 0}', 'Open issues', C.danger),
          SizedBox(width: 8),
          stat('${p['urgent'] ?? 0}', 'High priority', Color(0xFFF59E0B)),
          SizedBox(width: 8),
          stat('${count('solved')}', 'Solved', C.success),
          SizedBox(width: 8),
          stat('${count('points')}', 'Points', C.accent2),
        ]),
        SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if ((p['due'] ?? '').toString().isNotEmpty) _chip('Delivery ${p['due']}'),
          if (renew.isNotEmpty) _chip('Domain renewal $renew'),
          if (mobile.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => openLink('tel:$mobile'),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: C.success.withAlpha(34), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.call_rounded, size: 14, color: C.success), SizedBox(width: 4), Text(mobile, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: C.success))]),
              ),
            ),
        ]),
        if (team.isNotEmpty) ...[
          SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.groups_rounded, size: 17, color: C.sub),
            SizedBox(width: 7),
            Expanded(child: Text(team.join(', '), style: TextStyle(color: C.sub, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.35))),
          ]),
        ],
      ]),
    );
  }

  /* ---------- tabs ---------- */
  Widget _tabs() {
    final keys = _keys, labels = _labels, cn = _counts;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sel = _tab == i;
          final n = i < cn.length ? cn[i] : -1;
          return Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                gradient: sel ? C.grad : null,
                color: sel ? null : (C.dark ? C.g1 : Colors.white),
                borderRadius: BorderRadius.circular(22),
                border: sel ? null : Border.all(color: C.line),
                boxShadow: sel ? [BoxShadow(color: C.accent.withAlpha(80), blurRadius: 12, offset: Offset(0, 4))] : null,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () {
                  setState(() => _tab = i);
                  if (keys[i] == 'money' && _money == null && !_moneyLoading) _loadMoney();
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Row(children: [
                    Icon(_icon(keys[i]), size: 17, color: sel ? Colors.white : C.sub),
                    SizedBox(width: 6),
                    Text(labels[i], style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: sel ? Colors.white : C.text)),
                    if (n > 0) ...[
                      SizedBox(width: 6),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(color: sel ? Color(0x33FFFFFF) : C.g2, borderRadius: BorderRadius.circular(20)),
                        child: Text('$n', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: sel ? Colors.white : C.sub)),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /* ---------- parts ---------- */
  Widget _field(String key, int i, Map f, {required bool last}) {
    final kind = (f['kind'] ?? 'text').toString();
    final v = (f['value'] ?? '').toString();
    final label = (f['label'] ?? '').toString();
    final id = '$key:$i';
    final secret = kind == 'secret';
    final shown = _shown.contains(id);
    final link = kind == 'link' || kind == 'phone';
    return Container(
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: C.line))),
      padding: EdgeInsets.fromLTRB(14, 11, 10, 11),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: TextStyle(color: C.muted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .8)),
            SizedBox(height: 3),
            GestureDetector(
              onTap: link ? () => openLink(kind == 'phone' ? 'tel:$v' : _url(v)) : null,
              onLongPress: () => _copy(v),
              child: Text(secret && !shown ? '••••••••••' : (v.isEmpty ? '—' : v),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.3, letterSpacing: secret && !shown ? 2 : 0, color: link ? (C.dark ? C.accent2 : C.accent) : C.text)),
            ),
          ]),
        ),
        if (secret) _round(shown ? Icons.visibility_off_rounded : Icons.visibility_rounded, () => setState(() => shown ? _shown.remove(id) : _shown.add(id))),
        if (link && v.isNotEmpty) _round(kind == 'phone' ? Icons.call_rounded : Icons.open_in_new_rounded, () => openLink(kind == 'phone' ? 'tel:$v' : _url(v))),
        _round(Icons.copy_rounded, () => _copy(v)),
      ]),
    );
  }

  Widget _item(Map r, {bool solved = false}) {
    final lv = (r['level'] is num) ? (r['level'] as num).toInt() : -1;
    final chips = [r['priority'], (r['due'] ?? '').toString().isEmpty ? null : 'Due ${r['due']}', r['state'], r['category']].where((e) => e != null && e.toString().isNotEmpty).map((e) => e.toString()).toList();
    final team = ((r['team'] as List?) ?? []).map((e) => e.toString()).toList();
    final text = (r['text'] ?? '').toString();
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      decoration: _deco(),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: solved ? C.success : (lvColor(lv) ?? C.accent.withAlpha(120))),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(13),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (solved) Padding(padding: EdgeInsets.only(right: 6, top: 1), child: Icon(Icons.check_circle_rounded, size: 18, color: C.success)),
                  Expanded(child: Text((r['title'] ?? '').toString(), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: C.text))),
                ]),
                if (chips.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final c in chips)
                        (lv >= 0 && !solved && c == (r['priority'] ?? '').toString())
                            ? lvBadge(lv)
                            : (solved && c.startsWith('Solved') ? _chip(c, fg: C.success, bg: C.success.withAlpha(30)) : _chip(c)),
                    ]),
                  ),
                if (text.isNotEmpty) Padding(padding: EdgeInsets.only(top: 8), child: Text(text, maxLines: 8, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.sub, fontSize: 13.5, height: 1.4))),
                if (team.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Icon(solved ? Icons.verified_user_rounded : Icons.groups_rounded, size: 16, color: C.muted),
                      SizedBox(width: 6),
                      Expanded(child: Text((solved ? 'Solved by ' : '') + team.join(', '), style: TextStyle(color: C.muted, fontSize: 12.5))),
                    ]),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _plan(Map r) {
    final text = (r['text'] ?? '').toString();
    final file = r['file'] is Map ? r['file'] as Map : null;
    final imgs = ((r['images'] as List?) ?? []).map((e) => e.toString()).toList();
    final head = [(r['date'] ?? '').toString(), (r['time'] ?? '').toString()].where((e) => e.isNotEmpty).join(' · ');
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(13),
      decoration: _deco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.event_rounded, size: 17, color: C.accent2), SizedBox(width: 7), Expanded(child: Text(head, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: C.text)))]),
        if (text.isNotEmpty) Padding(padding: EdgeInsets.only(top: 8), child: Text(text, style: TextStyle(color: C.sub, fontSize: 13.5, height: 1.4))),
        if (file != null)
          Padding(
            padding: EdgeInsets.only(top: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => openLink(file['url'].toString()),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                decoration: BoxDecoration(color: C.g2, borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.attach_file_rounded, size: 17, color: C.accent2),
                  SizedBox(width: 6),
                  Flexible(child: Text('${file['name']}', overflow: TextOverflow.ellipsis, style: TextStyle(color: C.text, fontWeight: FontWeight.w700, fontSize: 13))),
                ]),
              ),
            ),
          ),
        if (imgs.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final u in imgs)
                GestureDetector(
                  onTap: () => openLink(u),
                  child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(u, width: 92, height: 92, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 92, height: 92, color: C.g2))),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _pane() {
    final keys = _keys;
    final k = keys[_tab.clamp(0, keys.length - 1)];
    if (k == 'money') return _moneyPane();
    final rows = (((_d?['data'] as Map?)?[k] as List?) ?? []).whereType<Map>().toList();
    if (rows.isEmpty) {
      return _empty(switch (k) {
        'issues' => 'No pending issue 🎉',
        'solved' => 'No solved issue yet.',
        'points' => 'No pending point.',
        'care' => 'No take-care point.',
        'plan' => 'No plan added.',
        _ => 'Nothing added here.',
      });
    }
    if (k == 'plan') return Column(children: [for (final r in rows) _plan(r)]);
    if (k == 'issues' || k == 'points' || k == 'care' || k == 'solved') return Column(children: [for (final r in rows) _item(r, solved: k == 'solved')]);
    return Container(
      decoration: _deco(),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [for (var i = 0; i < rows.length; i++) _field(k, i, rows[i], last: i == rows.length - 1)]),
    );
  }

  /* ---------- payments ---------- */
  Widget _section(String t, IconData i, [int? n]) => Padding(
        padding: EdgeInsets.fromLTRB(2, 18, 2, 10),
        child: Row(children: [
          Icon(i, size: 18, color: C.accent2),
          SizedBox(width: 7),
          Text(t, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5, color: C.text)),
          if (n != null) ...[SizedBox(width: 7), _chip('$n')],
        ]),
      );

  Widget _lockCard() => Container(
        padding: EdgeInsets.all(18),
        decoration: _deco(edge: C.accent.withAlpha(90)),
        child: Column(children: [
          Container(
            width: 58, height: 58,
            decoration: BoxDecoration(gradient: C.grad, shape: BoxShape.circle, boxShadow: [BoxShadow(color: C.accent.withAlpha(90), blurRadius: 16, offset: Offset(0, 6))]),
            child: Icon(Icons.lock_rounded, color: Colors.white, size: 28),
          ),
          SizedBox(height: 12),
          Text('Amounts are locked', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: C.text)),
          SizedBox(height: 4),
          Text('Enter your accounting password to see payments, commitments and commission.', textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 13, height: 1.4)),
          SizedBox(height: 14),
          TextField(
            controller: _pin,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            onSubmitted: (_) => _unlock(),
            style: TextStyle(color: C.text, fontWeight: FontWeight.w700, letterSpacing: 2),
            decoration: InputDecoration(
              hintText: 'Accounting password',
              hintStyle: TextStyle(letterSpacing: 0, color: C.hint, fontWeight: FontWeight.w500),
              prefixIcon: Icon(Icons.key_rounded, color: C.accent2),
              filled: true,
              fillColor: C.g2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(14)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _unlocking ? null : _unlock,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 13),
                    child: Center(
                      child: _unlocking
                          ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                          : Text('Unlock', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );

  Widget _moneyPane() {
    if (_moneyLoading && _money == null) return Padding(padding: EdgeInsets.symmetric(vertical: 50), child: Center(child: CircularProgressIndicator(color: C.accent2)));
    if (_locked) return _lockCard();
    if (_moneyErr.isNotEmpty) return _empty(_moneyErr, icon: Icons.cloud_off_rounded);
    final m = _money;
    if (m == null) return SizedBox();
    final t = (m['totals'] as Map?) ?? {};
    final pays = ((m['payments'] as List?) ?? []).whereType<Map>().toList();
    final coms = ((m['commitments'] as List?) ?? []).whereType<Map>().toList();
    final works = ((t['works'] as List?) ?? []).whereType<Map>().toList();
    final comm = ((m['commission'] as List?) ?? []).whereType<Map>().toList();
    final cpays = ((m['commissionPayments'] as List?) ?? []).whereType<Map>().toList();
    final pct = ((t['percent'] as num?) ?? 0).clamp(0, 100).toDouble();

    Widget tile(String l, num? v, Color c) => Container(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(color: c.withAlpha(C.dark ? 34 : 22), borderRadius: BorderRadius.circular(14), border: Border(left: BorderSide(color: c, width: 3.5))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .6, color: C.muted)),
            SizedBox(height: 3),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(inr(v), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: c))),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: EdgeInsets.all(14),
        decoration: _deco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            childAspectRatio: 2.25,
            mainAxisSpacing: 9,
            crossAxisSpacing: 9,
            children: [
              tile('Payable', t['deal'] as num?, C.accent),
              tile('Received', t['paid'] as num?, C.success),
              tile('Balance', t['remaining'] as num?, C.danger),
              tile('Committed', t['committed'] as num?, Color(0xFFF59E0B)),
            ],
          ),
          SizedBox(height: 12),
          Row(children: [
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(9), child: LinearProgressIndicator(value: pct / 100, minHeight: 7, backgroundColor: C.g2, valueColor: AlwaysStoppedAnimation(C.success)))),
            SizedBox(width: 9),
            Text('${pct.round()}% received', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.sub)),
          ]),
          SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _chip('Confirmed ${inr(t['confirm'] as num?)}'),
            if (((t['extra'] as num?) ?? 0) > 0) _chip('Additional work ${inr(t['extra'] as num?)}'),
            if (((t['pdiscount'] as num?) ?? 0) > 0) _chip('Project discount ${inr(t['pdiscount'] as num?)}'),
            if (((t['discount'] as num?) ?? 0) > 0) _chip('Payment discount ${inr(t['discount'] as num?)}'),
            if (t['fully'] == true) _chip('Fully paid', fg: C.success, bg: C.success.withAlpha(30)),
          ]),
        ]),
      ),
      if (works.isNotEmpty) ...[
        _section('Additional work', Icons.add_task_rounded, works.length),
        for (final w in works)
          Container(
            margin: EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.all(12),
            decoration: _deco(),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${(w['refno'] ?? '').toString().isEmpty ? '' : '${w['refno']} · '}${w['title']}', style: TextStyle(fontWeight: FontWeight.w800, color: C.text)),
                  SizedBox(height: 3),
                  Text('Payable ${inr(w['payable'] as num?)} · Paid ${inr(w['paid'] as num?)}', style: TextStyle(fontSize: 12.5, color: C.muted)),
                ]),
              ),
              Text(inr(w['left'] as num?), style: TextStyle(fontWeight: FontWeight.w900, color: ((w['left'] as num?) ?? 0) > 0 ? C.danger : C.success)),
            ]),
          ),
      ],
      _section('Payment history', Icons.receipt_long_rounded, pays.length),
      if (pays.isEmpty) _empty('No payment received yet.', icon: Icons.payments_outlined),
      for (final p in pays)
        Container(
          margin: EdgeInsets.only(bottom: 8),
          padding: EdgeInsets.all(12),
          decoration: _deco(),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: C.success.withAlpha(30), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.south_west_rounded, color: C.success, size: 20)),
            SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(inr(p['amount'] as num?), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5, color: C.success)),
                SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 5, children: [
                  _chip(p['date'].toString()),
                  if ((p['mode'] ?? '').toString().isNotEmpty) _chip(p['mode'].toString()),
                  if ((p['ref'] ?? '').toString().isNotEmpty) _chip('Ref ${p['ref']}'),
                  if (((p['discount'] as num?) ?? 0) > 0) _chip('Discount ${inr(p['discount'] as num?)}', fg: Color(0xFFB86A00), bg: Color(0x22F59E0B)),
                ]),
                if ((p['bank'] ?? '').toString().isNotEmpty) Padding(padding: EdgeInsets.only(top: 5), child: Text('To ${p['bank']}', style: TextStyle(fontSize: 12.5, color: C.muted))),
                if ((p['remark'] ?? '').toString().isNotEmpty) Padding(padding: EdgeInsets.only(top: 3), child: Text(p['remark'].toString(), style: TextStyle(fontSize: 12.5, color: C.sub))),
              ]),
            ),
          ]),
        ),
      _section('Payment commitments', Icons.event_available_rounded, coms.length),
      if (coms.isEmpty) _empty('No commitment.', icon: Icons.event_busy_rounded),
      for (final c in coms)
        Container(
          margin: EdgeInsets.only(bottom: 8),
          padding: EdgeInsets.all(12),
          decoration: _deco(edge: c['late'] == true ? C.danger.withAlpha(120) : null),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(inr(c['amount'] as num?), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: C.text))),
              if (c['late'] == true) _chip('Late', fg: C.danger, bg: C.danger.withAlpha(30)) else _chip((c['status'] ?? '').toString(), fg: c['open'] == true ? C.accent2 : C.muted),
            ]),
            SizedBox(height: 5),
            Wrap(spacing: 6, runSpacing: 5, children: [
              _chip('Date ${c['date']}'),
              if (((c['paid'] as num?) ?? 0) > 0) _chip('Paid ${inr(c['paid'] as num?)}', fg: C.success, bg: C.success.withAlpha(30)),
              if (c['open'] == true && ((c['left'] as num?) ?? 0) > 0) _chip('Left ${inr(c['left'] as num?)}', fg: C.danger, bg: C.danger.withAlpha(26)),
              if ((c['assignee'] ?? '').toString().isNotEmpty) _chip('Follow-up: ${c['assignee']}'),
            ]),
            if ((c['note'] ?? '').toString().isNotEmpty) Padding(padding: EdgeInsets.only(top: 6), child: Text(c['note'].toString(), style: TextStyle(fontSize: 12.5, color: C.sub))),
          ]),
        ),
      if (comm.isNotEmpty) ...[
        _section('Reference commission', Icons.handshake_rounded, comm.length),
        for (final c in comm)
          Container(
            margin: EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.all(12),
            decoration: _deco(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(c['person'].toString(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: C.text))),
                _chip(c['rule'].toString(), fg: Color(0xFFB86A00), bg: Color(0x22F59E0B)),
              ]),
              SizedBox(height: 9),
              Row(children: [
                for (final e in [['Total', c['total'], C.accent], ['Paid', c['paid'], C.success], ['Unpaid', c['left'], C.danger], ['Due now', c['due'], Color(0xFFF59E0B)]])
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((e[0] as String).toUpperCase(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: C.muted)),
                      FittedBox(fit: BoxFit.scaleDown, child: Text(inr(e[1] as num?), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: e[2] as Color))),
                    ]),
                  ),
              ]),
              if (((c['old'] as num?) ?? 0) > 0) Padding(padding: EdgeInsets.only(top: 7), child: Text('Old payments (no accounting): ${inr(c['old'] as num?)}', style: TextStyle(fontSize: 12, color: C.muted))),
            ]),
          ),
        if (cpays.isNotEmpty) ...[
          _section('Commission payments', Icons.history_rounded, cpays.length),
          for (final p in cpays)
            Container(
              margin: EdgeInsets.only(bottom: 8),
              padding: EdgeInsets.all(12),
              decoration: _deco(),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: C.danger.withAlpha(26), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.north_east_rounded, color: C.danger, size: 20)),
                SizedBox(width: 11),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(inr(p['amount'] as num?), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: C.text))),
                      Text(p['date'].toString(), style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w700)),
                    ]),
                    SizedBox(height: 3),
                    Text(p['person'].toString(), style: TextStyle(fontSize: 13, color: C.sub, fontWeight: FontWeight.w700)),
                    SizedBox(height: 5),
                    Wrap(spacing: 6, runSpacing: 5, children: [
                      p['old'] == true ? _chip('Old · no accounting', fg: Color(0xFFB86A00), bg: Color(0x22F59E0B)) : _chip(p['from'].toString()),
                      if ((p['ref'] ?? '').toString().isNotEmpty) _chip('Ref ${p['ref']}'),
                    ]),
                    if ((p['remark'] ?? '').toString().isNotEmpty) Padding(padding: EdgeInsets.only(top: 5), child: Text(p['remark'].toString(), style: TextStyle(fontSize: 12.5, color: C.sub))),
                  ]),
                ),
              ]),
            ),
        ],
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Aurora(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text((_p['name'] ?? widget.name).toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: C.text)),
          actions: [IconButton(tooltip: 'Refresh', onPressed: () { setState(() => _loading = _d == null); _load(); }, icon: Icon(Icons.refresh_rounded, color: C.sub))],
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: C.accent2))
            : _err.isNotEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.cloud_off_rounded, size: 44, color: C.hint),
                        SizedBox(height: 10),
                        Text(_err, textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
                        SizedBox(height: 14),
                        OutlinedButton(onPressed: () { setState(() => _loading = true); _load(); }, child: Text('Try again')),
                      ]),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(physics: AlwaysScrollableScrollPhysics(), padding: EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                      _hero(),
                      SizedBox(height: 14),
                      _tabs(),
                      SizedBox(height: 14),
                      AnimatedSwitcher(duration: Duration(milliseconds: 220), child: KeyedSubtree(key: ValueKey('$_tab-${_money != null}-$_locked'), child: _pane())),
                    ]),
                  ),
      ),
    );
  }
}
