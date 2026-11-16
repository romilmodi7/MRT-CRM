import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/call.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// One voice call, from ringing to hanging up. The voice goes straight from phone to phone (WebRTC);
/// the server is only asked "what is new?" (answer, network addresses, hang up).
class CallScreen extends StatefulWidget {
  final bool pc;          // private chat (true) or employee chat (false)
  final int room;         // private room id
  final int thread;       // employee chat id
  final String name;      // the other person
  final bool video;       // video call (private chat only)
  final bool incoming;
  final int callId;       // incoming only
  final String offer;     // incoming only: the caller's connection offer
  final List ice;         // incoming only: servers used to find a path
  final int ringLeft;     // incoming only: seconds until the caller gives up

  const CallScreen({super.key, required this.pc, this.room = 0, this.thread = 0, required this.name, required this.incoming, this.video = false, this.callId = 0, this.offer = '', this.ice = const [], this.ringLeft = 30});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

enum _Phase { ringing, calling, connecting, live, ended }

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  static const _stun = [
    {'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']}
  ];
  static const _noPath = 'Could not connect. One of the phones is on a network that blocks direct calls.';

  late final CallApi _api = CallApi(widget.pc, widget.room);
  late final AnimationController _pulse = AnimationController(vsync: this, duration: Duration(milliseconds: 1800))..repeat();

  RTCPeerConnection? _pc;
  MediaStream? _local;
  final RTCVideoRenderer _localView = RTCVideoRenderer(), _remoteView = RTCVideoRenderer();
  bool _viewsReady = false, _camOff = false, _remoteVideo = false, _front = true;
  int _id = 0, _after = 0, _secs = 0, _miss = 0;
  _Phase _phase = _Phase.calling;
  String _note = '';
  bool _muted = false, _speaker = false, _closing = false, _remoteSet = false, _answered = false, _polling = false, _sending = false, _rang = false;
  final List<Map<String, dynamic>> _out = [];
  final List<Map> _pendingRemote = [];
  Timer? _poll, _flush, _clock, _ringTimer, _failTimer, _connectTimer;

  @override
  void initState() {
    super.initState();
    Calls.busy = true;
    AwayGuard.hold();   // a private chat must not lock itself in the middle of a call
    _speaker = widget.video;   // a video call starts on the loudspeaker
    if (widget.incoming) {
      _id = widget.callId;
      _phase = _Phase.ringing;
      CallNative.ring(true);
      _setPoll(2);
      _ringTimer = Timer(Duration(seconds: widget.ringLeft + 3), () => _finish('Missed call'));
    } else {
      _startOutgoing();
    }
  }

  @override
  void dispose() {
    _stopAll();
    _pulse.dispose();
    if (_viewsReady) {
      try {
        _localView.srcObject = null;
        _remoteView.srcObject = null;
      } catch (_) {}
    }
    try {
      _localView.dispose();
      _remoteView.dispose();
    } catch (_) {}
    Calls.busy = false;
    AwayGuard.release();
    super.dispose();
  }

  /* ------------------------------------------------------------------ setting up */

  Future<bool> _mic() async {
    try {
      final r = await AwayGuard.run(() => [Permission.microphone, Permission.bluetoothConnect, if (widget.video) Permission.camera].request());
      return (r[Permission.microphone]?.isGranted ?? false) && (!widget.video || (r[Permission.camera]?.isGranted ?? false));
    } catch (_) {
      return false;
    }
  }

  Future<void> _setup(List ice) async {
    await CallNative.service(true, widget.name, widget.video);
    if (widget.video && !_viewsReady) {
      await _localView.initialize();
      await _remoteView.initialize();
      _viewsReady = true;
      CallNative.screenOn(true);
    }
    final pc = await createPeerConnection({'iceServers': ice.isEmpty ? _stun : ice, 'sdpSemantics': 'unified-plan'});
    _pc = pc;
    pc.onIceCandidate = (c) {
      final s = c.candidate;
      if (s == null || s.isEmpty || _closing) return;
      _out.add({'candidate': s, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    };
    pc.onIceConnectionState = _onIce;
    pc.onTrack = (e) {
      if (!widget.video || e.track.kind != 'video' || e.streams.isEmpty) return;
      _remoteView.srcObject = e.streams.first;
      if (mounted) setState(() => _remoteVideo = true);
    };
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
      'video': widget.video ? {'facingMode': 'user', 'width': {'ideal': 640}, 'height': {'ideal': 480}, 'frameRate': {'ideal': 24}} : false,
    });
    _local = stream;
    for (final t in stream.getTracks()) {
      await pc.addTrack(t, stream);
    }
    if (widget.video) {
      _localView.srcObject = stream;
      if (mounted) setState(() {});
    }
    try {
      await Helper.setSpeakerphoneOn(_speaker);
    } catch (_) {}
    CallNative.proximity(!widget.video && !_speaker);
    _flush = Timer.periodic(Duration(milliseconds: 400), (_) => _sendOut());
  }

  Future<void> _startOutgoing() async {
    try {
      if (!await _mic()) {
        _finish(widget.video ? 'Allow the camera and the microphone to make video calls.' : 'Allow the microphone to make calls.');
        return;
      }
      if (_closing) return;
      List ice = const [];
      var ringSecs = 45;
      final r0 = await _api.get('ice');
      if (r0.ok && r0.data is Map) {
        ice = ((r0.data as Map)['ice'] as List?) ?? const [];
        ringSecs = (((r0.data as Map)['ring']) as num?)?.toInt() ?? 45;
      }
      if (_closing) return;
      await _setup(ice);
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      if (_closing) return;
      final r = await _api.post('start', {'sdp': offer.sdp, if (!widget.pc) 'thread': widget.thread, if (widget.video) 'video': true});
      if (!r.ok || r.data is! Map) {
        final busy = r.json['busy'] == true;
        if (busy) CallNative.tone('busy');
        _finish(r.code == 404 ? 'Calls are not set up on the server yet.' : r.msg, tone: !busy);
        return;
      }
      _id = (((r.data as Map)['id']) as num?)?.toInt() ?? 0;
      if (_closing || !mounted) {
        if (_id > 0) _api.post('$_id/end', {'reason': 'cancel'});
        return;
      }
      _rang = true;
      CallNative.tone('ringback');
      setState(() {});
      _setPoll(1);
      _ringTimer = Timer(Duration(seconds: ringSecs), () => _hangup(reason: 'timeout', note: 'No answer'));
    } catch (_) {
      _hangup(note: 'The call could not be started.');
    }
  }

  Future<void> _accept() async {
    if (_answered || _closing) return;
    _answered = true;
    CallNative.ring(false);
    _ringTimer?.cancel();
    setState(() => _phase = _Phase.connecting);
    try {
      if (!await _mic()) {
        _hangup(reason: 'declined', note: widget.video ? 'Allow the camera and the microphone to answer video calls.' : 'Allow the microphone to answer calls.');
        return;
      }
      if (_closing) return;
      await _setup(widget.ice);
      await _pc!.setRemoteDescription(RTCSessionDescription(widget.offer, 'offer'));
      _remoteSet = true;
      await _drainRemote();
      final ans = await _pc!.createAnswer();
      await _pc!.setLocalDescription(ans);
      final r = await _api.post('$_id/answer', {'sdp': ans.sdp});
      if (!r.ok) {
        _finish('The call has ended.');
        return;
      }
      _setPoll(1);
      _connectTimer = Timer(Duration(seconds: 25), () {
        if (_phase != _Phase.live) _hangup(note: _noPath);
      });
    } catch (_) {
      _hangup(note: 'The call could not be answered.');
    }
  }

  /* ------------------------------------------------------------------ talking to the server */

  void _setPoll(int secs) {
    _poll?.cancel();
    _poll = Timer.periodic(Duration(seconds: secs), (_) => _tick());
  }

  Future<void> _sendOut() async {
    if (_sending || _closing || _id == 0 || _out.isEmpty) return;
    _sending = true;
    final batch = List<Map<String, dynamic>>.from(_out.take(30));
    try {
      final r = await _api.post('$_id/signal', {'c': batch});
      if (r.ok) _out.removeRange(0, batch.length > _out.length ? _out.length : batch.length);
    } catch (_) {
    } finally {
      _sending = false;
    }
  }

  Future<void> _addRemote(Map c) async {
    final s = (c['candidate'] ?? '').toString();
    if (s.isEmpty || _pc == null) return;
    try {
      await _pc!.addCandidate(RTCIceCandidate(s, c['sdpMid']?.toString(), (c['sdpMLineIndex'] as num?)?.toInt()));
    } catch (_) {}
  }

  Future<void> _drainRemote() async {
    final list = List<Map>.from(_pendingRemote);
    _pendingRemote.clear();
    for (final c in list) {
      await _addRemote(c);
    }
  }

  Future<void> _tick() async {
    if (_polling || _closing || _id == 0) return;
    _polling = true;
    try {
      final r = await _api.state(_id, _after);
      if (!mounted || _closing) return;
      if (r.code == 404) {
        _finish('Call ended');
        return;
      }
      if (!r.ok || r.data is! Map) {
        if (++_miss > 25) _hangup(note: 'Connection lost');
        return;
      }
      _miss = 0;
      final d = r.data as Map;
      final st = (d['status'] as num?)?.toInt() ?? 0;
      for (final s in ((d['signals'] as List?) ?? const []).whereType<Map>()) {
        final sid = (s['id'] as num?)?.toInt() ?? 0;
        if (sid > _after) _after = sid;
        final c = s['c'];
        if (c is! Map) continue;
        if (_remoteSet) {
          await _addRemote(c);
        } else {
          _pendingRemote.add(c);
        }
      }
      final ans = (d['answer'] ?? '').toString();
      if (!widget.incoming && !_remoteSet && st == 1 && ans.isNotEmpty && _pc != null) {
        _ringTimer?.cancel();
        CallNative.tone('stop');
        await _pc!.setRemoteDescription(RTCSessionDescription(ans, 'answer'));
        _remoteSet = true;
        await _drainRemote();
        if (mounted && _phase != _Phase.live) setState(() => _phase = _Phase.connecting);
        _connectTimer = Timer(Duration(seconds: 25), () {
          if (_phase != _Phase.live) _hangup(note: _noPath);
        });
      }
      if (st >= 2) {
        final busy = st == 5;
        if (busy) CallNative.tone('busy');
        _finish(switch (st) { 3 => 'Call declined', 4 => widget.incoming ? 'Missed call' : 'No answer', 5 => '${widget.name} is on another call', 6 => 'Missed call', _ => 'Call ended' }, tone: !busy);
      }
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  void _onIce(RTCIceConnectionState s) {
    if (_closing || !mounted) return;
    if (s == RTCIceConnectionState.RTCIceConnectionStateConnected || s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
      _failTimer?.cancel();
      _connectTimer?.cancel();
      if (_phase != _Phase.live) {
        CallNative.tone('stop');
        _clock ??= Timer.periodic(Duration(seconds: 1), (_) {
          if (mounted) setState(() => _secs++);
        });
        _setPoll(3);
      }
      setState(() {
        _phase = _Phase.live;
        _note = '';
      });
    } else if (s == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
      setState(() => _note = 'Reconnecting…');
      _failTimer?.cancel();
      _failTimer = Timer(Duration(seconds: 15), () => _hangup(note: 'Call dropped (network lost)'));
    } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
      if (_phase == _Phase.live) {
        _failTimer ??= Timer(Duration(seconds: 6), () => _hangup(note: 'Call dropped (network lost)'));
      } else {
        _hangup(note: _noPath);
      }
    }
  }

  /* ------------------------------------------------------------------ ending */

  Future<void> _hangup({String reason = '', String? note}) async {
    if (_closing) return;
    final id = _id;
    _finish(note ?? 'Call ended');
    if (id > 0) {
      try {
        await _api.post('$id/end', {'reason': reason});
      } catch (_) {}
    }
  }

  void _stopAll() {
    for (final t in [_poll, _flush, _clock, _ringTimer, _failTimer, _connectTimer]) {
      t?.cancel();
    }
    CallNative.ring(false);
    CallNative.proximity(false);
    CallNative.screenOn(false);
    final pc = _pc, st = _local;
    _pc = null;
    _local = null;
    try {
      st?.getTracks().forEach((t) => t.stop());
      st?.dispose();
    } catch (_) {}
    try {
      pc?.close();
    } catch (_) {}
    CallNative.service(false);
  }

  void _finish(String note, {bool tone = true}) {
    if (_closing) return;
    _closing = true;
    if (tone) CallNative.tone('end');
    _stopAll();
    if (mounted) {
      setState(() {
        _phase = _Phase.ended;
        _note = note;
      });
    }
    Future.delayed(Duration(milliseconds: note.length > 40 ? 3200 : 1400), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    try {
      _local?.getAudioTracks().forEach((t) => t.enabled = !_muted);
    } catch (_) {}
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speaker = !_speaker);
    try {
      await Helper.setSpeakerphoneOn(_speaker);
    } catch (_) {}
    CallNative.proximity(!widget.video && !_speaker);
  }

  void _toggleCam() {
    setState(() => _camOff = !_camOff);
    try {
      _local?.getVideoTracks().forEach((t) => t.enabled = !_camOff);
    } catch (_) {}
  }

  Future<void> _flipCam() async {
    try {
      final t = _local?.getVideoTracks();
      if (t == null || t.isEmpty) return;
      await Helper.switchCamera(t.first);
      if (mounted) setState(() => _front = !_front);
    } catch (_) {}
  }

  /* ------------------------------------------------------------------ screen */

  String get _clockText {
    final h = _secs ~/ 3600, m = (_secs % 3600) ~/ 60, s = _secs % 60;
    final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  String get _status => switch (_phase) {
        _Phase.ringing => widget.video ? 'Incoming video call' : 'Incoming voice call',
        _Phase.calling => _rang ? 'Ringing…' : 'Calling…',
        _Phase.connecting => 'Connecting…',
        _Phase.live => _note.isNotEmpty ? _note : _clockText,
        _Phase.ended => _note,
      };

  Widget _round({required IconData icon, required String label, required VoidCallback? onTap, Color? bg, Color fg = Colors.white, double size = 64, bool on = false}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Material(
        color: bg ?? (on ? Colors.white : Color(0x29FFFFFF)),
        shape: CircleBorder(),
        child: InkWell(
          customBorder: CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Icon(icon, color: bg == null && on ? Color(0xFF1E2A5A) : fg, size: size * .44)),
        ),
      ),
      SizedBox(height: 8),
      Text(label, style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _ring(double t) {
    final v = (_pulse.value + t) % 1;
    return Container(
      width: 132 + 110 * v,
      height: 132 + 110 * v,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withAlpha((70 * (1 - v)).round()), width: 2)),
    );
  }

  /// Video call: the other person fills the screen, my own camera is the small picture, the buttons float on top.
  Widget _videoBody() {
    final live = _phase == _Phase.live && _remoteVideo;
    final small = _round;
    return Stack(fit: StackFit.expand, children: [
      // the big picture: the other person when connected, my own camera while it rings
      Container(color: Colors.black),
      if (live)
        RTCVideoView(_remoteView, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
      else if (!_camOff)
        RTCVideoView(_localView, mirror: _front, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
      // soft dark edges so the white text and buttons stay readable
      IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xB3000000), Color(0x00000000), Color(0x00000000), Color(0xCC000000)], stops: [0, .22, .6, 1], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        ),
      ),
      SafeArea(
        child: Column(children: [
          SizedBox(height: 14),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text(_status, maxLines: 2, style: TextStyle(color: _phase == _Phase.live && _note.isEmpty ? Color(0xFF36E0A6) : Colors.white70, fontSize: 14.5, fontWeight: FontWeight.w600)),
                ]),
              ),
              // my own camera (small) once the other person is on screen
              if (live)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 104,
                    height: 148,
                    decoration: BoxDecoration(color: Color(0xFF111827), border: Border.all(color: Colors.white24)),
                    child: _camOff ? Icon(Icons.videocam_off_rounded, color: Colors.white54) : RTCVideoView(_localView, mirror: _front, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                  ),
                ),
            ]),
          ),
          Spacer(),
          if (_phase == _Phase.ringing)
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              small(icon: Icons.call_end_rounded, label: 'Decline', bg: Color(0xFFE5484D), size: 72, onTap: () => _hangup(reason: 'declined', note: 'Call declined')),
              small(icon: Icons.videocam_rounded, label: 'Accept', bg: Color(0xFF16A34A), size: 72, onTap: _accept),
            ])
          else ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              small(icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded, label: _muted ? 'Unmute' : 'Mute', on: _muted, size: 56, onTap: _local == null ? null : _toggleMute),
              small(icon: _camOff ? Icons.videocam_off_rounded : Icons.videocam_rounded, label: _camOff ? 'Camera off' : 'Camera', on: _camOff, size: 56, onTap: _local == null ? null : _toggleCam),
              small(icon: Icons.cameraswitch_rounded, label: 'Flip', size: 56, onTap: _local == null || _camOff ? null : _flipCam),
              small(icon: Icons.volume_up_rounded, label: 'Speaker', on: _speaker, size: 56, onTap: _local == null ? null : _toggleSpeaker),
            ]),
            SizedBox(height: 22),
            small(icon: Icons.call_end_rounded, label: 'End', bg: Color(0xFFE5484D), size: 72, onTap: () => _hangup(reason: 'cancel')),
          ],
          SizedBox(height: 30),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _phase == _Phase.ringing || _phase == _Phase.calling || _phase == _Phase.connecting;
    return PopScope(
      canPop: _phase == _Phase.ended,
      child: Scaffold(
        backgroundColor: Color(0xFF0A1030),
        body: widget.video && _viewsReady && _phase != _Phase.ended ? _videoBody() : Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1B1464), Color(0xFF0A1030), Color(0xFF06122B)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: SafeArea(
            child: Column(children: [
              SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.lock_rounded, size: 13, color: Colors.white54),
                SizedBox(width: 6),
                Text(widget.video ? 'Private video call' : (widget.pc ? 'Private voice call' : 'MRT CRM voice call'), style: TextStyle(color: Colors.white54, fontSize: 12.5, letterSpacing: .4)),
              ]),
              Spacer(),
              SizedBox(
                width: 260,
                height: 260,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Stack(alignment: Alignment.center, children: [
                    if (waiting) _ring(0),
                    if (waiting) _ring(.5),
                    Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x667C6CFF), blurRadius: 44, spreadRadius: 4)]),
                      child: Avatar(widget.name, size: 128),
                    ),
                  ]),
                ),
              ),
              SizedBox(height: 22),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 28),
                child: Text(widget.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
              ),
              SizedBox(height: 10),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 34),
                child: AnimatedSwitcher(
                  duration: Duration(milliseconds: 200),
                  child: Text(_status, key: ValueKey(_status), textAlign: TextAlign.center, style: TextStyle(color: _phase == _Phase.live && _note.isEmpty ? Color(0xFF36E0A6) : Colors.white70, fontSize: _phase == _Phase.live && _note.isEmpty ? 20 : 15.5, fontWeight: FontWeight.w600, height: 1.4)),
                ),
              ),
              Spacer(flex: 2),
              if (_phase == _Phase.ringing)
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _round(icon: Icons.call_end_rounded, label: 'Decline', bg: Color(0xFFE5484D), size: 72, onTap: () => _hangup(reason: 'declined', note: 'Call declined')),
                  _round(icon: Icons.call_rounded, label: 'Accept', bg: Color(0xFF16A34A), size: 72, onTap: _accept),
                ])
              else if (_phase != _Phase.ended)
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _round(icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded, label: _muted ? 'Unmute' : 'Mute', on: _muted, onTap: _local == null ? null : _toggleMute),
                  _round(icon: Icons.call_end_rounded, label: 'End', bg: Color(0xFFE5484D), size: 76, onTap: () => _hangup(reason: 'cancel')),
                  _round(icon: Icons.volume_up_rounded, label: 'Speaker', on: _speaker, onTap: _local == null ? null : _toggleSpeaker),
                ])
              else
                SizedBox(height: 100),
              SizedBox(height: 44),
            ]),
          ),
        ),
      ),
    );
  }
}
