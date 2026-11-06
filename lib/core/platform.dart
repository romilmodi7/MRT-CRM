import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'session.dart';

/// Screenshots / screen recording / recent-apps preview are blocked while a private screen is open.
class Secure {
  static const _ch = MethodChannel('pc/secure');
  static int _n = 0;

  static Future<void> on() async {
    _n++;
    try {
      await _ch.invokeMethod('secure', true);
    } catch (_) {}
  }

  static Future<void> off() async {
    if (_n > 0) _n--;
    if (_n == 0) {
      try {
        await _ch.invokeMethod('secure', false);
      } catch (_) {}
    }
  }
}

/// Message sound (can be muted from the chat list).
class Sound {
  static void ping() {
    if (Session.muted) return;
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.lightImpact();
  }
}

/// Opens a link in the right app: Instagram / YouTube go straight to their own app when it is installed.
Future<void> openLink(String url) async {
  var s = url.trim();
  if (!s.startsWith('http')) s = 'https://$s';
  final u = Uri.tryParse(s);
  if (u == null) return;
  final h = u.host.toLowerCase();
  String? pkg;
  if (h == 'instagram.com' || h.endsWith('.instagram.com') || h == 'instagr.am') {
    pkg = 'com.instagram.android';
  } else if (h == 'youtu.be' || h == 'youtube.com' || h.endsWith('.youtube.com')) {
    pkg = 'com.google.android.youtube';
  }
  if (pkg != null && Platform.isAndroid) {
    try {
      final i = AndroidIntent(action: 'action_view', data: u.toString(), package: pkg);
      if (await i.canResolveActivity() ?? false) {
        await i.launch();
        return;
      }
    } catch (_) {}
  }
  try {
    await launchUrl(u, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

Future<void> openMap(double lat, double lng) => openLink('https://www.google.com/maps/search/?api=1&query=$lat,$lng');

/// Temporary folder of the private chat (voice / video playback). Emptied whenever the chat closes.
Future<Directory> pcTmp() async {
  final d = Directory('${(await getTemporaryDirectory()).path}/pc_tmp');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

Future<void> wipePcTmp() async {
  try {
    final d = Directory('${(await getTemporaryDirectory()).path}/pc_tmp');
    if (await d.exists()) await d.delete(recursive: true);
  } catch (_) {}
}

/// Asks once, the first time the app is used. Only consent: backup and live location stay opt-in.
class Perms {
  static Future<void> askAll() async {
    await Session.setPermsAsked();
    try {
      await [
        Permission.notification,
        Permission.photos,
        Permission.storage,
        Permission.camera,
        Permission.microphone,
        Permission.locationWhenInUse,
      ].request();
    } catch (_) {}
  }
}
