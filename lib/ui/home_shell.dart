import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/cookie_bridge.dart';
import '../services/store.dart';
import '../services/tts_service.dart';
import '../services/x_scraper.dart';
import '../state/listening_controller.dart';
import 'listen_pager.dart';
import 'queue_list_page.dart';
import 'settings_page.dart';

const String _kMobileUA =
    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

enum _Mode { loading, login, app }

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final WebViewController _homeController;
  late final WebViewController _detailController;
  late final XScraper _homeScraper;
  late final XScraper _detailScraper;
  late final ListeningController _c;
  late final TabController _tab;

  _Mode _mode = _Mode.loading;
  bool _checking = false;
  bool _firstFetched = false;
  DateTime? _lastTabTap; // 双击 TAB 检测(清理已读)
  int? _lastTabIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tab = TabController(length: 2, vsync: this);
    _homeController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_kMobileUA)
      ..setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => _onHomeFinished()));
    _detailController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_kMobileUA);
    _homeScraper = XScraper(_homeController, channelName: 'XBridgeH');
    _detailScraper = XScraper(_detailController, channelName: 'XBridgeD');
    _c = ListeningController(
      store: Store(),
      tts: TtsService(),
      homeScraper: _homeScraper,
      detailScraper: _detailScraper,
    );
    _init();
  }

  Future<void> _init() async {
    await _homeScraper.attach();
    await _detailScraper.attach();
    await _detailController.loadRequest(Uri.parse('about:blank'));
    await _c.init();
    if (mounted) setState(() {});
    await _c.restoreSavedCookies(); // 先注入本地保存的登录
    await _seedCookiesIfPresent(); // seed 文件(若有)用更新鲜的值覆盖并存盘
    await _homeController.loadRequest(Uri.parse('https://x.com/home'));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 后台播放交给前台服务,熄屏继续读;进后台只把 cookie 落盘。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      CookieBridge.flush();
      _c.captureCookies();
    }
  }

  /// 测试用:若外部目录有 seed_cookies.json 则注入免登录,用完即删(生产无此文件)。
  Future<void> _seedCookiesIfPresent() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final f = File('${dir.path}/seed_cookies.json');
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final a = (j['auth_token'] as String?) ?? '';
      final c0 = (j['ct0'] as String?) ?? '';
      if (a.isNotEmpty) {
        await _c.saveAndInjectCookies(a, c0); // 持久注入 + 存盘(供下次重启恢复)
      }
      await f.delete();
    } catch (_) {}
  }

  Future<void> _onHomeFinished() async {
    if (_checking) return;
    _checking = true;
    try {
      _homeController.runJavaScript(kMuteMediaJs); // 静音隐藏 WebView 里 x.com 的视频
      final st = await _homeScraper.loginState();
      if (!mounted) return;
      if (st == 'in') {
        _c.captureCookies(); // 登录成功 → 读真实 cookie 存本地
        if (_mode != _Mode.app) setState(() => _mode = _Mode.app);
        if (!_firstFetched) {
          _firstFetched = true;
          _firstFetch();
        }
      } else if (st == 'login') {
        if (_mode != _Mode.login) setState(() => _mode = _Mode.login);
      } else if (_mode == _Mode.loading) {
        setState(() => _mode = _Mode.app);
      }
    } finally {
      _checking = false;
    }
  }

  /// 首次登录后:两队列都空则自动抓两个 tab;否则用缓存,静默刷新当前 tab。
  Future<void> _firstFetch() async {
    if (_c.unread('for_you') == 0 && _c.unread('following') == 0) {
      await _c.refresh('for_you');
      await _c.refresh('following');
    } else {
      _c.refresh(_currentTab);
    }
  }

  String get _currentTab => _tab.index == 0 ? 'for_you' : 'following';

  Future<void> _recheckLogin() async {
    final st = await _homeScraper.loginState();
    if (!mounted) return;
    if (st == 'in') {
      setState(() => _mode = _Mode.app);
      if (!_firstFetched) {
        _firstFetched = true;
        _firstFetch();
      }
    } else {
      _snack('还没检测到登录,请确认已登录 X');
    }
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s), duration: const Duration(seconds: 2)));
  }

  void _refreshCurrent() {
    final tab = _currentTab;
    _c.refresh(tab).then((added) {
      if (mounted) _snack(added > 0 ? '新增 $added 条' : '没有新内容');
    });
  }

  void _openPager(String tab, int index) => Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              ListenPager(controller: _c, tab: tab, startIndex: index),
        ),
      );

  void _recallPager() {
    final tab = _c.playingTab;
    final cur = _c.currentItem;
    final idx = cur == null ? 0 : _c.queue(tab).indexOf(cur);
    _openPager(tab, idx < 0 ? 0 : idx);
  }

  void _openSettings() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SettingsPage(
            controller: _c,
            onRelogin: () => setState(() => _mode = _Mode.login),
          ),
        ),
      );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tab.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _detailController),
        WebViewWidget(controller: _homeController),
        if (_mode == _Mode.app) _buildApp(),
        if (_mode == _Mode.loading) _buildLoading(),
        if (_mode == _Mode.login) _buildLoginOverlay(),
      ],
    );
  }

  Widget _buildLoading() => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('正在加载 X…'),
            ],
          ),
        ),
      );

  Widget _buildLoginOverlay() => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          elevation: 8,
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('请在上方页面登录你的 X 账号,登录后即可收听你的时间线',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _recheckLogin,
                      child: const Text('我已登录,继续'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildApp() {
    return AnimatedBuilder(
      animation: _c,
      builder: (ctx, _) {
        final hasPlaying = _c.ready && _c.currentItem != null;
        return Scaffold(
          appBar: AppBar(
            title: const Text('收听'),
            actions: [
              if (hasPlaying)
                StreamBuilder<PlayerState>(
                  stream: _c.player.playerStateStream,
                  builder: (sctx, snap) {
                    final playing = snap.data?.playing ?? false;
                    return IconButton(
                      tooltip: playing ? '暂停' : '播放',
                      onPressed: () =>
                          playing ? _c.player.pause() : _c.player.play(),
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    );
                  },
                ),
              if (hasPlaying)
                IconButton(
                  tooltip: '正在播放',
                  onPressed: _recallPager,
                  icon: Icon(Icons.graphic_eq,
                      color: Theme.of(ctx).colorScheme.primary),
                ),
              IconButton(
                tooltip: '刷新',
                onPressed: _c.loading ? null : _refreshCurrent,
                icon: _c.loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
              ),
              PopupMenuButton<int>(
                tooltip: '定时关闭',
                icon: Icon(Icons.bedtime_outlined,
                    color: _c.sleepAfterMin != null
                        ? Theme.of(ctx).colorScheme.primary
                        : null),
                onSelected: (v) {
                  _c.setSleepTimer(v == 0 ? null : v);
                  _snack(v == 0 ? '已取消定时' : '将在 $v 分钟后暂停播放');
                },
                itemBuilder: (_) => [
                  if (_c.sleepAfterMin != null)
                    PopupMenuItem(
                        value: 0,
                        child: Text('取消定时(剩 ${_c.sleepAfterMin} 分钟)')),
                  for (final m in const [20, 30, 45, 60])
                    PopupMenuItem(value: m, child: Text('$m 分钟后暂停')),
                ],
              ),
              IconButton(
                  tooltip: '设置',
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_outlined)),
            ],
            bottom: TabBar(
              controller: _tab,
              onTap: _onTabTap,
              tabs: [
                _tabLabel('推荐', 'for_you', _c.unread('for_you')),
                _tabLabel('关注', 'following', _c.unread('following')),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tab,
            children: [
              QueueListPage(
                  controller: _c, tab: 'for_you', onOpenPager: _openPager),
              QueueListPage(
                  controller: _c, tab: 'following', onOpenPager: _openPager),
            ],
          ),
        );
      },
    );
  }

  Widget _tabLabel(String name, String tab, int n) => Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (n > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$n',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimary)),
              ),
            ],
          ],
        ),
      );

  /// 双击同一个 TAB → 清理该 tab 列表里的已读(可靠地用 TabBar.onTap 判重复点击)。
  void _onTabTap(int i) {
    final now = DateTime.now();
    final isDouble = _lastTabIndex == i &&
        _lastTabTap != null &&
        now.difference(_lastTabTap!) < const Duration(milliseconds: 500);
    _lastTabTap = now;
    _lastTabIndex = i;
    if (isDouble) {
      final tab = i == 0 ? 'for_you' : 'following';
      final removed = _c.purgeReadNow(tab);
      _snack(removed > 0 ? '已清理 $removed 条已读' : '没有已读可清理');
    }
  }
}
