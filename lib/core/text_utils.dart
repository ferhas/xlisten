/// 纯文本逻辑层：从 scrape_x.py / build_audio.py 精确移植，保持行为一致。
/// 这一层不依赖 Flutter，可独立单元测试。
library;

final RegExp _urlRe = RegExp(r'https?://\S+');
final RegExp _asciiFragRe = RegExp(r'[A-Za-z0-9_\-./]{15,}');
final RegExp _tagRe = RegExp(r'[#@]\S+');
final RegExp _collapseRe = RegExp(r'[，。、\s ]{2,}');
final RegExp _numRe = RegExp(r'[\d,]+');

bool _isCjk(int rune) => rune >= 0x4E00 && rune <= 0x9FFF; // 一 .. 鿿
bool _isAsciiAlpha(int rune) =>
    (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);

/// 去掉链接（X 常把长 URL 拆成多行，仅去 http 前缀不够，再去长 ASCII 碎片）。
String stripUrls(String t) {
  t = t.replaceAll(_urlRe, ' ');
  t = t.replaceAll(_asciiFragRe, ' ');
  return t;
}

({int cjk, int lat}) _counts(String t) {
  var cjk = 0;
  var lat = 0;
  for (final r in t.runes) {
    if (_isCjk(r)) {
      cjk++;
    } else if (_isAsciiAlpha(r)) {
      lat++;
    }
  }
  return (cjk: cjk, lat: lat);
}

/// 语言判定（同 scrape_x.detect_lang）：zh / en / other。用原始文本统计。
String detectLang(String text) {
  final c = _counts(text);
  if (c.cjk >= 4 && c.cjk >= c.lat) return 'zh';
  if (c.lat >= 10 && c.lat > c.cjk * 2) return 'en';
  return 'other';
}

/// 是否“真英文”（同 scrape_x.is_english）：先剥链接、话题/提及，再按字母占比判定。
bool isEnglish(String t) {
  final stripped = stripUrls(t).replaceAll(_tagRe, ' ');
  final c = _counts(stripped);
  return c.lat >= 10 && c.lat > c.cjk * 2;
}

/// 朗读前清洗（同 build_audio.clean）：剥链接、不间断空格→空格、换行→“，”、折叠标点、去首尾标点。
String clean(String t) {
  t = stripUrls(t);
  t = t.replaceAll(' ', ' ').replaceAll('\n', '，');
  t = t.replaceAll(_collapseRe, '，');
  return _trimChars(t, ' ，。');
}

String _trimChars(String s, String chars) {
  var start = 0;
  var end = s.length;
  while (start < end && chars.contains(s[start])) {
    start++;
  }
  while (end > start && chars.contains(s[end - 1])) {
    end--;
  }
  return s.substring(start, end);
}

/// 互动数解析（同 scrape_x.num）：从 aria-label 里抽出数字。
int? parseNum(String? s) {
  if (s == null) return null;
  final m = _numRe.firstMatch(s);
  if (m == null) return null;
  return int.tryParse(m.group(0)!.replaceAll(',', ''));
}

/// 去重 key（同 scrape_x.itemkey）：优先 url，否则 handle|正文前 40 字。
String itemKey(String handle, String text, String url) {
  if (url.isNotEmpty) return url;
  final head = text.length > 40 ? text.substring(0, 40) : text;
  return '$handle|$head';
}

/// 朗读文本（同 build_audio.make_lines 的单条逻辑）：返回 `作者：正文`；
/// 清洗后 ≤10 字（MIN_CHARS）返回 null 表示应跳过。
String? makeReadingText(String author, String text) {
  final body = clean(text);
  if (body.runes.length < 15) return null; // 过滤 15 字以下的短内容
  return '${shortAuthor(author)}：$body';
}

/// 朗读用的「短作者名」:砍掉括号/竖线后的描述性后缀(如「立党（劝人卖房/学CS…）」),
/// 再封顶 14 字,避免名字太长把开头读很久。
String shortAuthor(String author) {
  var s = author.trim();
  final m = RegExp(r'[（(｜|【\[]').firstMatch(s);
  if (m != null && m.start >= 1) s = s.substring(0, m.start).trim();
  final runes = s.runes.toList();
  if (runes.length > 14) s = String.fromCharCodes(runes.take(14));
  return s.isEmpty ? author.trim() : s;
}
