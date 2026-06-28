# X 时间线收听（独立安卓 App）

把你自己的 X（Twitter）「为你推荐 / 正在关注」时间线，做成手机上**获取列表、点一条收听**的独立 APK。完全在手机本地运行，不依赖 PC。

## 它怎么工作

App 内嵌一个 WebView，你在里面登录一次自己的 X → App 注入 JS 抓时间线 → 原生列表展示 → 点单条或「全部连读」，用微软 Edge-TTS 的**晓晓**音色（+20% 语速）朗读。长推/英文条会在轮到朗读时自动进详情页补全完整正文、取 X 的中文翻译。

## 安装

1. 把 `build/app/outputs/flutter-apk/app-release.apk` 传到手机（微信/USB/网盘均可）。
2. 手机「设置 → 应用 → 特殊权限 → 安装未知应用」允许从文件管理器安装。
3. 点 APK 安装。（已用 debug key 自动签名，可直接侧载。）

## 使用

1. 首次打开会显示 X 页面 → **登录你的 X 账号**（和你平时手机登 X 一样）→ 登录后点底部「我已登录，继续」。
2. 进入列表页，点右上角**刷新**抓取时间线（每板块约 30 条，随机停顿抓取以降低风控）。
3. **点任意一条**即开始朗读；底部播放条有**全部连读 / 上一条 / 播放暂停 / 下一条 / 进度条**。连读会自动跳到下一条，并边播边预取下一条的音频。
4. 列表项带 🔤(translate) 图标的是长推或英文条，朗读前会自动补全/翻译。

## 网络要求（重要）

App 要联网访问两处：`x.com`（抓取）和 `speech.platform.bing.com`（Edge-TTS 合成）。在中国大陆这两者通常都需要你手机上访问 X 的同一条网络通道（系统级 VPN/全局代理）。**只要你手机能正常刷 X，这个 App 就能抓取；TTS 也走同一系统网络。** 若某条合成失败，App 会自动跳过、继续连读，不中断。

## 开发/重新编译

本机已具备：Flutter 3.24.5、Android SDK、JDK 17（`C:\JDK17\jdk-17.0.11+9`，已 `flutter config --jdk-dir` 指好）。

```bash
cd D:/code/X/xlisten
# 构建命令务必【不走】那个会拦截 Google/Maven 的 env 代理；走国内镜像
unset HTTP_PROXY HTTPS_PROXY
export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

flutter pub get
flutter test                 # 纯逻辑 + Edge-TTS 协议单测
flutter build apk --release  # 产物：build/app/outputs/flutter-apk/app-release.apk

# 装到连着的手机：
"$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe" install -r build/app/outputs/flutter-apk/app-release.apk
```

gradle 依赖镜像已配在 `android/settings.gradle` 与 `android/build.gradle`（阿里云 google/public）。`minSdk=24`（webview_flutter 要求），`INTERNET` 权限已加。

手动验证 Edge-TTS（经代理真连微软）：`dart run tool/tts_spike.dart 代理host:port`。

## 代码结构

```
lib/
  core/text_utils.dart      纯文本逻辑（从 scrape_x.py/build_audio.py 移植：detectLang/isEnglish/clean/makeReadingText…）
  models/timeline_item.dart  推文模型
  services/
    edge_tts.dart           Edge-TTS WebSocket 协议（token/SSML/帧解析）
    x_scraper.dart          注入 JS（复刻 JS_EXTRACT/JS_FULL）+ 抓取/滚动/补全
    store.dart              shared_preferences 缓存
    tts_service.dart        合成→临时 mp3
  player/playlist_player.dart  just_audio 手动队列：连读/自动下一条/预取
  ui/home_page.dart         WebView 引擎栈 + 登录门 + 列表 + 播放条
  main.dart
test/                       25 个单测（含 Edge-TTS token/帧解析）
```

## 已验证 / 待真机验证

- ✅ 编译通过（debug + release APK 都能出包）、25 个单测全过。
- ✅ Edge-TTS 协议：Dart 算的 Sec-MS-GEC token 与本机官方 edge-tts 7.2.8 **逐字节一致**；Python 经同代理真合成出音频；帧解析单测通过。
- ⏳ 需在你的真机（带 X 登录 + 网络）上确认的活路：WebView 登录后抓取是否拿到列表、Edge-TTS 在手机网络上能否合成、端到端连读。X 偶尔改版 DOM 时，`x_scraper.dart` 里的选择器可能要跟着小改（与 PC 端 `scrape_x.py` 同源）。
