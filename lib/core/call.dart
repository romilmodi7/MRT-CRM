import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/call_screen.dart';
import 'api.dart';
import 'push.dart';
import 'session.dart';
import 'theme.dart';

/// Small helpers that only Android itself can do: keep the call alive when the app is in the background,
/// ring like a phone, play the "ringing" tone in the earpiece, switch the screen off at the ear.
class CallNative {
  static const _ch = MethodChannel('mrt/call');

  static Future<void> _c(String m, [dynamic a]) async {
    try {
      await _ch.invokeMethod(m, a);
    } catch (_) {}
  }

  /// "Call in progress" notification + microphone allowed while the app is in the background.
  static Future<void> service(bool on, [String name = '', bool video = false]) => _c('service', {'on': on, 'name': name, 'video': video});

  /// Keep the screen on (video call).
  static Future<void> screenOn(bool on) => _c('screen', on);

  /// The phone's own ringtone + vibration (incoming call while the app is open).
  static Future<void> ring(bool on) => _c('ring', on);

  /// ringback (the caller hears it while the other phone rings) | busy | end | stop
  static Future<void> tone(String t) => _c('tone', t);

  /// Screen off while the phone is held to the ear.
  static Future<void> proximity(bool on) => _c('proximity', on);
}

/// The server paths of a call: employee chat, or a private room (owner / guest).
class CallApi {
  final bool pc;
  final int room;
  const CallApi(this.pc, this.room);

  String _p(String p) => pc ? (PcApi.owner ? 'rooms/$room/api/call/$p' : 'room/api/call/$p') : 'call/$p';

  Future<ApiRes> get(String p) => pc ? PcApi.get(_p(p)) : Api.get(_p(p));
  Future<ApiRes> post(String p, [Map<String, dynamic>? b]) => pc ? PcApi.post(_p(p), b) : Api.post(_p(p), b);
  Future<ApiRes> state(int id, int after) => pc ? PcApi.get(_p('$id'), {'after': '$after'}) : Api.get('call/$id?after=$after');
}

/// Starts calls and notices incoming ones (asks the server every few seconds while the app is open,
/// and at once when a call notification arrives or is tapped).
class Calls {
  /// A call screen is open: no second call can start or come in.
  static bool busy = false;

  /// The app is on screen.
  static bool fg = true;

  static Timer? _t;
  static bool _checking = false;

  static void watch() {
    _t ??= Timer.periodic(Duration(seconds: 5), (_) => check());
  }

  static Future<void> check() async {
    if (busy || _checking || !fg) return;
    _checking = true;
    try {
      if (Session.token != null) {
        if (_open(await Api.get('call/incoming'), false)) return;
      }
      if (PcApi.token != null) {
        _open(await PcApi.get(PcApi.owner ? 'call/incoming' : 'room/api/call/incoming'), true);
      }
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  static bool _open(ApiRes r, bool pc) {
    if (busy || !r.ok || r.data is! Map) return false;
    final d = r.data as Map;
    final id = (d['id'] as num?)?.toInt() ?? 0;
    final offer = (d['offer'] ?? '').toString();
    final nav = Push.navKey.currentState;
    if (id <= 0 || offer.isEmpty || nav == null) return false;
    busy = true;
    final ref = (d['ref'] as num?)?.toInt() ?? 0;
    nav.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CallScreen(
        pc: pc,
        room: pc ? (ref > 0 ? ref : PcApi.roomId) : 0,
        thread: pc ? 0 : ref,
        name: (d['name'] ?? 'Call').toString(),
        video: pc && d['video'] == true,
        incoming: true,
        callId: id,
        offer: offer,
        ice: (d['ice'] as List?) ?? const [],
        ringLeft: (d['left'] as num?)?.toInt() ?? 30,
      ),
    ));
    return true;
  }

  /// Call the other person of a chat.
  static Future<void> dial(BuildContext c, {required bool pc, int room = 0, int thread = 0, required String name, bool video = false}) async {
    if (busy) {
      toast(c, 'You are already on a call.');
      return;
    }
    busy = true;
    await Navigator.of(c).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CallScreen(pc: pc, room: room, thread: thread, name: name, incoming: false, video: video),
    ));
  }
}
