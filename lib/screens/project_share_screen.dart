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
  ShareCard(this.id, this.project, this.code, this.client, this.sections, {this.issue = ''});

  static ShareCard? from(dynamic j) {
    if (j is! Map) return null;
    return ShareCard(
      (j['id'] as num?)?.toInt() ?? 0,
      (j['project'] ?? '').toString(),
      (j['code'] ?? '').toString(),
      (j['client'] ?? '').toString(),
      ((j['sections'] as List?) ?? []).map((e) => e.toString()).toList(),
      issue: (j['issue'] ?? '').toString(),
    );
  }
}

/// The card inside the chat bubble
class ShareCardView extends StatelessWidget {
  final ShareCard s;
  final bool mine;
  const ShareCardView(this.s, {super.key, required this.mine});

  @override
  Widget build(BuildContext context) {
    final sub = (s.issue.isNotEmpty ? [s.project] : [s.code, s.client]).where((e) => e.isNotEmpty).join(' · ');
    return Container(
      margin: EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.dark ? Color(0x22FFFFFF) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text(s.issue.isNotEmpty ? '🐞' : '📁', style: TextStyle(fontSize: 26)),
          SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.issue.isNotEmpty ? s.issue : s.project, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: C.text)),
              if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 12, color: C.muted)),
            ]),
          ),
        ]),
        SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final x in s.sections)
            Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: C.accent.withAlpha(36), borderRadius: BorderRadius.circular(20)), child: Text(x, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.accent2))),
        ]),
        SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectShareScreen(s))), child: Text('View details')),
        ),
      ]),
    );
  }
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

  Widget _field(String key, int i, Map f) {
    final kind = (f['kind'] ?? 'text').toString();
    final v = (f['value'] ?? '').toString();
    final id = '$key:$i';
    final secret = kind == 'secret';
    final shown = _shown.contains(id);
    if (kind == 'image') {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((f['label'] ?? '').toString(), style: TextStyle(color: C.muted, fontSize: 13)),
          SizedBox(height: 6),
          GestureDetector(
            onTap: () => openLink(v),
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(v, width: double.infinity, height: 200, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 60, color: C.g2, alignment: Alignment.center, child: Text('Open screenshot', style: TextStyle(color: C.accent2))))),
          ),
        ]),
      );
    }
    final link = kind == 'link' || kind == 'phone';
    final style = TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: link ? C.accent2 : C.text);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text((f['label'] ?? '').toString(), style: TextStyle(color: C.muted, fontSize: 13))),
        Expanded(
          child: GestureDetector(
            onTap: link ? () => openLink(kind == 'phone' ? 'tel:$v' : _url(v)) : null,
            child: Text(secret && !shown ? '••••••••' : v, style: style),
          ),
        ),
        if (secret) InkWell(onTap: () => setState(() => shown ? _shown.remove(id) : _shown.add(id)), child: Padding(padding: EdgeInsets.all(6), child: Icon(shown ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 19, color: C.muted))),
        InkWell(onTap: () => _copy(v), child: Padding(padding: EdgeInsets.all(6), child: Icon(Icons.copy_rounded, size: 18, color: C.muted))),
      ]),
    );
  }

  Widget _chip(String t) => Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: C.g2, borderRadius: BorderRadius.circular(20)), child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.sub)));

  Widget _item(Map r) {
    final chips = [r['priority'], (r['due'] ?? '').toString().isEmpty ? null : 'Due ${r['due']}', r['state'], r['category']].where((e) => e != null && e.toString().isNotEmpty).map((e) => e.toString()).toList();
    final team = ((r['team'] as List?) ?? []).map((e) => e.toString()).toList();
    final text = (r['text'] ?? '').toString();
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.g1, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((r['title'] ?? '').toString(), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: C.text)),
        if (chips.isNotEmpty) Padding(padding: EdgeInsets.only(top: 6), child: Wrap(spacing: 6, runSpacing: 4, children: [for (final c in chips) _chip(c)])),
        if (text.isNotEmpty) Padding(padding: EdgeInsets.only(top: 6), child: Text(text, style: TextStyle(color: C.sub, fontSize: 13.5, height: 1.35))),
        if (team.isNotEmpty) Padding(padding: EdgeInsets.only(top: 6), child: Text('👥 ${team.join(', ')}', style: TextStyle(color: C.muted, fontSize: 12.5))),
      ]),
    );
  }

  Widget _plan(Map r) {
    final text = (r['text'] ?? '').toString();
    final file = r['file'] is Map ? r['file'] as Map : null;
    final imgs = ((r['images'] as List?) ?? []).map((e) => e.toString()).toList();
    final head = [(r['date'] ?? '').toString(), (r['time'] ?? '').toString()].where((e) => e.isNotEmpty).join(' · ');
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.g1, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(head, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: C.text)),
        if (text.isNotEmpty) Padding(padding: EdgeInsets.only(top: 6), child: Text(text, style: TextStyle(color: C.sub, fontSize: 13.5, height: 1.35))),
        if (file != null) Padding(padding: EdgeInsets.only(top: 8), child: InkWell(onTap: () => openLink(file['url'].toString()), child: Text('📎 ${file['name']}', style: TextStyle(color: C.accent2, fontWeight: FontWeight.w700)))),
        if (imgs.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final u in imgs)
                GestureDetector(
                  onTap: () => openLink(u),
                  child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(u, width: 92, height: 92, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 92, height: 92, color: C.g2))),
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
    if (rows.isEmpty) return Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Nothing added here.', style: TextStyle(color: C.muted))));
    final maps = rows.whereType<Map>().toList();
    if (k == 'plan') return Column(children: [for (final r in maps) _plan(r)]);
    if (k == 'issues' || k == 'points' || k == 'care') return Column(children: [for (final r in maps) _item(r)]);
    return Column(children: [for (var i = 0; i < maps.length; i++) _field(k, i, maps[i])]);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    return Scaffold(
      appBar: AppBar(title: Text(c.issue.isNotEmpty ? c.issue : c.project, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: C.accent2))
          : _err.isNotEmpty
              ? Center(child: Padding(padding: EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_err, textAlign: TextAlign.center, style: TextStyle(color: C.muted)), SizedBox(height: 12), OutlinedButton(onPressed: () { setState(() => _loading = true); _load(); }, child: Text('Try again'))])))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
                    Text((c.issue.isNotEmpty ? [c.project] : [c.code, c.client]).where((e) => e.isNotEmpty).join(' · '), style: TextStyle(color: C.muted)),
                    SizedBox(height: 2),
                    Text('Shared by ${_d?['by'] ?? ''} · ${_d?['time'] ?? ''}  (live data)', style: TextStyle(color: C.hint, fontSize: 12)),
                    if ((_d?['note'] ?? '').toString().isNotEmpty) Padding(padding: EdgeInsets.only(top: 8), child: Text(_d!['note'].toString(), style: TextStyle(color: C.text))),
                    SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (var i = 0; i < _labels.length; i++)
                          Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: ChoiceChip(label: Text(_labels[i]), selected: _tab == i, onSelected: (_) => setState(() => _tab = i), selectedColor: C.accent, labelStyle: TextStyle(color: _tab == i ? Colors.white : C.text, fontWeight: FontWeight.w700)),
                          ),
                      ]),
                    ),
                    SizedBox(height: 10),
                    _pane(),
                  ]),
                ),
    );
  }
}
