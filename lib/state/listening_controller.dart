import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/text_utils.dart';
import '../core/voices.dart';
import '../models/timeline_item.dart';
import '../player/queue_player.dart';
import '../services/cookie_bridge.dart';
import '../services/store.dart';
import '../services/synth_queue.dart';
import '../services/tts_service.dart';
import '../services/x_scraper.dart';

/// 全局收听状态:抓取、去重、未读队列、已听 seen、历史、设置、播放编排。
class ListeningController extends ChangeNotifier {
  ListeningController({
    required this.store,
    required this.tts,
    required this.homeScraper,
    required this.detailScraper,
  });

  final Store store;
  final TtsService tts;
  final XScraper homeScraper;
  final XScraper detailScraper;

  final Set<String> _seen = {};
  final List<TimelineItem> forYou = [];
  final List<TimelineItem> following = [];
  final List<TimelineItem> history = [];

  String voice = kDefaultVoice;
  String rate = kDefaultRate;
  bool autoAdvance = true;
  bool autoFetch = true;
  bool autoplayOnOpen = false;

  bool loading = false;
  String? lastError;
  bool needLogin = false;
  String playingTab = 'for_you';

  late final QueuePlayer player;
  late final SynthQueue _synthQueue;
  bool _ready = false;
  bool get ready => _ready;

  bool fullscreenActive = false; // 抖音全屏播放器开着时,_onCompleted 只标记已听,由播放器翻页
  bool _prefetching = false;
  int _consecutiveFails = 0; // 连续合成失败计数(限流时止损,别空转烧队列)
  Timer? _sleepTimer;
  int? sleepAfterMin; // 当前定时关闭(分钟);null = 未设定时
  Future<void> _ensureLock = Future.value(); // 串行化详情页(共享 WebView)

  List<TimelineItem> queue(String tab) => tab == 'for_you' ? forYou : following;
  int unreadCount(String tab) => queue(tab).where((it) => !it.read).length;
  int unread(String tab) => unreadCount(tab);
  int get seenCount => _seen.length;
  bool isSeen(TimelineItem it) => _seen.contains(it.key);
  TimelineItem? get currentItem => _ready ? player.current : null;

  Future<void> init() async {
    voice = await store.getVoice();
    rate = await store.getRate();
    tts.voice = voice;
    tts.rate = rate;
    autoAdvance = await store.getBool('autoAdvance_v1', true);
    autoFetch = await store.getBool('autoFetch_v1', true);
    autoplayOnOpen = await store.getBool('autoplayOnOpen_v1', false);
    _seen.addAll(await store.loadSeen());
    forYou.addAll(await store.loadQueue('for_you'));
    following.addAll(await store.loadQueue('following'));
    history.addAll(await store.loadHistory());
    player = QueuePlayer(synthesize: _synth);
    player.onCompleted = _onCompleted;
    player.onFailed = _onFailed;
    player.onStarted = _onStarted; // 真正开始播放 → 标记已读(失败条目不会触发)
    player.onSkipNext = (cur) => _after(cur, queue(playingTab));
    player.onPeekNext = (cur) => _after(cur, queue(playingTab));
    await player.init();
    player.currentStream.listen((_) => notifyListeners()); // 当前项变化驱动 UI 刷新
    await tts.warmup(); // 让 isCachedSync 立即可用
    _synthQueue = SynthQueue(
      ensureFull: ensureFull,
      synthOnly: _synthOnly,
      isCached: (it) => tts.isCachedSync(it.key),
      needsFull: (it) => !it.completed && (it.truncated || isEnglish(it.text)),
    );
    _ready = true;
    notifyListeners();
    _kickPreSynth(); // 启动即后台预合成已加载的未读项
  }

  // ---------- 播放编排 ----------

  Future<void> playFrom(String tab, TimelineItem it) async {
    playingTab = tab;
    await player.playItem(it);
    notifyListeners();
  }

  Future<void> playAll(String tab) async {
    final q = queue(tab);
    if (q.isEmpty) return;
    await playFrom(tab, q.first);
  }

