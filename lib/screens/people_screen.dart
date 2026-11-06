import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'conversation_screen.dart';
import 'threads_screen.dart';

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});
  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  List<Map> _people = [];
  bool _loading = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Api.get('chat/people');
    if (!mounted) return;
    setState(() {
      _people = r.ok && r.data is List ? (r.data as List).whereType<Map>().toList() : [];
      _loading = false;
    });
    if (!r.ok) toast(context, r.msg);
  }

  Future<void> _open(Map p) async {
    final r = await Api.post('chat/direct', {'userid': p['id']});
    if (!mounted) return;
    final id = r.ok && r.data is Map ? ((r.data as Map)['id'] as num?)?.toInt() ?? 0 : 0;
    if (id > 0) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ConversationScreen(thread: Thread(id, p['name'].toString(), '', '', 0, 'direct'))));
    } else {
      toast(context, r.msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _people.where((p) => p['name'].toString().toLowerCase().contains(_q.toLowerCase())).toList();
    return Aurora(
      child: Scaffold(
        appBar: AppBar(title: Text('New chat', style: TextStyle(fontWeight: FontWeight.w800))),
        body: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(onChanged: (v) => setState(() => _q = v), decoration: InputDecoration(hintText: 'Search people', prefixIcon: Icon(Icons.search_rounded, color: C.hint))),
          ),
          Expanded(
            child: _loading
                ? Skeleton()
                : list.isEmpty
                    ? EmptyState(icon: Icons.group_outlined, title: 'No one found')
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: list.length,
                        itemBuilder: (_, i) => Entrance(
                          index: i,
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: GlassCard(
                              onTap: () => _open(list[i]),
                              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(children: [
                                Avatar(list[i]['name'].toString(), size: 44),
                                SizedBox(width: 14),
                                Expanded(child: Text(list[i]['name'].toString(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                                Icon(Icons.chevron_right_rounded, color: C.muted),
                              ]),
                            ),
                          ),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }
}
