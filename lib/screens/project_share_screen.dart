import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/platform.dart';
import '../core/theme.dart';

/// A project shared in a chat (card in the bubble). Opens for anyone who is in that chat; no project right needed.
class ShareCard {
  final int id;
  final String project, code, client, issue;
  final List<String> sections;
  final int level; // 0 High, 1 Medium, 2 Low, -1 none
  ShareCard(this.id, this.project, this.code, this.client, this.sections, {this.issue = '', this.level = -1});

  static ShareCard? from(dynamic j) {
    if (j is! Map) return null;
    return ShareCard(
      (j['id'] as num?)?.toInt() ?? 0,
      (j['project'] ?? '').toString(),
      (j['code'] ?? '').toString(),
      (j['client'] ?? '').toString(),
      ((j['sections'] as List?) ?? []).map((e) => e.toString()).toList(),
      issue: (j['issue'] ?? '').toString(),
      level: (j['level'] is num) ? (j['level'] as num).toInt() : -1,
    );
  }
}

const _lvNames = ['High', 'Medium', 'Low'];
const _lvColors = [Color(0xFFE0533D), Color(0xFFF59E0B), Color(0xFF16A34A)];
Color? lvColor(int l) => (l >= 0 && l <= 2) ? _lvColors[l] : null;
Widget lvBadge(int l) => lvColor(l) == null
    ? SizedBox.shrink()
    : Container(padding: EdgeInsets.symmetric(horizontal: 9, vertical: 2), decoration: BoxDecoration(color: lvColor(l), borderRadius: BorderRadius.circular(20)), child: Text(_lvNames[l], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)));

/// The card inside the chat bubble
class ShareCardView extends StatelessWidget {
  final ShareCard s;
  final bool mine;
  const ShareCardView(this.s, {super.key, required this.mine});

  @override
  Widget build(BuildContext context) {
    final sub = (s.issue.isNotEmpty ? [s.project] : [s.code, s.client]).where((e) => e.isNotEmpty).join(' · ');
    final lc = lvColor(s.level);
    return Container(
      margin: EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: C.dark ? Color(0x26FFFFFF) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.line),
        boxShadow: C.dark ? null : [BoxShadow(color: Color(0x14111827), blurRadius: 14, offset: Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: lc ?? C.accent),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(13)),
                    alignment: Alignment.center,
                    child: Icon(s.issue.isNotEmpty ? Icons.bug_report_rounded : Icons.folder_special_rounded, color: Colors.white, size: 22),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.issue.isNotEmpty ? s.issue : s.project, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: C.text)),
                      if (sub.isNotEmpty) Padding(padding: EdgeInsets.only(top: 1), child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted))),
                    ]),
                  ),
                  if (s.level >= 0) lvBadge(s.level),
                ]),
                if (s.sections.isNotEmpty) ...[
                  SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final x in s.sections)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(color: C.accent.withAlpha(34), borderRadius: BorderRadius.circular(20), border: Border.all(color: C.accent.withAlpha(60))),
                        child: Text(x, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.dark ? C.accent2 : C.accent)),
                      ),
                  ]),
                ],
                SizedBox(height: 12),
                _GradButton(label: 'View details', icon: Icons.arrow_forward_rounded, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectShareScreen(s)))),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _GradButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GradButton({required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(14)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 11),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                SizedBox(width: 6),
                Icon(icon, color: Colors.white, size: 18),
              ]),
            ),
          ),
        ),
      );
}

/// Full screen: the shared parts of the project, one tab per part
class ProjectShareScreen extends StatefulWidget {
  final ShareCard card;
  const ProjectShareScreen(this.card, {super.key});
  @override
  State<ProjectShareScreen> createState() => _ProjectShareScreenState();
}

