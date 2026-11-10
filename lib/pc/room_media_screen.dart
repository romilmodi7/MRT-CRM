import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../core/api.dart';
import '../core/platform.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import 'pc_models.dart';
import 'pc_widgets.dart';

/// "Media, links and docs" of a private chat (like WhatsApp): everything shared in the room, one kind per tab,
/// newest first, loading on as you scroll.
class RoomMediaScreen extends StatefulWidget {
  final String title;
  final bool showDeleted;
  const RoomMediaScreen({super.key, required this.title, this.showDeleted = false});
  @override
  State<RoomMediaScreen> createState() => _RoomMediaScreenState();
}

class _RoomMediaScreenState extends State<RoomMediaScreen> {
  static const kinds = ['media', 'docs', 'links', 'gifs', 'voice'];
  static const labels = ['Media', 'Docs', 'Links', 'GIFs', 'Voice'];
  static const icons = [Icons.photo_library_rounded, Icons.description_rounded, Icons.link_rounded, Icons.gif_box_rounded, Icons.mic_rounded];
  Map<String, int> _counts = {};

  void _setCounts(Map<String, int> c) {
    if (mounted) setState(() => _counts = c);
  }

  @override
  Widget build(BuildContext context) {
    return Aurora(
      child: DefaultTabController(
        length: kinds.length,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Media, links and docs', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: C.text)),
              if (widget.title.isNotEmpty) Text(widget.title, style: TextStyle(fontSize: 12, color: C.muted)),
            ]),
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: C.accent2,
              indicatorWeight: 3,
              labelColor: C.accent2,
              unselectedLabelColor: C.sub,
              labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              dividerColor: C.line,
              tabs: [
                for (var i = 0; i < kinds.length; i++)
                  Tab(
                    height: 46,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icons[i], size: 17),
                      SizedBox(width: 6),
                      Text(labels[i]),
                      if ((_counts[kinds[i]] ?? 0) > 0) ...[
                        SizedBox(width: 6),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(color: C.accent.withAlpha(46), borderRadius: BorderRadius.circular(20)),
                          child: Text('${_counts[kinds[i]]}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ]),
                  ),
              ],
            ),
          ),
          body: TabBarView(children: [
            for (final k in kinds) _KindList(kind: k, showDeleted: widget.showDeleted, onCounts: _setCounts),
          ]),
        ),
      ),
    );
  }
}

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String _month(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  final n = DateTime.now();
  if (d.year == n.year && d.month == n.month) return 'This month';
  return '${_months[d.month - 1]} ${d.year}';
}

class _Item {
  final PcMsg m;
  final String? link;
  final String? text;
  _Item(this.m, {this.link, this.text});
}

class _KindList extends StatefulWidget {
  final String kind;
  final bool showDeleted;
  final void Function(Map<String, int>) onCounts;
  const _KindList({required this.kind, required this.showDeleted, required this.onCounts});
  @override
  State<_KindList> createState() => _KindListState();
}

