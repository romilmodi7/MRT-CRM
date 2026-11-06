import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';

/// The location stream lives outside the screen, so sharing keeps going when you leave this page (until it expires, you stop it, or the chat locks).
StreamSubscription<Position>? _liveSub;
DateTime _lastPingAt = DateTime(2000);

/// Share live location with the other person in the chat, and see theirs.
class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});
  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  bool _sharing = false;
  int _minutes = 60;
  List<Map> _others = [];
  late final Poller _tick = Poller(Duration(seconds: 10), _refresh);

  @override
  void initState() {
    super.initState();
    _refresh();
    _tick.start();
  }

  @override
  void dispose() {
    _tick.stop();
    super.dispose();
  }

  Future<void> _refresh() async {
    final r = await PcApi.get(PcApi.room('location/active'));
    if (!mounted || !r.ok) return;
    setState(() {
      _sharing = r.json['mine'] != null && _liveSub != null;
      if (r.json['mine'] == null && _liveSub != null) _stopLocal();
      _others = ((r.json['others'] as List?) ?? []).whereType<Map>().toList();
    });
  }

  Future<void> _start() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) toast(context, 'Turn on location (GPS) first.');
      return;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await AwayGuard.run(() => Geolocator.requestPermission());
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      if (mounted) toast(context, 'Location permission is needed.');
      return;
    }
    final r = await PcApi.post(PcApi.room('location/start'), {'minutes': _minutes, 'label': 'Live location'});
    if (!mounted) return;
    if (!r.ok) {
      toast(context, r.msg);
      return;
    }
    _liveSub?.cancel();
    _liveSub = Geolocator.getPositionStream(locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      intervalDuration: Duration(seconds: 15),
      foregroundNotificationConfig: ForegroundNotificationConfig(notificationTitle: 'Sharing live location', notificationText: 'Tap to return to the app', enableWakeLock: true),
    )).listen(_ping, onError: (_) {});
    setState(() => _sharing = true);
  }

  Future<void> _ping(Position p) async {
    if (DateTime.now().difference(_lastPingAt).inSeconds < 8) return;
    _lastPingAt = DateTime.now();
    final r = await PcApi.post(PcApi.room('location/ping'), {'lat': p.latitude, 'lng': p.longitude, 'accuracy': p.accuracy, 'heading': p.heading});
    if ((r.ok && r.json['sharing'] == false) || r.code == 401) _stopLocal();
  }

  void _stopLocal() {
    _liveSub?.cancel();
    _liveSub = null;
    if (mounted) setState(() => _sharing = false);
  }

  Future<void> _stop() async {
    _stopLocal();
    await PcApi.post(PcApi.room('location/stop'));
    _refresh();
  }

  Future<void> _open(Map m) async {
    final uri = 'geo:${m['lat']},${m['lng']}?q=${m['lat']},${m['lng']}(Live location)';
    try {
      await AndroidIntent(action: 'action_view', data: uri).launch();
    } catch (_) {
      if (mounted) toast(context, 'No maps app found.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Live location')),
      body: ListView(padding: EdgeInsets.all(18), children: [
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_sharing ? Icons.my_location_rounded : Icons.location_off_rounded, color: _sharing ? C.success : C.muted, size: 32),
              SizedBox(width: 14),
              Expanded(child: Text(_sharing ? 'You are sharing your location' : 'Not sharing', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            ]),
            SizedBox(height: 14),
            if (!_sharing) ...[
              Text('Share for', style: TextStyle(color: C.muted)),
              SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final m in [15, 60, 240, 480])
                  ChoiceChip(label: Text(m < 60 ? '$m min' : '${m ~/ 60} h'), selected: _minutes == m, onSelected: (_) => setState(() => _minutes = m), selectedColor: C.accent, labelStyle: TextStyle(color: Colors.white)),
              ]),
              SizedBox(height: 16),
              GradientButton(label: 'Start sharing', icon: Icons.near_me_rounded, onTap: _start),
            ] else
              OutlinedButton.icon(onPressed: _stop, icon: Icon(Icons.stop_circle_outlined), label: Text('Stop sharing'), style: OutlinedButton.styleFrom(foregroundColor: C.danger)),
            SizedBox(height: 8),
            Text('Sharing continues while the app stays open.', style: TextStyle(color: C.hint, fontSize: 12)),
          ]),
        ),
        SizedBox(height: 20),
        Text('Shared with you', style: TextStyle(fontWeight: FontWeight.w700, color: C.muted)),
        SizedBox(height: 8),
        if (_others.isEmpty)
          Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Nobody is sharing right now.', style: TextStyle(color: C.hint))))
        else
          for (final m in _others)
            GlassCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.location_on_rounded, color: C.accent2, size: 32),
                title: Text((m['label'] ?? 'Live location').toString()),
                subtitle: Text('${(m['lat'] as num).toStringAsFixed(5)}, ${(m['lng'] as num).toStringAsFixed(5)}', style: TextStyle(fontSize: 12)),
                trailing: TextButton(onPressed: () => _open(m), child: Text('Open map')),
              ),
            ),
      ]),
    );
  }
}
