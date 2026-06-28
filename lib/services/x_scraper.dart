import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:webview_flutter/webview_flutter.dart';

import '../core/text_utils.dart';

/// 注入 JS：抓取当前页所有 article（复刻 scrape_x.JS_EXTRACT），返回数组。
const String kExtractJs = r'''
(function(){
  function stat(art,t){var el=art.querySelector('[data-testid="'+t+'"]');return el?(el.getAttribute('aria-label')||''):'';}
  var res=[];
  var arts=document.querySelectorAll('article');
  for(var i=0;i<arts.length;i++){
    var art=arts[i];
    var textEl=art.querySelector('[data-testid="tweetText"]');
    var text=textEl?textEl.innerText:'';
    var nameEl=art.querySelector('[data-testid="User-Name"]');
    var name='',handle='';
    if(nameEl){var p=nameEl.innerText.split('\n').filter(Boolean);name=p[0]||'';for(var k=0;k<p.length;k++){if(p[k].charAt(0)==='@'){handle=p[k];break;}}}
    var timeEl=art.querySelector('time');
    var url='',time='';
    if(timeEl){time=timeEl.getAttribute('datetime')||'';var a=timeEl.closest('a');if(a){url=a.href;}}
    var showMore=art.querySelector('[data-testid="tweet-text-show-more-link"]');
    var tail=(art.innerText||'').slice(-40);
    var truncated=!!showMore||/显示更多|Show more/.test(tail);
    res.push({name:name,handle:handle,text:text,time:time,url:url,truncated:truncated,reply:stat(art,'reply'),retweet:stat(art,'retweet'),like:stat(art,'like')});
  }
  return res;
})()
''';

/// 注入 JS：详情页取主推文完整正文（复刻 scrape_x.JS_FULL）。英文条目此处通常已是 X 中文翻译。
const String kFullJs = r'''
(function(){var art=document.querySelector('article');if(!art){return null;}var el=art.querySelector('[data-testid="tweetText"]');return el?el.innerText:null;})()
''';

/// 注入 JS：判断登录态。返回 'in' / 'login' / 'unknown'。
/// 注入 JS:静音并暂停页面里所有 video/audio(隐藏抓取 WebView 不该出声),
/// 装 MutationObserver + 定时器,持续静音滚动新出现的视频。
const String kMuteMediaJs = r'''
(function(){
  function mute(){ try{ var ms=document.querySelectorAll('video,audio'); for(var i=0;i<ms.length;i++){ ms[i].muted=true; ms[i].volume=0; try{ms[i].pause();}catch(e){} } }catch(e){} }
  mute();
  if(!window.__xlMute){ window.__xlMute=true; try{ new MutationObserver(mute).observe(document.documentElement,{childList:true,subtree:true}); }catch(e){} setInterval(mute, 2500); }
  return 'muted';
})()
''';

const String kLoginJs = r'''
(function(){
  var path=location.pathname||'';
  if(path.indexOf('/login')>=0||path.indexOf('/i/flow/login')>=0||path.indexOf('/i/flow/signup')>=0){return 'login';}
  if(document.querySelector('[data-testid="primaryColumn"]')||document.querySelector('article')){return 'in';}
  if(document.querySelector('input[autocomplete="username"]')||document.querySelector('input[name="text"]')){return 'login';}
  return 'unknown';
})()
''';

/// 封装一个 WebViewController：通过 JS 通道做“请求/响应”式取值，并实现抓取/补全。
class XScraper {
  final WebViewController controller;
  final String channelName;
  final Random _rng = Random();
  Completer<String>? _pending;

  XScraper(this.controller, {required this.channelName});

  /// 注册 JS 通道（须在用到 eval 前调用一次）。
  Future<void> attach() async {
    await controller.addJavaScriptChannel(
      channelName,
      onMessageReceived: (JavaScriptMessage m) {
        final c = _pending;
        if (c != null && !c.isCompleted) c.complete(m.message);
      },
    );
  }

