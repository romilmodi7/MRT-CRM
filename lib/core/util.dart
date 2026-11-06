import 'dart:async';

String two(int n) => n < 10 ? '0$n' : '$n';

String clock(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String dayLabel(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  final n = DateTime.now();
  final a = DateTime(d.year, d.month, d.day);
  final b = DateTime(n.year, n.month, n.day);
  final diff = b.difference(a).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

String agoLabel(int? ts) {
  if (ts == null) return '';
  final s = DateTime.now().millisecondsSinceEpoch ~/ 1000 - ts;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60} min ago';
  if (s < 86400) return clock(ts);
  return dayLabel(ts);
}

String fmtSize(num b) {
  if (b < 1024) return '${b.toInt()} B';
  if (b < 1048576) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(2)} GB';
}

String mmss(int secs) => '${secs ~/ 60}:${two(secs % 60)}';

class Debouncer {
  final Duration d;
  Timer? _t;
  Debouncer(this.d);
  void run(void Function() f) {
    _t?.cancel();
    _t = Timer(d, f);
  }

  void cancel() => _t?.cancel();
}

final RegExp kUrlRe = RegExp(r'((?:https?:\/\/|www\.)[^\s<]+[^\s<.,;:!?)\]]|(?:[a-z0-9-]+\.)*(?:instagram\.com|youtube\.com|youtu\.be)\/[^\s<]*[^\s<.,;:!?)\]])', caseSensitive: false);
