"""用宿主机 Chrome（能上 X）+ cookie，在真 x.com 上跑 App 里一模一样的抓取 JS，
验证选择器今天仍有效。只读，不写任何文件。
  py tool/verify_scrape.py
"""
import json
import sys

from playwright.sync_api import sync_playwright

sys.stdout.reconfigure(encoding="utf-8")
ck = json.load(open(r"D:\code\X\cookies.json", encoding="utf-8"))

# 与 lib/services/x_scraper.dart 的 kExtractJs 完全一致
JS_EXTRACT = r"""
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
"""

with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome", headless=True)
    ctx = b.new_context(locale="zh-CN")
    ctx.add_cookies([
        {"name": "auth_token", "value": ck["auth_token"], "domain": ".x.com",
         "path": "/", "httpOnly": True, "secure": True},
        {"name": "ct0", "value": ck["ct0"], "domain": ".x.com", "path": "/", "secure": True},
    ])
    page = ctx.new_page()
    page.goto("https://x.com/home", wait_until="domcontentloaded", timeout=30000)
    page.wait_for_timeout(5000)
    if "/home" not in page.url:
        print("❌ 未登录成功, url =", page.url)
        b.close()
        sys.exit(1)
    print("✅ 已登录 x.com/home")
    try:
        page.get_by_role("tab", name="为你推荐").click(timeout=5000)
    except Exception:
        print("（未点到「为你推荐」tab，直接抓当前）")
    page.wait_for_timeout(3000)
    page.evaluate("window.scrollBy(0, window.innerHeight*2)")
    page.wait_for_timeout(2500)
    res = page.evaluate(JS_EXTRACT)
    real = [it for it in res if it.get("url") and it.get("text")]
    print(f"\n=== 抓取 JS 提取到 {len(res)} 个 article，其中有正文+链接的 {len(real)} 条 ===")
    for it in real[:8]:
        t = (it.get("text") or "").replace("\n", " ")[:46]
        print(f"  · {it.get('name')}  {it.get('handle')}  | {t}  | trunc={it.get('truncated')} like={it.get('like')[:14] if it.get('like') else ''}")
    b.close()
