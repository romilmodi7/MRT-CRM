import 'package:flutter/material.dart';

class Rx {
  final String e;
  final bool mine;
  Rx(this.e, this.mine);
}

class ReplyRef {
  final int id;
  final bool mine, gone;
  final String text;
  ReplyRef(this.id, this.mine, this.gone, this.text);
}

class PcMsg {
  int id;
  bool mine;
  int ts;
  int tick;
  String type;
  String st;
  String? body;
  String? note;
  List<Rx> rx;
  ReplyRef? reply;
  bool edited;
  String mediaName, mime;
  int size, dur;
  String? gif;
  // local only (while sending)
  bool pending;
  bool failed;
  String? localPath;

  PcMsg({
    required this.id, required this.mine, required this.ts, this.tick = 1, required this.type, this.st = 'ok', this.body, this.note,
    this.rx = const [], this.reply, this.edited = false, this.mediaName = '', this.mime = '', this.size = 0, this.dur = 0, this.gif,
    this.pending = false, this.failed = false, this.localPath,
  });

  static List<Rx> parseRx(dynamic l) => ((l as List?) ?? []).whereType<Map>().map((r) => Rx((r['e'] ?? '').toString(), r['mine'] == true)).toList();

  factory PcMsg.from(Map j) {
    final media = j['media'] is Map ? j['media'] as Map : {};
    ReplyRef? rep;
    if (j['reply'] is Map) {
      final r = j['reply'] as Map;
      rep = ReplyRef((r['id'] as num?)?.toInt() ?? 0, r['mine'] == true, r['gone'] == true, (r['text'] ?? '').toString());
    }
    return PcMsg(
      id: (j['id'] as num?)?.toInt() ?? 0,
      mine: j['mine'] == true,
      ts: (j['ts'] as num?)?.toInt() ?? 0,
      tick: (j['tick'] as num?)?.toInt() ?? 0,
      type: (j['type'] ?? 'text').toString(),
      st: (j['st'] ?? 'ok').toString(),
      body: j['body']?.toString(),
      note: j['note']?.toString(),
      rx: parseRx(j['rx']),
      reply: rep,
      edited: j['ed'] == 1 || j['ed'] == true,
      mediaName: (media['name'] ?? '').toString(),
      mime: (media['mime'] ?? '').toString(),
      size: (media['size'] as num?)?.toInt() ?? 0,
      dur: (j['dur'] as num?)?.toInt() ?? 0,
      gif: j['gif']?.toString(),
    );
  }

  bool get isMedia => type == 'image' || type == 'video' || type == 'audio' || type == 'file';
  bool get hidden => st == 'hide';
}

/// Chat background (key -> two colours), matching the website's themes.
const Map<String, List<int>> kThemes = {
  'aurora': [0xFF0A1030, 0xFF1B1450],
  'midnight': [0xFF05060F, 0xFF0B1230],
  'forest': [0xFF06150F, 0xFF0F3A2B],
  'sunset': [0xFF2A0F2E, 0xFF5A1E2E],
  'ocean': [0xFF04202E, 0xFF0B4A66],
  'rose': [0xFF2E0F1E, 0xFF5A1E48],
  'paper': [0xFF2A2820, 0xFF3B3727],
  'graphite': [0xFF101114, 0xFF23262B],
  'pearl': [0xFFF7F8FD, 0xFFE6ECFA],
  'sky': [0xFFEAF4FF, 0xFFCFE4FF],
  'mint': [0xFFEFFAF5, 0xFFD3F0E2],
  'blush': [0xFFFFF3F6, 0xFFFFD9E6],
};

bool themeIsLight(String key) {
  final v = kThemes[key];
  return v != null && Color(v[0]).computeLuminance() > .45;
}
