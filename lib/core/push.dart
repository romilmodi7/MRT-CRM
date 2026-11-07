import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/conversation_screen.dart';
import '../screens/threads_screen.dart';
import 'api.dart';
import 'fcm_config.dart';
import 'session.dart';
import 'theme.dart';

/// Phone notifications (Firebase Cloud Messaging).
///  - app closed / in background: Android shows the notification by itself (sound, photo, urgent style are chosen by the server)
///  - app open: a small banner at the top + a short sound (unless the sound is switched off)
///  - the phone registers its address with the server for the employee login or the private room login
class Push {
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();
  static final navKey = GlobalKey<NavigatorState>();

  /// The chat that is open on screen ("chat:12" or "pc:3"): no banner for it.
  static String here = '';

  static bool _ready = false;
  static String? _token;
  static Map<String, dynamic>? _tap;

  static bool get configured => kFcmApiKey.isNotEmpty && kFcmAppId.isNotEmpty && kFcmSenderId.isNotEmpty && kFcmProjectId.isNotEmpty;

  static Future<void> init() async {
    if (!configured || _ready) return;
    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(apiKey: kFcmApiKey, appId: kFcmAppId, messagingSenderId: kFcmSenderId, projectId: kFcmProjectId),
      );
      final m = FirebaseMessaging.instance;
      // The notification permission is asked once by Perms.askAll (asking here as well made both requests wait for each other)
      _ready = true;
      _token = await m.getToken();
      m.onTokenRefresh.listen((t) {
        _token = t;
        sync();
      });
      FirebaseMessaging.onMessage.listen(_foreground);
      FirebaseMessaging.onMessageOpenedApp.listen((r) {
        _tap = Map<String, dynamic>.from(r.data);
        openPending();
      });
      final first = await m.getInitialMessage();
      if (first != null) _tap = Map<String, dynamic>.from(first.data);
    } catch (_) {}
  }

  /// Tells the server where to send this person's notifications. Safe to call as often as needed.
  static Future<void> sync() async {
    final t = _token;
    if (!_ready || t == null) return;
    final body = {'token': t, 'muted': Session.muted ? '1' : '0', 'device': Session.deviceId};
    try {
      if (Session.token != null) {
        await Api.post('push', body);
      } else if (Session.roomToken != null) {
        await PcApi.post('room/push', body);
      }
    } catch (_) {}
  }

  /// Log out / sign out: this phone stops getting this person's notifications.
  static Future<void> off() async {
    final t = _token;
    if (!_ready || t == null) return;
    try {
      if (Session.token != null) {
        await Api.post('push/off', {'token': t});
      } else if (Session.roomToken != null) {
        await PcApi.post('room/push/off', {'token': t});
      }
    } catch (_) {}
  }

  static void _foreground(RemoteMessage r) {
    try {
      final d = r.data;
      final key = d['kind'] == 'private' ? 'pc:${d['room']}' : 'chat:${d['thread']}';
      if (here == key) return;
      final title = r.notification?.title ?? '';
      final body = r.notification?.body ?? '';
      if (title.isEmpty && body.isEmpty) return;
      final urgent = d['urgent'] == '1';
      if (!Session.muted) SystemSound.play(SystemSoundType.alert);
      HapticFeedback.mediumImpact();
      final m = messengerKey.currentState;
      if (m == null) return;
      m.hideCurrentSnackBar();
      m.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: urgent ? 9 : 5),
        backgroundColor: urgent ? Color(0xFFB91C1C) : Color(0xFF1E2A5A),
        margin: EdgeInsets.fromLTRB(12, 0, 12, 12),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
          if (body.isNotEmpty) Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white70)),
        ]),
        action: d['kind'] == 'chat'
            ? SnackBarAction(
                label: 'OPEN',
                textColor: Colors.white,
                onPressed: () {
                  _tap = Map<String, dynamic>.from(d);
                  openPending();
                })
            : null,
      ));
    } catch (_) {}
  }

  /// A tapped notification opens its chat (employee chat). Private chat just opens the app.
  static void openPending() {
    final d = _tap;
    _tap = null;
    if (d == null || d['kind'] != 'chat' || Session.token == null) return;
    final id = int.tryParse((d['thread'] ?? '').toString()) ?? 0;
    final nav = navKey.currentState;
    if (id <= 0 || nav == null) return;
    nav.push(MaterialPageRoute(builder: (_) => ConversationScreen(thread: Thread(id, (d['title'] ?? 'Chat').toString(), '', '', 0, ''))));
  }
}
