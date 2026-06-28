"""复现手机 WebView 的抓取条件:移动 UA + 移动视口 + 点「为你推荐」tab + 同一套抓取 JS。
看手机版 x.com 的 DOM 是否能被现有选择器抓到。只读不写。
  py tool/verify_scrape_mobile.py
"""
import json
import sys

from playwright.sync_api import sync_playwright

sys.stdout.reconfigure(encoding="utf-8")
ck = json.load(open(r"D:\code\X\cookies.json", encoding="utf-8"))

# 与 App 完全一致的移动 UA(home_shell.dart 的 _kMobileUA)
UA = ("Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36")

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
    res.push({name:name,handle:handle,text:text,url:url});
  }
  return res;
})()
"""

TAB_CLICK = r"""
(function(){var ns=["为你推荐","For you"];var tabs=document.querySelectorAll('[role="tab"]');
for(var i=0;i<tabs.length;i++){var t=(tabs[i].innerText||"").trim();
for(var j=0;j<ns.length;j++){if(t.indexOf(ns[j])>=0){tabs[i].click();return "ok:"+t;}}}
return "notfound:"+tabs.length+"tabs";})()
"""

with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome", headless=True)
    ctx = b.new_context(locale="zh-CN", user_agent=UA,
                        viewport={"width": 412, "height": 915}, is_mobile=True,
                        has_touch=True, device_scale_factor=2.6)
    ctx.add_cookies([
        {"name": "auth_token", "value": ck["auth_token"], "domain": ".x.com",
         "path": "/", "httpOnly": True, "secure": True},
        {"name": "ct0", "value": ck["ct0"], "domain": ".x.com", "path": "/", "secure": True},
    ])
    page = ctx.new_page()
    page.goto("https://x.com/home", wait_until="domcontentloaded", timeout=30000)
    page.wait_for_timeout(4000)
    print("url after load:", page.url)
    print("article count (initial):", page.evaluate("document.querySelectorAll('article').length"))
    print("tweetText count (initial):", page.evaluate("document.querySelectorAll('[data-testid=\"tweetText\"]').length"))
    print("tabs:", page.evaluate('Array.from(document.querySelectorAll(\'[role="tab"]\')).map(function(t){return (t.innerText||"").trim();})'))
    print("tab click:", page.evaluate(TAB_CLICK))
    page.wait_for_timeout(3500)
    page.evaluate("window.scrollBy(0, window.innerHeight*2)")
    page.wait_for_timeout(3000)
    print("article count (after tab+scroll):", page.evaluate("document.querySelectorAll('article').length"))
    res = page.evaluate(JS_EXTRACT)
    real = [it for it in res if it.get("url") and it.get("text")]
    print(f"\n=== 移动条件下提取 {len(res)} 个 article,有正文+链接 {len(real)} 条 ===")
    for it in real[:6]:
        t = (it.get("text") or "").replace("\n", " ")[:40]
        print(f"  · {it.get('name')} {it.get('handle')} | {t}")
    # 看看是不是有挑战/异常页面
    body = page.evaluate("document.body.innerText.slice(0,200)")
    print("\nbody head:", body.replace("\n", " ")[:160])
    b.close()
