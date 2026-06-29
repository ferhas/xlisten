import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../models/timeline_item.dart';
import '../state/listening_controller.dart';

/// 全屏播放:横向 PageView,左滑=下一条,右滑=上一条;无播放控制按钮。
/// 播完自动翻到下一页;点正文切换播/暂停;顶部只有进度条 + 返回。
/// 退出全屏不停止播放(返回列表后继续连读)。
class ListenPager extends StatefulWidget {
  const ListenPager({
    super.key,
    required this.controller,
    required this.tab,
    required this.startIndex,
  });

  final ListeningController controller;
  final String tab;
  final int startIndex;

  @override
  State<ListenPager> createState() => _ListenPagerState();
}

class _ListenPagerState extends State<ListenPager> {
  late final PageController _pageCtl;
  late List<TimelineItem> _items;
  int _index = 0;
  bool _programmatic = false;
  StreamSubscription<TimelineItem>? _completedSub;

  ListeningController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.fullscreenActive = true;
    _items = List.of(c.queue(widget.tab));
    _index = _items.isEmpty ? 0 : widget.startIndex.clamp(0, _items.length - 1);
    _pageCtl = PageController(initialPage: _index);
    c.addListener(_onControllerChanged);
    _completedSub = c.player.completedStream.listen(_onAudioCompleted);
    WidgetsBinding.instance.addPostFrameCallback((_) => _activate(_index));
  }

  @override
  void dispose() {
    c.fullscreenActive = false;
    c.removeListener(_onControllerChanged);
    _completedSub?.cancel();
    _pageCtl.dispose();
    // 退出全屏【不】暂停:返回列表后继续连读(由 controller._onCompleted 接管推进)。
    super.dispose();
  }

  /// 后台队列变化(续抓 append):把新条目接到 _items 尾部,不打乱当前页。
  void _onControllerChanged() {
    final live = c.queue(widget.tab);
    final have = {for (final it in _items) it.key};
    final newOnes = live.where((it) => !have.contains(it.key)).toList();
    if (newOnes.isNotEmpty && mounted) {
      setState(() => _items.addAll(newOnes));
    } else if (mounted) {
      setState(() {}); // 已读态变化重绘
    }
  }

  Future<void> _activate(int i) async {
    if (i < 0 || i >= _items.length) return;
    _index = i;
    final it = _items[i];
    // 同一条且未播完 → 从【上次位置】继续(暂停过就接着播),绝不重头;
    // 不同条 / 上次已播完 → 正常从头播。
    if (identical(c.player.current, it) && !c.player.isCompleted) {
      if (!c.player.playing) await c.player.play();
    } else {
      await c.playFrom(widget.tab, it); // 内含 ensureFull + 合成 + 播放
    }
    // Req5:看到剩 5 条未读以内,提前续抓
    var remaining = 0;
    for (var j = i + 1; j < _items.length; j++) {
      if (!_items[j].read) remaining++;
    }
    if (remaining <= 30) c.prefetchMore(widget.tab); // 缓冲低于 30 就提示后台慢补
  }

  void _onAudioCompleted(TimelineItem done) {
    if (!mounted || _index >= _items.length) return;
    if (!identical(_items[_index], done)) return; // 用户已手动翻走
    final next = _index + 1;
    if (next < _items.length) {
      _programmatic = true;
      _pageCtl.animateToPage(next,
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
      _activate(next);
    } else {
      c.prefetchMore(widget.tab); // 到底了,续抓;等用户上滑或新内容到
    }
  }

  void _onPageChanged(int i) {
    if (_programmatic) {
      _programmatic = false;
      return;
    }
    _activate(i);
  }

  Future<void> _openOriginal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cur = c.currentItem;
    return PopScope(
      canPop: false, // 横滑切页时屏蔽系统侧边返回手势误触;退出请点左上 ⌄ 箭头
      child: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_items.isEmpty)
              const Center(
                  child: Text('没有内容', style: TextStyle(color: Colors.white)))
            else
              PageView.builder(
                controller: _pageCtl,
                scrollDirection: Axis.horizontal,
                onPageChanged: _onPageChanged,
                itemCount: _items.length,
                itemBuilder: (ctx, i) => _TweetPage(
                  controller: c,
                  item: _items[i],
                  onTapToggle: () =>
                      c.player.playing ? c.player.pause() : c.player.play(),
                ),
              ),
            // 顶部:进度条 + 返回(无任何播放控制按钮)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  StreamBuilder<Duration>(
                    stream: c.player.positionStream,
                    builder: (ctx, s) {
                      final pos = s.data ?? Duration.zero;
                      final dur = c.player.duration ?? Duration.zero;
                      final v = dur.inMilliseconds <= 0
                          ? null
                          : (pos.inMilliseconds / dur.inMilliseconds)
                              .clamp(0.0, 1.0);
                      return LinearProgressIndicator(
                        value: v,
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation(cs.primary),
                      );
                    },
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: Colors.white),
                        tooltip: '返回',
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      if (cur != null && cur.url.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _openOriginal(cur.url),
                          icon: const Icon(Icons.open_in_new,
                              color: Colors.white70, size: 18),
                          label: const Text('原文',
                              style: TextStyle(color: Colors.white70)),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white70),
                        ),
                      const SizedBox(width: 6),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

class _TweetPage extends StatelessWidget {
  const _TweetPage({
    required this.controller,
    required this.item,
    required this.onTapToggle,
  });

  final ListeningController controller;
  final TimelineItem item;
  final VoidCallback onTapToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTapToggle,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: controller,
        builder: (ctx, _) {
          final read = item.read;
          return Opacity(
            opacity: read ? 0.6 : 1.0,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 60, 22, 64),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.author.isEmpty ? item.handle : item.author,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold),
                          softWrap: true,
                        ),
                      ),
                      if (read)
                        const Icon(Icons.check_circle,
                            color: Colors.white54, size: 20),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.tab == 'following' ? '正在关注' : '为你推荐'}   ·   ${relativeTime(item.time)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  // 用普通 Text(非 SelectableText):点正文的点击能落到外层切换播/暂停。
                  Text(
                    item.text,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 20, height: 1.6),
                  ),
                  if (item.textOriginal != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      item.textOriginal!,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 15, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