class _ProjectShareScreenState extends State<ProjectShareScreen> {
  Map<String, dynamic>? _d;
  String _err = '';
  bool _loading = true;
  int _tab = 0;
  final Set<String> _shown = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Api.get('chat/share/${widget.card.id}');
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
  }

  List<String> get _keys => ((_d?['keys'] as List?) ?? []).map((e) => e.toString()).toList();
  List<String> get _labels => ((_d?['labels'] as List?) ?? []).map((e) => e.toString()).toList();

  String _url(String v) => RegExp(r'^https?://', caseSensitive: false).hasMatch(v) ? v : 'http://$v';

  Future<void> _copy(String v) async {
    await Clipboard.setData(ClipboardData(text: v));
    if (mounted) toast(context, 'Copied');
  }

  IconData _tabIcon(String key, String label) {
    final t = '$key $label'.toLowerCase();
    if (t.contains('ftp')) return Icons.cloud_upload_rounded;
    if (t.contains('data') && t.contains('base')) return Icons.storage_rounded;
    if (t.contains('server') || t.contains('host')) return Icons.dns_rounded;
    if (t.contains('domain') || t.contains('url') || t.contains('web')) return Icons.language_rounded;
    if (t.contains('issue') || t.contains('bug')) return Icons.bug_report_rounded;
    if (t.contains('plan')) return Icons.event_note_rounded;
    if (t.contains('point') || t.contains('care')) return Icons.push_pin_rounded;
    if (t.contains('mail') || t.contains('smtp')) return Icons.mail_rounded;
    if (t.contains('git') || t.contains('code')) return Icons.code_rounded;
    if (t.contains('app') || t.contains('android')) return Icons.phone_android_rounded;
    if (t.contains('screen') || t.contains('image')) return Icons.image_rounded;
    return Icons.folder_rounded;
  }

  String _initials(String n) {
    final p = n.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (p.isEmpty) return '?';
    return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
  }

  Widget _round(IconData i, VoidCallback onTap, {Color? color}) => Padding(
        padding: EdgeInsets.only(left: 6),
        child: Material(
          color: C.g2,
          shape: CircleBorder(),
          child: InkWell(
            customBorder: CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 36, height: 36, child: Icon(i, size: 18, color: color ?? C.sub)),
          ),
        ),
      );

  Widget _field(String key, int i, Map f, {required bool last}) {
    final kind = (f['kind'] ?? 'text').toString();
    final v = (f['value'] ?? '').toString();
    final label = (f['label'] ?? '').toString();
    final id = '$key:$i';
    final secret = kind == 'secret';
    final shown = _shown.contains(id);
    final link = kind == 'link' || kind == 'phone';

    if (kind == 'image') {
      return Padding(
        padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: TextStyle(color: C.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8)),
          SizedBox(height: 8),
          GestureDetector(
            onTap: () => openLink(v),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(v, width: double.infinity, height: 190, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 64, color: C.g2, alignment: Alignment.center, child: Text('Open screenshot', style: TextStyle(color: C.accent2, fontWeight: FontWeight.w700)))),
            ),
          ),
        ]),
      );
    }

    final valueStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 14.5,
      height: 1.3,
      letterSpacing: secret && !shown ? 2 : 0,
      color: link ? (C.dark ? C.accent2 : C.accent) : C.text,
    );
    return Container(
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: C.line))),
      padding: EdgeInsets.fromLTRB(14, 11, 10, 11),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: TextStyle(color: C.muted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .8)),
            SizedBox(height: 3),
            GestureDetector(
              onTap: link ? () => openLink(kind == 'phone' ? 'tel:$v' : _url(v)) : null,
              onLongPress: () => _copy(v),
              child: Text(secret && !shown ? '••••••••••' : (v.isEmpty ? '—' : v), style: valueStyle),
            ),
          ]),
        ),
        if (secret) _round(shown ? Icons.visibility_off_rounded : Icons.visibility_rounded, () => setState(() => shown ? _shown.remove(id) : _shown.add(id))),
        if (link && v.isNotEmpty) _round(kind == 'phone' ? Icons.call_rounded : Icons.open_in_new_rounded, () => openLink(kind == 'phone' ? 'tel:$v' : _url(v))),
        _round(Icons.copy_rounded, () => _copy(v)),
      ]),
    );
  }

  Widget _chip(String t) => Container(
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: C.g2, borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.sub)),
      );

  BoxDecoration _cardDeco({Color? edge}) => BoxDecoration(
        color: C.dark ? C.g1 : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.line),
        boxShadow: C.dark ? null : [BoxShadow(color: Color(0x10111827), blurRadius: 14, offset: Offset(0, 6))],
      );

  Widget _item(Map r) {
    final chips = [r['priority'], (r['due'] ?? '').toString().isEmpty ? null : 'Due ${r['due']}', r['state'], r['category']].where((e) => e != null && e.toString().isNotEmpty).map((e) => e.toString()).toList();
    final team = ((r['team'] as List?) ?? []).map((e) => e.toString()).toList();
    final text = (r['text'] ?? '').toString();
    final lv = (r['level'] is num) ? (r['level'] as num).toInt() : -1;
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      decoration: _cardDeco(),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: lvColor(lv) ?? C.accent.withAlpha(120)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(13),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((r['title'] ?? '').toString(), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: C.text)),
                if (chips.isNotEmpty)
                  Padding(padding: EdgeInsets.only(top: 8), child: Wrap(spacing: 6, runSpacing: 6, children: [for (final c in chips) (lv >= 0 && c == (r['priority'] ?? '').toString()) ? lvBadge(lv) : _chip(c)])),
                if (text.isNotEmpty) Padding(padding: EdgeInsets.only(top: 8), child: Text(text, style: TextStyle(color: C.sub, fontSize: 13.5, height: 1.4))),
                if (team.isNotEmpty) Padding(padding: EdgeInsets.only(top: 8), child: Row(children: [Icon(Icons.groups_rounded, size: 16, color: C.muted), SizedBox(width: 6), Expanded(child: Text(team.join(', '), style: TextStyle(color: C.muted, fontSize: 12.5)))])),
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
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.event_rounded, size: 17, color: C.accent2),
          SizedBox(width: 7),
          Expanded(child: Text(head, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: C.text))),
        ]),
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
    if (keys.isEmpty) return SizedBox();
    final k = keys[_tab.clamp(0, keys.length - 1)];
    final rows = ((_d?['data'] as Map?)?[k] as List?) ?? [];
    if (rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Column(children: [Icon(Icons.inbox_rounded, size: 40, color: C.hint), SizedBox(height: 8), Text('Nothing added here.', style: TextStyle(color: C.muted))])),
      );
    }
    final maps = rows.whereType<Map>().toList();
    if (k == 'plan' || k == 'plansel') return Column(children: [for (final r in maps) _plan(r)]);
    if (k == 'issues' || k == 'issuesel' || k == 'points' || k == 'pointsel' || k == 'care' || k == 'caresel') return Column(children: [for (final r in maps) _item(r)]);
    return Container(
      decoration: _cardDeco(),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [for (var i = 0; i < maps.length; i++) _field(k, i, maps[i], last: i == maps.length - 1)]),
    );
  }

  Widget _hero() {
    final c = widget.card;
    final title = c.issue.isNotEmpty ? c.issue : c.project;
    final sub = (c.issue.isNotEmpty ? [c.project] : [c.code, c.client]).where((e) => e.isNotEmpty).join(' · ');
    final by = (_d?['by'] ?? '').toString();
    final time = (_d?['time'] ?? '').toString();
    final note = (_d?['note'] ?? '').toString();
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
            width: 48, height: 48,
            decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: C.accent.withAlpha(90), blurRadius: 14, offset: Offset(0, 6))]),
            alignment: Alignment.center,
            child: Icon(c.issue.isNotEmpty ? Icons.bug_report_rounded : Icons.folder_special_rounded, color: Colors.white, size: 25),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: C.text, height: 1.2)),
              if (sub.isNotEmpty) Padding(padding: EdgeInsets.only(top: 2), child: Text(sub, style: TextStyle(color: C.sub, fontSize: 13))),
            ]),
          ),
          if (c.level >= 0) lvBadge(c.level),
        ]),
        if (by.isNotEmpty || time.isNotEmpty) ...[
          SizedBox(height: 14),
          Row(children: [
            if (by.isNotEmpty)
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(gradient: C.gradMe, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(_initials(by), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10.5)),
              ),
            if (by.isNotEmpty) SizedBox(width: 8),
            Expanded(
              child: Text(by.isNotEmpty ? 'Shared by $by${time.isNotEmpty ? ' · $time' : ''}' : time, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.sub, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: C.success.withAlpha(34), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: C.success, shape: BoxShape.circle)),
                SizedBox(width: 5),
                Text('Live data', style: TextStyle(color: C.success, fontSize: 11, fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
        ],
        if (note.isNotEmpty) ...[
          SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(11),
            decoration: BoxDecoration(color: C.dark ? Color(0x22000000) : Color(0xAAFFFFFF), borderRadius: BorderRadius.circular(13)),
            child: Text(note, style: TextStyle(color: C.text, fontSize: 13.5, height: 1.4)),
          ),
        ],
      ]),
    );
  }

  Widget _tabs() {
    final keys = _keys;
    final labels = _labels;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sel = _tab == i;
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
                onTap: () => setState(() => _tab = i),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 15),
                  child: Row(children: [
                    Icon(_tabIcon(i < keys.length ? keys[i] : '', labels[i]), size: 17, color: sel ? Colors.white : C.sub),
                    SizedBox(width: 7),
                    Text(labels[i], style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: sel ? Colors.white : C.text)),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    return Aurora(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(c.issue.isNotEmpty ? c.issue : c.project, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: C.text)),
          actions: [IconButton(tooltip: 'Refresh', onPressed: () { setState(() => _loading = true); _load(); }, icon: Icon(Icons.refresh_rounded, color: C.sub))],
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
                      AnimatedSwitcher(duration: Duration(milliseconds: 220), child: KeyedSubtree(key: ValueKey(_tab), child: _pane())),
                    ]),
                  ),
      ),
    );
  }
}