  /// current 之后第一条【未读】(不出队),用于预取/手动跳过/连读推进。
  TimelineItem? _after(TimelineItem cur, List<TimelineItem> q) {
    final i = q.indexOf(cur);
    if (i < 0) return null;
    for (var j = i + 1; j < q.length; j++) {
      if (!q[j].read) return q[j];
    }
    return null;
  }

  Future<void> _onCompleted(TimelineItem done) async {
    if (fullscreenActive) {
      markRead(done); // 全屏播放器自己翻页,这里只标记已听
      return;
    }
    markRead(done); // 标记已听(留在列表,不出队)
    if (!autoAdvance) {
      await player.stop();
      return;
    }
    final next = _after(done, queue(playingTab));
    if (next != null) {
      await player.playItem(next);
    } else {
      await _continueOrStop();
    }
  }

  /// 一条【真正开始播放】(合成成功):此刻才标记已读 —— 失败的条目到不了这里,绝不误标。
  void _onStarted(TimelineItem item) {
    _consecutiveFails = 0;
    markRead(item);
  }

  Future<void> _onFailed(TimelineItem item) async {
    // 合成失败:不标记已听(用户没听到),跳到下一条(留队列稍后可重试)。
    _consecutiveFails++;
    if (_consecutiveFails >= 4) {
      // 连续多条失败(多半被限流)→ 止损停下,别空转把整个队列烧成"已读般"快速跳过。
      _consecutiveFails = 0;
      lastError = '语音合成接连失败,已暂停(可能被限流),稍后再试';
      await player.stop();
      notifyListeners();
      return;
    }
    if (!autoAdvance) {
      await player.stop();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 600)); // 轻微退避,给限流恢复
    final next = _after(item, queue(playingTab));
    if (next != null) {
      await player.playItem(next);
    } else {
      await _continueOrStop();
    }
  }

  Future<void> _continueOrStop() async {
    // 先放掉队列里任何剩余未读(含刷新置顶进来的新条目):仍有未读时绝不自动刷新,
    // 避免「下方无未读但上方还堆着十几条」时反复触发刷新。
    for (final e in queue(playingTab)) {
      if (!e.read) {
        await player.playItem(e);
        return;
      }
    }
    // 真的一条未读都不剩了 → autoFetch 才抓下一批
    if (autoFetch) {
      final added = await refresh(playingTab);
      if (added > 0) {
        for (final e in queue(playingTab)) {
          if (!e.read) {
            await player.playItem(e);
            return;
          }
        }
      }
    }
    await player.stop();
    notifyListeners();
  }

  // ---------- 标记已听(Req2:留在列表,只在下次刷新才移走)----------

  void markRead(TimelineItem it) {
    if (it.read) return; // 幂等
    it.read = true;
    _seen.add(it.key);
    history.remove(it);
    history.insert(0, it);
    if (history.length > 500) history.removeRange(500, history.length);
    _persist();
    notifyListeners();
    _maybePrefetch(); // Req5:未读剩 5 条以下时自动续抓
  }

  // ---------- 抓取 / 去重入队 ----------

  Future<int> refresh(String tab) async {
    if (loading) return 0;
    loading = true;
    lastError = null;
    notifyListeners();
    try {
      await homeScraper.controller.loadRequest(Uri.parse('https://x.com/home'));
      final ok = await homeScraper.waitForSelector('[data-testid="primaryColumn"]',
          timeout: const Duration(seconds: 12));
      final st = await homeScraper.loginState();
      if (st == 'login' || (!ok && st != 'in')) {
        loading = false;
        needLogin = true;
        notifyListeners();
        return 0;
      }
      final names = tab == 'for_you'
          ? const ['为你推荐', 'For you']
          : const ['正在关注', 'Following'];
      final raw = await homeScraper.scrapeTab(names, target: 30);
      final scraped = raw.map((m) => TimelineItem.fromScrape(m, tab)).toList();
      _purgeRead(tab); // Req2:已读条目只在此刻(下次刷新)才从列表移走
      final added = _ingest(scraped, tab);
      loading = false;
      notifyListeners();
      _kickPreSynth(); // Req1:新内容后台预合成
      return added;
    } catch (e) {
      loading = false;
      lastError = '$e';
      notifyListeners();
      return 0;
    }
  }

  int _ingest(List<TimelineItem> scraped, String tab) {
    final q = queue(tab);
    final queued = {for (final it in q) it.key};
    final fresh = scraped
        .where((it) => !it.promoted)
        .where(_isPlayable)
        .where((it) => !_seen.contains(it.key)) // 全时段去重:听过永不再现
        .where((it) => !queued.contains(it.key))
        .toList();
    q.insertAll(0, fresh); // 只增不减,新内容置顶
    _persist();
    return fresh.length;
  }

  void _purgeRead(String tab) => queue(tab).removeWhere((it) => it.read);

  /// 双击 TAB:立刻把列表里的已读移走(已在 markRead 入历史),保留正在播的那条。返回移除条数。
  int purgeReadNow(String tab) {
    final cur = currentItem;
    final q = queue(tab);
    final before = q.length;
    q.removeWhere((it) => it.read && !identical(it, cur));
    final removed = before - q.length;
    if (removed > 0) {
      _persist();
      notifyListeners();
    }
    return removed;
  }

  bool _isPlayable(TimelineItem it) {
    if (it.promoted) return false;
    if (it.truncated || isEnglish(it.text)) return true;
    return clean(it.text).runes.length >= 15; // 过滤 15 字以下
  }

  // ---------- 后台预合成(Req1)/ 续抓(Req5)----------

  void _kickPreSynth() {
    if (!_ready) return;
    final primary = queue(playingTab).where((it) => !it.read);
    final other = playingTab == 'for_you' ? following : forYou;
    final secondary = other.where((it) => !it.read);
    final batch = [...primary, ...secondary].take(90).toList(); // 留缓冲,不超缓存上限 100
    _synthQueue.enqueue(batch);
  }

  /// 仅 TTS(条目已补全),供批量预合成用;<15 字跳过。
  Future<void> _synthOnly(TimelineItem it) async {
    final reading = makeReadingText(it.author, it.text);
    if (reading == null) return;
    await tts.synthToFile(reading, it.key);
  }

  void _maybePrefetch() {
    if (!autoFetch || _prefetching || loading) return;
    if (unreadCount(playingTab) > 12) return; // 未读 ≤12 就提前抓下一批
    _prefetching = true;
    () async {
      try {
        await refresh(playingTab);
      } finally {
        _prefetching = false;
      }
    }();
  }

  /// 供全屏播放器在翻页时触发续抓。
  void prefetchMore(String tab) {
    if (tab == playingTab) _maybePrefetch();
  }

  // ---------- 懒补全 / 全文 ----------

  /// 串行化:所有详情页导航(用户播放 + 后台批量)排队走,绝不并发抢同一个 WebView。
  Future<void> ensureFull(TimelineItem it) {
    final prev = _ensureLock;
    final completer = Completer<void>();
    _ensureLock = completer.future;
    return prev.then((_) async {
      try {
        await _ensureFullImpl(it);
      } finally {
        completer.complete();
      }
    });
  }

  Future<void> _ensureFullImpl(TimelineItem it) async {
    if (it.completed) return;
    if (it.url.isEmpty || !(it.truncated || isEnglish(it.text))) {
      it.completed = true;
      return;
    }
    try {
      final full = await detailScraper.fetchFull(it.url);
      if (full != null && full.isNotEmpty) {
        final better = full.length > it.text.length ||
            (isEnglish(it.text) && detectLang(full) == 'zh');
        if (better) {
          if (isEnglish(it.text)) it.textOriginal = it.text;
          it.text = full;
          it.lang = detectLang(full);
          if (detectLang(full) == 'zh') it.textZh = full;
        }
      }
    } catch (_) {}
    it.completed = true;
    _persist();
    notifyListeners();
  }

  Future<File> _synth(TimelineItem it) async {
    await ensureFull(it);
    final reading = makeReadingText(it.author, it.text);
    if (reading == null) throw StateError('skip');
    return tts.synthToFile(reading, it.key);
  }

  // ---------- 设置 ----------

  Future<void> setVoice(String v) async {
    voice = v;
    tts.voice = v;
    await store.setVoice(v);
    await player.invalidatePrefetch();
    notifyListeners();
    _kickPreSynth(); // 用新音色重新预合成
  }

  Future<void> setRate(String r) async {
    rate = r;
    tts.rate = r;
    await store.setRate(r);
    await player.invalidatePrefetch();
    notifyListeners();
    _kickPreSynth();
  }

  Future<void> setAutoAdvance(bool v) async {
    autoAdvance = v;
    await store.setBool('autoAdvance_v1', v);
    notifyListeners();
  }

  /// 定时关闭:[minutes] 分钟后暂停播放。null/0 = 取消。
  void setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (minutes != null && minutes > 0) {
      sleepAfterMin = minutes;
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        player.pause();
        sleepAfterMin = null;
        _sleepTimer = null;
        notifyListeners();
      });
    } else {
      sleepAfterMin = null;
    }
    notifyListeners();
  }

  Future<void> setAutoFetch(bool v) async {
    autoFetch = v;
    await store.setBool('autoFetch_v1', v);
    notifyListeners();
  }

  Future<void> setAutoplayOnOpen(bool v) async {
    autoplayOnOpen = v;
    await store.setBool('autoplayOnOpen_v1', v);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    history.clear();
    _seen.clear();
    await store.saveHistory([]);
    await store.saveSeen({});
    notifyListeners();
  }

  /// 重新抓满:清队列 + seen + 历史(对齐 Python「重新抓满」)。
  Future<void> resetAll() async {
    forYou.clear();
    following.clear();
    history.clear();
    _seen.clear();
    await _persist();
    notifyListeners();
  }

  Future<void> replayFromHistory(TimelineItem it) async {
    playingTab = it.tab;
    await player.playItem(it);
    notifyListeners();
  }

  // ---------- 登录持久化 ----------

  Future<void> _injectCookies(String authToken, String ct0) async {
    // 用原生写【持久】cookie(带 1 年过期),会话级 cookie 重启即失、持久才不丢登录。
    const persist = 'Domain=.x.com; Path=/; Max-Age=31536000';
    if (authToken.isNotEmpty) {
      await CookieBridge.setCookie(
          'https://x.com', 'auth_token=$authToken; $persist; Secure; HttpOnly');
    }
    if (ct0.isNotEmpty) {
      await CookieBridge.setCookie('https://x.com', 'ct0=$ct0; $persist; Secure');
    }
  }

  /// 启动时:把本地保存的登录 cookie 重注入(登录绝不掉)。
  Future<void> restoreSavedCookies() async {
    final c = await store.loadAuthCookies();
    final a = c['auth_token'] ?? '';
    if (a.isNotEmpty) await _injectCookies(a, c['ct0'] ?? '');
  }

  /// 登录成功后:从 WebView 读出真实 cookie(含 HttpOnly)存本地。
  Future<void> captureCookies() async {
    final s = await CookieBridge.getCookies('https://x.com');
    final m = CookieBridge.parse(s);
    final a = m['auth_token'] ?? '';
    if (a.isNotEmpty) await store.saveAuthCookies(a, m['ct0'] ?? '');
  }

  /// 存本地 + 注入(供 seed 文件 / 手动导入复用)。
  Future<void> saveAndInjectCookies(String authToken, String ct0) async {
    await store.saveAuthCookies(authToken.trim(), ct0.trim());
    await _injectCookies(authToken.trim(), ct0.trim());
  }

  /// 手动导入登录(粘贴 cookie):存本地 + 注入 + 重载 x.com。
  Future<void> importLogin(String authToken, String ct0) async {
    await saveAndInjectCookies(authToken, ct0);
    await homeScraper.controller.loadRequest(Uri.parse('https://x.com/home'));
  }

  Future<void> logout() async {
    await store.clearAuthCookies();
    await WebViewCookieManager().clearCookies();
  }

  /// 试听:一次性合成样例直接播放,不进队列、不写 seen。
  Future<void> previewVoice() async {
    try {
      final f = await tts.synthSample('你好，这是${voiceById(voice).name}音色的语音试听。');
      await player.playSample(f.path);
    } catch (_) {}
  }

  Future<void> _persist() async {
    await store.saveSeen(_seen);
    await store.saveQueue('for_you', forYou);
    await store.saveQueue('following', following);
    await store.saveHistory(history);
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    player.dispose();
    super.dispose();
  }
}
