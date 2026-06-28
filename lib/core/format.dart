/// 把 ISO8601 时间转成「x 分钟前 / x 小时前 / x 天前 / 年-月-日」。
String relativeTime(String iso) {
  if (iso.isEmpty) return '';
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.isNegative) return '刚刚';
  if (d.inMinutes < 1) return '刚刚';
  if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
  if (d.inHours < 24) return '${d.inHours} 小时前';
  if (d.inDays < 30) return '${d.inDays} 天前';
  final lt = t.toLocal();
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${lt.year}-${p2(lt.month)}-${p2(lt.day)}';
}

/// mm:ss 时长格式。
String fmtDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
