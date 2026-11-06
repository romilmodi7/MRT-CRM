import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import 'config.dart';
import 'session.dart';

/// One answer from the server: {status, data, msg} (+ the HTTP code).
class ApiRes {
  final int code;
  final Map<String, dynamic> json;
  final Map<String, String> headers;
  ApiRes(this.code, this.json, [this.headers = const {}]);

  factory ApiRes.offline() => ApiRes(0, {'status': false, 'msg': 'No internet connection. Please try again.'});

  factory ApiRes.from(http.Response r) {
    Map<String, dynamic> j = {};
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map<String, dynamic>) j = d;
    } catch (_) {}
    return ApiRes(r.statusCode, j, r.headers);
  }

  bool get ok => json['status'] == true || json['ok'] == true;
  dynamic get data => json['data'];
  bool get needCode => json['needCode'] == true;
  bool get locked => json['locked'] == true;

  String get msg {
    final m = json['msg'];
    if (m is String && m.isNotEmpty) return m;
    final e = json['errors'];
    if (e is Map && e.isNotEmpty) {
      final f = e.values.first;
      if (f is List && f.isNotEmpty) return f.first.toString();
    }
    final mm = json['message'];
    if (mm is String && mm.isNotEmpty) return mm;
    return code == 0 ? 'No internet connection. Please try again.' : 'Something went wrong. Please try again.';
  }
}

String mimeOf(String path) => lookupMimeType(path) ?? 'application/octet-stream';

/// Employee chat / CRM API (Bearer login).
class Api {
  static void Function()? onUnauthorized;

  static Map<String, String> _h({bool json = true}) {
    final t = Session.token;
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (t != null) 'Authorization': 'Bearer $t',
    };
  }

  static Future<ApiRes> _run(Future<http.Response> Function() f, {int secs = 40}) async {
    try {
      final r = await f().timeout(Duration(seconds: secs));
      final res = ApiRes.from(r);
      if (res.code == 401 && !res.needCode && Session.token != null) onUnauthorized?.call();
      return res;
    } catch (_) {
      return ApiRes.offline();
    }
  }

  static Future<ApiRes> get(String path) => _run(() => http.get(Uri.parse(kApi + path), headers: _h()));

  static Future<ApiRes> post(String path, [Map<String, dynamic>? body]) =>
      _run(() => http.post(Uri.parse(kApi + path), headers: _h(), body: jsonEncode(body ?? {})));

  /// Login has no token yet.
  static Future<ApiRes> login(String user, String pass, String? code) => _run(() => http.post(
        Uri.parse('${kApi}login'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: jsonEncode({'username': user, 'password': pass, if (code != null && code.isNotEmpty) 'code': code, 'device': 'Android app'}),
      ));

  /// Files are streamed from disk (never loaded into memory).
  static Future<ApiRes> upload(String path, Map<String, String> fields, List<File> files, {String field = 'files[]'}) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse(kApi + path));
      req.headers.addAll(_h(json: false));
      req.fields.addAll(fields);
      for (final f in files) {
        req.files.add(await http.MultipartFile.fromPath(field, f.path, contentType: MediaType.parse(mimeOf(f.path))));
      }
      final s = await req.send().timeout(Duration(minutes: 8));
      final res = ApiRes.from(await http.Response.fromStream(s));
      if (res.code == 401 && Session.token != null) onUnauthorized?.call();
      return res;
    } catch (_) {
      return ApiRes.offline();
    }
  }

  static Future<Uint8List?> bytes(String path) async {
    try {
      final r = await http.get(Uri.parse(kApi + path), headers: _h(json: false)).timeout(Duration(seconds: 60));
      return r.statusCode == 200 ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }
}

/// Private chat API. Owner = token in memory only (unlocked with the PIN). Guest = room login kept until sign out.
class PcApi {
  static String? token;
  static bool owner = false;
  static int roomId = 0;
  static void Function(String why)? onLocked;

  static void useOwner(String t) {
    token = t;
    owner = true;
  }

  static void useGuest(String t) {
    token = t;
    owner = false;
  }

  static void forget() {
    token = null;
    owner = false;
    roomId = 0;
  }

  /// Path of a room endpoint for the current person.
  static String room(String p) => owner ? 'rooms/$roomId/api/$p' : 'room/api/$p';

  static Map<String, String> _h({bool json = true}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (token != null) 'X-PC-Token': token!,
      };

  static ApiRes _handle(http.Response r) {
    final res = ApiRes.from(r);
    final t = res.headers['x-pc-token'];
    if (t != null && owner) token = t;
    if (res.code == 401 && res.locked) onLocked?.call(res.msg);
    return res;
  }

  static Future<ApiRes> _run(Future<http.Response> Function() f, {int secs = 40}) async {
    try {
      return _handle(await f().timeout(Duration(seconds: secs)));
    } catch (_) {
      return ApiRes.offline();
    }
  }

  static Uri _u(String path, [Map<String, String>? q]) => Uri.parse(kPcApi + path).replace(queryParameters: q);

  static Future<ApiRes> get(String path, [Map<String, String>? q]) => _run(() => http.get(_u(path, q), headers: _h()));

  static Future<ApiRes> post(String path, [Map<String, dynamic>? body]) =>
      _run(() => http.post(_u(path), headers: _h(), body: jsonEncode(body ?? {})));

  static Future<ApiRes> delete(String path, [Map<String, dynamic>? body]) =>
      _run(() => http.delete(_u(path), headers: _h(), body: jsonEncode(body ?? {})));

  /// Public: no token yet.
  static Future<ApiRes> roomLogin(String user, String pass) => _run(() => http.post(
        _u('room-login'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: jsonEncode({'username': user, 'password': pass}),
      ));

  /// Needs the employee Bearer login (admin 3) + the PIN / master password.
  static Future<ApiRes> unlock(String q) => _run(() => http.post(
        _u('unlock'),
        headers: Api._h(),
        body: jsonEncode({'q': q}),
      ));

  static Future<ApiRes> upload(String path, Map<String, String> fields, List<File> files, {String field = 'file'}) async {
    try {
      final req = http.MultipartRequest('POST', _u(path));
      req.headers.addAll(_h(json: false));
      req.fields.addAll(fields);
      for (final f in files) {
        req.files.add(await http.MultipartFile.fromPath(field, f.path, contentType: MediaType.parse(mimeOf(f.path))));
      }
      final s = await req.send().timeout(Duration(minutes: 10));
      return _handle(await http.Response.fromStream(s));
    } catch (_) {
      return ApiRes.offline();
    }
  }

  static Future<Uint8List?> bytes(String path, [Map<String, String>? q]) async {
    try {
      final r = await http.get(_u(path, q), headers: _h(json: false)).timeout(Duration(minutes: 3));
      if (r.statusCode == 200) {
        final t = r.headers['x-pc-token'];
        if (t != null && owner) token = t;
        return r.bodyBytes;
      }
      if (r.statusCode == 401) onLocked?.call('Locked');
      return null;
    } catch (_) {
      return null;
    }
  }
}
