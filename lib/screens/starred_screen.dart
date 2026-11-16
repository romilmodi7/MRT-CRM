import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/stickers.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Starred messages of one team chat. Everybody in the chat sees the same stars.
/// Tapping a message goes back to the chat at that message.
class StarredScreen extends StatefulWidget {
  final int thread;
  final String title;
  const StarredScreen({super.key, required this.thread, required this.title});
  @override
  State<StarredScreen> createState() => _StarredScreenState();
}

class _StarredScreenState extends State<StarredScreen> {
  List<Map> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Api.get('chatx/${widget.thread}/stars').then((r) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (r.ok && r.data is Map) _items = (((r.data as Map)['items'] as List?) ?? []).whereType<Map>().toList();
      });
    });
  }

  String _text(Map m) {
    final t = (m['text'] ?? '').toString();
    final st = StickerMsg.parse(t);
    if (st != null) return st.isImage ? 'Sticker${st.cap.isEmpty ? '' : ' · ${st.cap}'}' : '${st.e} ${st.cap}'.trim();
    return t;
  }

  @override
  Widget build(BuildContext context) {
    return Aurora(
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Starred messages', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
          ]),
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? EmptyState(icon: Icons.star_border_rounded, title: 'No starred messages', sub: 'Hold a message and tap Star to keep it here')
                : ListView.separated(
                    padding: EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final m = _items[i];
                      return Material(
                        color: C.g1,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(context, (m['id'] as num?)?.toInt()),
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.star_rounded, color: Color(0xFFF5B400), size: 22),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(m['mine'] == true ? 'You' : (m['name'] ?? '').toString(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.accent2)),
                                  SizedBox(height: 2),
                                  Text(_text(m), maxLines: 5, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, height: 1.35)),
                                  SizedBox(height: 4),
                                  Text((m['time'] ?? '').toString(), style: TextStyle(fontSize: 11.5, color: C.muted)),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
