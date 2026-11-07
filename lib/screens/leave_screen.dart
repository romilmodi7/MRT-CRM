import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Apply for leave from the app, and see / cancel my requests. Works with the employee login only (no device permission).
class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});
  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  bool _loading = true, _busy = false;
  Map _bal = {};
  List<Map> _types = [];
  List<Map> _mine = [];
  DateTime? _from, _to;
  int _type = 0, _day = 0;
  final _reason = TextEditingController();

  static const _days = ['Full day', 'First half', 'Second half'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await Api.get('leave');
    if (!mounted) return;
    if (r.ok && r.data is Map) {
      final d = r.data as Map;
      setState(() {
        _bal = d['balance'] is Map ? d['balance'] as Map : {};
        _types = d['types'] is List ? (d['types'] as List).whereType<Map>().toList() : [];
        _mine = d['mine'] is List ? (d['mine'] as List).whereType<Map>().toList() : [];
        if (_types.isNotEmpty && !_types.any((t) => (t['id'] as num?)?.toInt() == _type)) _type = (_types.first['id'] as num).toInt();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      toast(context, r.msg);
    }
  }

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _show(DateTime? d) => d == null ? 'Select date' : '${d.day} ${_months[d.month - 1]} ${d.year}';
  bool get _single => _from != null && _to != null && _iso(_from!) == _iso(_to!);

  Future<void> _pick(bool from) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = from ? today : (_from ?? today);
    final init = (from ? _from : _to) ?? first;
    final p = await showDatePicker(context: context, initialDate: init.isBefore(first) ? first : init, firstDate: first, lastDate: today.add(Duration(days: 365)));
    if (p == null || !mounted) return;
    setState(() {
      if (from) {
        _from = p;
        if (_to == null || _to!.isBefore(p)) _to = p;
      } else {
        _to = p;
      }
      if (!_single) _day = 0;
    });
  }

  Future<void> _apply() async {
    if (_from == null || _to == null) return toast(context, 'Please choose the dates.');
    if (_reason.text.trim().length < 3) return toast(context, 'Please write a reason.');
    setState(() => _busy = true);
    final r = await Api.post('leave', {'fromdate': _iso(_from!), 'todate': _iso(_to!), 'leavetype': _type, 'daytype': _single ? _day : 0, 'reason': _reason.text.trim()});
    if (!mounted) return;
    setState(() => _busy = false);
    toast(context, r.ok ? (r.msg.isNotEmpty ? r.msg : 'Leave applied.') : r.msg);
    if (r.ok) {
      setState(() {
        _from = null;
        _to = null;
        _day = 0;
        _reason.clear();
      });
      _load();
    }
  }

  Future<void> _cancel(Map l) async {
    if (!await confirm(context, 'Cancel this leave request?', yes: 'Cancel leave', no: 'Keep')) return;
    final r = await Api.post('leave/${l['id']}/cancel');
    if (!mounted) return;
    toast(context, r.ok ? 'Leave cancelled.' : r.msg);
    if (r.ok) _load();
  }

  Color _sc(int s) => s == 1 ? C.success : s == 2 ? C.danger : s == 0 ? Color(0xFFF59E0B) : C.muted;

  Widget _chip(String t, bool on, VoidCallback tap) => GestureDetector(
        onTap: tap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(color: on ? null : C.g2, gradient: on ? C.grad : null, borderRadius: BorderRadius.circular(20), border: Border.all(color: on ? Colors.transparent : C.line)),
          child: Text(t, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: on ? Colors.white : C.text)),
        ),
      );

  Widget _date(String label, DateTime? d, VoidCallback tap) => Expanded(
        child: GlassCard(
          onTap: tap,
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          radius: 16,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 11, color: C.muted, fontWeight: FontWeight.w700)),
            SizedBox(height: 3),
            Text(_show(d), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: d == null ? C.hint : C.text)),
          ]),
        ),
      );

  Widget _stat(String k, dynamic v, {Color? c}) {
    final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
    final t = n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
    return Expanded(
      child: Column(children: [
        Text(t, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c ?? C.text)),
        SizedBox(height: 2),
        Text(k, style: TextStyle(fontSize: 11, color: C.muted)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Aurora(
      child: Scaffold(
        appBar: AppBar(title: Text('Leave', style: TextStyle(fontWeight: FontWeight.w800))),
        body: _loading
            ? Skeleton()
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
                  if (_bal.isNotEmpty)
                    GlassCard(
                      child: Column(children: [
                        Align(alignment: Alignment.centerLeft, child: Text('Paid leave · ${_bal['month'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w700, color: C.muted, fontSize: 12))),
                        SizedBox(height: 10),
                        Row(children: [
                          _stat('allowed', _bal['allowed']),
                          _stat('used', _bal['used']),
                          _stat('remaining', _bal['remaining'], c: C.success),
                          _stat('unpaid', _bal['unpaid'], c: ((_bal['unpaid'] as num?) ?? 0) > 0 ? C.danger : null),
                        ]),
                      ]),
                    ),
                  SizedBox(height: 14),
                  Text('Apply for leave', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  SizedBox(height: 10),
                  Row(children: [_date('FROM', _from, () => _pick(true)), SizedBox(width: 10), _date('TO', _to, () => _pick(false))]),
                  if (_single) ...[
                    SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [for (var i = 0; i < _days.length; i++) _chip(_days[i], _day == i, () => setState(() => _day = i))]),
                  ],
                  SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final t in _types) _chip((t['name'] ?? '').toString(), (t['id'] as num?)?.toInt() == _type, () => setState(() => _type = (t['id'] as num).toInt())),
                  ]),
                  SizedBox(height: 12),
                  TextField(controller: _reason, minLines: 2, maxLines: 4, maxLength: 500, decoration: InputDecoration(hintText: 'Reason for leave')),
                  SizedBox(height: 8),
                  GradientButton(label: 'Apply leave', icon: Icons.event_available_rounded, busy: _busy, onTap: _apply),
                  SizedBox(height: 22),
                  Text('My leaves', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  if (_mine.isEmpty) Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Center(child: Text('No leave requests yet.', style: TextStyle(color: C.muted)))),
                  for (final l in _mine)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: GlassCard(
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${l['dates']}  ·  ${l['days']} day${(l['days'] as num?) == 1 ? '' : 's'}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              SizedBox(height: 2),
                              Text('${l['type'] ?? ''}${(l['reason'] ?? '').toString().isEmpty ? '' : ' · ${l['reason']}'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 13)),
                            ]),
                          ),
                          SizedBox(width: 8),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: _sc((l['status'] as num?)?.toInt() ?? 0).withAlpha(36), borderRadius: BorderRadius.circular(12)),
                              child: Text((l['statusLabel'] ?? '').toString(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _sc((l['status'] as num?)?.toInt() ?? 0))),
                            ),
                            if (((l['status'] as num?)?.toInt() ?? -1) == 0) TextButton(onPressed: () => _cancel(l), child: Text('Cancel', style: TextStyle(color: C.danger))),
                          ]),
                        ]),
                      ),
                    ),
                ]),
              ),
      ),
    );
  }
}
