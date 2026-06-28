import 'dart:async';

import '../models/timeline_item.dart';

/// 后台批量预合成,消除播放等待:
/// - Pass 1:现成的条目(无需补全)→ 低并发 TTS(2),先把大多数缓存好;
/// - Pass 2:长推/英文(需进详情页补全)→ 串行补全 + 1.5s 间隔,再 TTS(保护 X + 共享 WebView)。
/// 可取消:enqueue 会先取消上一批;改音色/语速重新 enqueue。命中缓存即跳过。
class SynthQueue {
  SynthQueue({
    required this.ensureFull,
    required this.synthOnly,
    required this.isCached,
    required this.needsFull,
  });

  final Future<void> Function(TimelineItem item) ensureFull;
  final Future<void> Function(TimelineItem item) synthOnly;
  final bool Function(TimelineItem item) isCached;
  final bool Function(TimelineItem item) needsFull;

  int _gen = 0;

  void cancel() => _gen++;

  void enqueue(List<TimelineItem> items) {
    cancel();
    final gen = _gen;
    _run(List.of(items), gen);
  }

  Future<void> _run(List<TimelineItem> items, int gen) async {
    // Pass 1:现成项 → TTS,低并发 2
    final ready = items.where((it) => !needsFull(it) && !isCached(it)).toList();
    await _ttsBatch(ready, gen);
    if (gen != _gen) return;
    // Pass 2:需补全项 → 串行补全 + 间隔,再 TTS
    final needFull = items.where((it) => needsFull(it) && !isCached(it)).toList();
    for (final it in needFull) {
      if (gen != _gen) return;
      try {
        await ensureFull(it);
        if (gen != _gen) return;
        await _ttsOne(it);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
  }

  Future<void> _ttsBatch(List<TimelineItem> items, int gen, {int concurrency = 2}) async {
    var idx = 0;
    Future<void> worker() async {
      while (true) {
        if (gen != _gen) return;
        final i = idx++;
        if (i >= items.length) return;
        await _ttsOne(items[i]);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
  }

  static const List<Duration> _backoff = [
    Duration(milliseconds: 800),
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];

  Future<void> _ttsOne(TimelineItem it) async {
    if (isCached(it)) return;
    for (var attempt = 0;; attempt++) {
      try {
        await synthOnly(it);
        return;
      } catch (_) {
        if (attempt >= _backoff.length) return; // 放弃,留到播放时按需合成
        await Future<void>.delayed(_backoff[attempt]);
      }
    }
  }
}
