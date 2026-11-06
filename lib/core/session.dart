import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Everything the app remembers on the phone. The owner's private-chat unlock is NEVER stored (memory only).
class Session {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  // ---- employee login
  static String? get token => _p.getString('token');
  static String get name => _p.getString('name') ?? '';
  static Future<void> save(String token, String name) async {
    await _p.setString('token', token);
    await _p.setString('name', name);
  }

  static Future<void> clearEmployee() async {
    await _p.remove('token');
    await _p.remove('name');
  }

  // ---- private-room login (stays until Sign out)
  static String? get roomToken => _p.getString('room_token');
  static Map<String, dynamic>? get roomInfo {
    final s = _p.getString('room_info');
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveRoom(String token, Map<String, dynamic> info) async {
    await _p.setString('room_token', token);
    await _p.setString('room_info', jsonEncode(info));
  }

  static Future<void> clearRoom() async {
    await _p.remove('room_token');
    await _p.remove('room_info');
  }

  // ---- small settings
  static bool get muted => _p.getBool('muted') ?? false;
  static Future<void> setMuted(bool v) => _p.setBool('muted', v);
  static bool get permsAsked => _p.getBool('perms_asked') ?? false;
  static Future<void> setPermsAsked() => _p.setBool('perms_asked', true);

  /// A random id that stays the same on this phone (used to tell devices apart in the backup).
  static String get deviceId {
    var id = _p.getString('device_id');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(24, (_) => 'abcdef0123456789'[r.nextInt(16)]).join();
      _p.setString('device_id', id);
    }
    return id;
  }

  static int? getInt(String k) => _p.getInt(k);
  static Future<void> setInt(String k, int v) => _p.setInt(k, v);
  static String? getString(String k) => _p.getString(k);
  static Future<void> setString(String k, String v) => _p.setString(k, v);
  static bool getBool(String k, [bool d = false]) => _p.getBool(k) ?? d;
  static Future<void> setBool(String k, bool v) => _p.setBool(k, v);
  static Future<void> remove(String k) => _p.remove(k);
}
