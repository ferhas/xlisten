import '../core/text_utils.dart';

/// 一条时间线推文。text/lang/completed/textZh 可变(懒补全会原地替换/补充)。
class TimelineItem {
  String author;
  String handle;
  String text; // 当前用于朗读/预览的正文(英文条补全后会换成中文译文)
  String? textZh; // X 中文译文(英文条补全所得)
  String? textOriginal; // 英文原文(补全前的原始正文,供原文/译文切换)
  bool truncated;
  bool completed;
  bool read; // 已听(听完即标记,但留在列表,下次刷新才移走)
  String lang;
  final String time;
  final String url;
  final int? replies;
  final int? retweets;
  final int? likes;
  final bool promoted;
  final String tab; // 'for_you' | 'following'

  TimelineItem({
    required this.author,
    required this.handle,
    required this.text,
    this.textZh,
    this.textOriginal,
    required this.truncated,
    required this.completed,
    this.read = false,
    required this.lang,
    required this.time,
    required this.url,
    required this.replies,
    required this.retweets,
    required this.likes,
    required this.promoted,
    required this.tab,
  });

  String get key => itemKey(handle, text, url);

  /// 从注入 JS 抓回的原始 map 构造(字段同 scrape_x.JS_EXTRACT)。
  factory TimelineItem.fromScrape(Map<String, dynamic> j, String tab) {
    final text = (j['text'] as String?)?.trim() ?? '';
    final url = (j['url'] as String?) ?? '';
    return TimelineItem(
      author: (j['name'] as String?)?.trim() ?? '',
      handle: (j['handle'] as String?) ?? '',
      text: text,
      truncated: (j['truncated'] as bool?) ?? false,
      completed: false,
      lang: detectLang(text),
      time: (j['time'] as String?) ?? '',
      url: url,
      replies: parseNum(j['reply'] as String?),
      retweets: parseNum(j['retweet'] as String?),
      likes: parseNum(j['like'] as String?),
      promoted: url.isEmpty,
      tab: tab,
    );
  }

  Map<String, dynamic> toJson() => {
        'author': author,
        'handle': handle,
        'text': text,
        'textZh': textZh,
        'textOriginal': textOriginal,
        'truncated': truncated,
        'completed': completed,
        'read': read,
        'lang': lang,
        'time': time,
        'url': url,
        'replies': replies,
        'retweets': retweets,
        'likes': likes,
        'promoted': promoted,
        'tab': tab,
      };

  factory TimelineItem.fromJson(Map<String, dynamic> j) => TimelineItem(
        author: j['author'] as String? ?? '',
        handle: j['handle'] as String? ?? '',
        text: j['text'] as String? ?? '',
        textZh: j['textZh'] as String?,
        textOriginal: j['textOriginal'] as String?,
        truncated: j['truncated'] as bool? ?? false,
        completed: j['completed'] as bool? ?? false,
        read: j['read'] as bool? ?? false,
        lang: j['lang'] as String? ?? 'other',
        time: j['time'] as String? ?? '',
        url: j['url'] as String? ?? '',
        replies: j['replies'] as int?,
        retweets: j['retweets'] as int?,
        likes: j['likes'] as int?,
        promoted: j['promoted'] as bool? ?? false,
        tab: j['tab'] as String? ?? 'for_you',
      );
}