class _KindListState extends State<_KindList> with AutomaticKeepAliveClientMixin {
  final _sc = ScrollController();
  final List<_Item> _items = [];
  bool _loading = false, _more = true, _first = true;
  String _err = '';
  int _last = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (_sc.hasClients && _sc.position.pixels > _sc.position.maxScrollExtent - 700) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (!_more && !reset)) return;
    if (reset) {
      _items.clear();
      _more = true;
      _last = 0;
      _first = true;
    }
    setState(() {
      _loading = true;
      _err = '';
    });
    final r = await PcApi.get(PcApi.room('media-list'), {'kind': widget.kind, 'before': '$_last', if (PcApi.owner && widget.showDeleted) 'hidden': '1'});
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _loading = false;
        _err = r.msg.isEmpty ? 'Could not load.' : r.msg;
      });
      return;
    }
    final j = r.json;
    final list = ((j['items'] as List?) ?? []).whereType<Map>();
    for (final x in list) {
      final m = PcMsg.from(x);
      if (widget.kind == 'links') {
        final ls = ((x['links'] as List?) ?? []).map((e) => e.toString()).toList();
        for (final l in ls) {
          _items.add(_Item(m, link: l, text: m.body));
        }
      } else {
        _items.add(_Item(m));
      }
    }
    if (j['counts'] is Map) {
      widget.onCounts({for (final e in (j['counts'] as Map).entries) e.key.toString(): (e.value as num).toInt()});
    }
    setState(() {
      _loading = false;
      _first = false;
      _more = j['more'] == true;
      _last = (j['last'] as num?)?.toInt() ?? _last;
    });
    // a short page that does not fill the screen: keep going
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _more && _sc.hasClients && _sc.position.maxScrollExtent <= 0) _load();
    });
  }

  // ------------------------------------------------------------------ pieces

  Widget _header(String t) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(t.toUpperCase(), style: TextStyle(color: C.muted, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .9)),
      );

  Widget _footer() {
    if (_loading) return Padding(padding: EdgeInsets.all(22), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: C.accent2))));
    if (_err.isNotEmpty) return Padding(padding: EdgeInsets.all(16), child: Center(child: TextButton(onPressed: _load, child: Text('$_err  Tap to retry'))));
    if (!_more && _items.isNotEmpty) return Padding(padding: EdgeInsets.fromLTRB(16, 18, 16, 28), child: Center(child: Text('${_items.length} ${_label()}', style: TextStyle(color: C.hint, fontSize: 12))));
    return SizedBox(height: 28);
  }

  String _label() => const {'media': 'photos and videos', 'docs': 'documents', 'links': 'links', 'gifs': 'GIFs', 'voice': 'voice messages'}[widget.kind]!;

  Widget _empty() {
    final t = const {
      'media': ['No photos or videos yet', Icons.photo_library_outlined],
      'docs': ['No documents yet', Icons.description_outlined],
      'links': ['No links yet', Icons.link_rounded],
      'gifs': ['No GIFs yet', Icons.gif_box_outlined],
      'voice': ['No voice messages yet', Icons.mic_none_rounded],
    }[widget.kind]!;
    return ListView(children: [
      SizedBox(height: 120),
      Icon(t[1] as IconData, size: 52, color: C.hint),
      SizedBox(height: 10),
      Center(child: Text(t[0] as String, style: TextStyle(color: C.muted, fontSize: 15, fontWeight: FontWeight.w600))),
      SizedBox(height: 4),
      Center(child: Text('Anything shared in this chat shows up here.', style: TextStyle(color: C.hint, fontSize: 12.5))),
    ]);
  }

  Future<void> _openDoc(PcMsg m) async {
    toast(context, 'Opening...');
    final f = await mediaFile(m, extOf(m));
    if (f == null) {
      if (mounted) toast(context, 'Could not open the file.');
      return;
    }
    await AwayGuard.run(() => OpenFilex.open(f.path));
  }

  Widget _thumb(_Item it) {
    final m = it.m;
    if (m.type == 'video') {
      return GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPage(m: m))),
        child: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1B1450), Color(0xFF0B0E22)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(6)),
          child: Stack(alignment: Alignment.center, children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0x66FFFFFF)), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26)),
            Positioned(left: 6, bottom: 5, child: Row(children: [Icon(Icons.videocam_rounded, size: 13, color: Colors.white70), SizedBox(width: 3), Text(m.size > 0 ? fmtSize(m.size) : 'Video', style: TextStyle(fontSize: 10.5, color: Colors.white70, fontWeight: FontWeight.w700))])),
          ]),
        ),
      );
    }
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImageViewerPage(cacheKey: 'p${m.id}', loader: () => mediaBytes(m.id), title: ''))),
      child: AuthImage(cacheKey: 'p${m.id}', loader: () => mediaBytes(m.id), radius: BorderRadius.circular(6)),
    );
  }

  Widget _gifTile(_Item it) => GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.all(18),
            child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.network(it.m.gif ?? '', fit: BoxFit.contain, errorBuilder: (_, __, ___) => Container(height: 160, color: C.card2, alignment: Alignment.center, child: Text('GIF', style: TextStyle(color: C.muted))))),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(fit: StackFit.expand, children: [
            Image.network(it.m.gif ?? '', fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: C.g2, alignment: Alignment.center, child: Text('GIF', style: TextStyle(color: C.muted)))),
            Positioned(left: 5, bottom: 5, child: Container(padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Color(0x99000000), borderRadius: BorderRadius.circular(4)), child: Text('GIF', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)))),
          ]),
        ),
      );

  ({IconData icon, Color color}) _docStyle(String ext) {
    switch (ext) {
      case 'pdf':
        return (icon: Icons.picture_as_pdf_rounded, color: Color(0xFFE5484D));
      case 'doc':
      case 'docx':
      case 'txt':
      case 'rtf':
        return (icon: Icons.description_rounded, color: Color(0xFF3E7BFA));
      case 'xls':
      case 'xlsx':
      case 'csv':
        return (icon: Icons.table_chart_rounded, color: Color(0xFF2FB872));
      case 'ppt':
      case 'pptx':
        return (icon: Icons.slideshow_rounded, color: Color(0xFFF08A24));
      case 'zip':
      case 'rar':
      case '7z':
        return (icon: Icons.folder_zip_rounded, color: Color(0xFFE0A91B));
      case 'apk':
        return (icon: Icons.android_rounded, color: Color(0xFF3DDC84));
      case 'sql':
      case 'json':
      case 'xml':
      case 'php':
      case 'js':
        return (icon: Icons.code_rounded, color: Color(0xFF8F7BFF));
      default:
        return (icon: Icons.insert_drive_file_rounded, color: C.accent2);
    }
  }

  BoxDecoration _card() => BoxDecoration(
        color: C.dark ? C.g1 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.line),
        boxShadow: C.dark ? null : [BoxShadow(color: Color(0x0F111827), blurRadius: 10, offset: Offset(0, 4))],
      );

  String _who(PcMsg m) => m.mine ? 'You' : 'Them';

  Widget _docRow(_Item it) {
    final m = it.m;
    final ext = extOf(m);
    final st = _docStyle(ext);
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: _card(),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openDoc(m),
            child: Padding(
              padding: EdgeInsets.all(11),
              child: Row(children: [
                Container(width: 46, height: 46, decoration: BoxDecoration(color: st.color.withAlpha(36), borderRadius: BorderRadius.circular(13)), child: Icon(st.icon, color: st.color, size: 25)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.mediaName.isEmpty ? 'File' : m.mediaName, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: C.text)),
                    SizedBox(height: 3),
                    Text([if (ext != 'bin') ext.toUpperCase(), if (m.size > 0) fmtSize(m.size), dayLabel(m.ts), _who(m)].join(' · '), style: TextStyle(fontSize: 12, color: C.muted)),
                  ]),
                ),
                Icon(Icons.open_in_new_rounded, size: 18, color: C.hint),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  String _host(String u) {
    final x = Uri.tryParse(RegExp(r'^https?://', caseSensitive: false).hasMatch(u) ? u : 'http://$u');
    final h = x?.host ?? '';
    return h.isEmpty ? u : h.replaceFirst(RegExp(r'^www\.'), '');
  }

  Widget _linkRow(_Item it) {
    final m = it.m;
    final u = it.link!;
    final full = RegExp(r'^https?://', caseSensitive: false).hasMatch(u) ? u : 'http://$u';
    final extra = (it.text ?? '').replaceAll(u, '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: _card(),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => openLink(full),
            onLongPress: () async {
              await Clipboard.setData(ClipboardData(text: full));
              if (mounted) toast(context, 'Link copied');
            },
            child: Padding(
              padding: EdgeInsets.all(11),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 46, height: 46, decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(13)), child: Icon(Icons.link_rounded, color: Colors.white, size: 24)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_host(u), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: C.text)),
                    SizedBox(height: 2),
                    Text(u, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: C.dark ? C.accent2 : C.accent, height: 1.3)),
                    if (extra.isNotEmpty) Padding(padding: EdgeInsets.only(top: 4), child: Text(extra, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: C.sub))),
                    SizedBox(height: 4),
                    Text('${dayLabel(m.ts)} · ${clock(m.ts)} · ${_who(m)}', style: TextStyle(fontSize: 11.5, color: C.muted)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _voiceRow(_Item it) {
    final m = it.m;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            gradient: m.mine ? C.gradMe : null,
            color: m.mine ? null : (C.dark ? C.g3 : Colors.white),
            borderRadius: BorderRadius.circular(18),
            border: m.mine ? null : Border.all(color: C.line),
          ),
          child: DefaultTextStyle.merge(style: TextStyle(color: m.mine ? Colors.white : C.text), child: VoiceBubble(m: m)),
        ),
        Padding(padding: EdgeInsets.fromLTRB(6, 3, 6, 0), child: Text('${_who(m)} · ${dayLabel(m.ts)} · ${clock(m.ts)}', style: TextStyle(fontSize: 11.5, color: C.muted))),
      ]),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_first && _loading) return Center(child: CircularProgressIndicator(color: C.accent2));
    if (_first && _err.isNotEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.cloud_off_rounded, size: 44, color: C.hint), SizedBox(height: 8), Text(_err, style: TextStyle(color: C.muted)), SizedBox(height: 10), OutlinedButton(onPressed: () => _load(reset: true), child: Text('Try again'))]));
    }
    if (_items.isEmpty) return RefreshIndicator(onRefresh: () => _load(reset: true), child: _empty());

    // group by month, keeping the newest first
    final groups = <String, List<_Item>>{};
    for (final it in _items) {
      groups.putIfAbsent(_month(it.m.ts), () => []).add(it);
    }
    final grid = widget.kind == 'media' || widget.kind == 'gifs';
    final slivers = <Widget>[];
    groups.forEach((month, list) {
      slivers.add(SliverToBoxAdapter(child: _header(month)));
      if (grid) {
        slivers.add(SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
            delegate: SliverChildBuilderDelegate((_, i) => widget.kind == 'gifs' ? _gifTile(list[i]) : _thumb(list[i]), childCount: list.length),
          ),
        ));
      } else {
        slivers.add(SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => widget.kind == 'docs' ? _docRow(list[i]) : widget.kind == 'links' ? _linkRow(list[i]) : _voiceRow(list[i]),
            childCount: list.length,
          ),
        ));
      }
    });
    slivers.add(SliverToBoxAdapter(child: _footer()));
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: CustomScrollView(controller: _sc, physics: AlwaysScrollableScrollPhysics(), slivers: slivers),
    );
  }
}