  /// 执行一个 JS 表达式，结果经通道回传并 JSON 解码。串行使用（一次一个）。
  Future<dynamic> eval(String jsExpr,
      {Duration timeout = const Duration(seconds: 15)}) async {
    final c = Completer<String>();
    _pending = c;
    final wrapped =
        '(function(){try{var __r=($jsExpr);$channelName.postMessage(JSON.stringify(__r===undefined?null:__r));}'
        'catch(e){$channelName.postMessage(JSON.stringify("__ERR__"+(e&&e.message?e.message:String(e))));}})();';
    await controller.runJavaScript(wrapped);
    final msg = await c.future.timeout(timeout, onTimeout: () => '"__TIMEOUT__"');
    try {
      return jsonDecode(msg);
    } catch (_) {
      return msg;
    }
  }

  /// 轮询等待选择器出现。
  Future<bool> waitForSelector(String selector,
      {Duration timeout = const Duration(seconds: 12)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final ok = await eval('document.querySelector(${jsonEncode(selector)})!=null',
          timeout: const Duration(seconds: 4));
      if (ok == true) return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  Future<String> loginState() async {
    final r = await eval(kLoginJs);
    return r is String ? r : 'unknown';
  }

  /// 切到目标 tab、随机滚动收集，直到达到 target 或连续 staleStop 次无新增。
  Future<List<Map<String, dynamic>>> scrapeTab(
    List<String> tabNames, {
    int target = 30,
    int maxScrolls = 40,
    int staleStop = 8,
  }) async {
    await eval(_tabClickExpr(tabNames));
    await _sleep(2500, 4500);
    await controller.runJavaScript('window.scrollTo(0,0);');
    await _sleep(900, 1800);
    // 先等时间线渲染出来(冷加载/慢网时,推文要点 tab 后才出现),避免抓空。
    await waitForSelector('article', timeout: const Duration(seconds: 15));

    final store = <String, Map<String, dynamic>>{};
    var stale = 0;
    for (var i = 0; i < maxScrolls; i++) {
      final before = store.length;
      await _collect(store);
      if (store.length >= target) break;
      stale = (store.length == before) ? stale + 1 : 0;
      if (stale >= staleStop) break;
      final factor = (1.1 + _rng.nextDouble()).toStringAsFixed(2); // 1.1~2.1 屏
      await controller
          .runJavaScript('window.scrollBy(0, window.innerHeight*$factor);');
      await _sleep(1500, 3600); // 随机停顿，拟人化、降风控
    }
    await _collect(store);
    return store.values.take(target).toList();
  }

  Future<void> _collect(Map<String, Map<String, dynamic>> store) async {
    final res = await eval(kExtractJs);
    if (res is! List) return;
    for (final raw in res) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final text = (m['text'] as String?) ?? '';
      final handle = (m['handle'] as String?) ?? '';
      final url = (m['url'] as String?) ?? '';
      final key = itemKey(handle, text, url);
      if (text.isNotEmpty && key.isNotEmpty && !store.containsKey(key)) {
        store[key] = m;
      }
    }
  }

  String _tabClickExpr(List<String> names) {
    final arr = jsonEncode(names);
    return '(function(){var ns=$arr;var tabs=document.querySelectorAll(\'[role="tab"]\');'
        'for(var i=0;i<tabs.length;i++){var t=(tabs[i].innerText||"").trim();'
        'for(var j=0;j<ns.length;j++){if(t.indexOf(ns[j])>=0){tabs[i].click();return "ok";}}}'
        'return "notfound";})()';
  }

  /// 详情页取完整正文（用于懒补全/英文翻译）。运行在“详情” WebView 上。
  Future<String?> fetchFull(String url) async {
    await controller.loadRequest(Uri.parse(url));
    final ok = await waitForSelector('article [data-testid="tweetText"]',
        timeout: const Duration(seconds: 9));
    if (!ok) return null;
    await controller.runJavaScript(kMuteMediaJs); // 详情页也静音视频
    await _sleep(700, 1100);
    final r = await eval(kFullJs);
    return r is String ? r : null;
  }

  Future<void> _sleep(int minMs, int maxMs) async {
    final d = minMs + _rng.nextInt(maxMs - minMs);
    await Future<void>.delayed(Duration(milliseconds: d));
  }
}
