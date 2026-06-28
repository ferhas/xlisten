# xlisten · 把 X(Twitter)时间线变成有声播客 🎧

> 用 **Edge‑TTS 晓晓** 自动朗读你的 X / Twitter 时间线的安卓 App。抓取「为你推荐 / 正在关注」，抖音式全屏滑动收听，开车、走路、躺着都能「听推」。
>
> **Listen to your X (Twitter) timeline as a podcast.** An Android app that scrapes your own X home timeline and reads tweets aloud with Microsoft Edge‑TTS — hands‑free, eyes‑free.

![Flutter](https://img.shields.io/badge/Flutter-3.24-02569B?logo=flutter)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android)
![Edge--TTS](https://img.shields.io/badge/TTS-Edge--TTS%20晓晓-5E5EFF)
![License](https://img.shields.io/badge/license-MIT-green)

关键词 / keywords：`X` `Twitter` `时间线朗读` `听推` `推文转语音` `text-to-speech` `Edge-TTS` `晓晓` `TTS` `Flutter` `Android` `无障碍` `podcast`

---

## ✨ 功能 Features

- 🔊 **自动朗读时间线** —— 抓取你自己的「为你推荐 / 正在关注」，用 Edge‑TTS 晓晓逐条朗读、自动连读。
- 📱 **抖音式全屏收听** —— 点一条进全屏，左右滑切换上下条，点正文暂停 / 继续。
- 🌓 **暗黑模式 + 超大字** —— 为「听」设计，字号随系统、绝不截断。
- 🌐 **长推 / 英文懒补全** —— 轮到才进详情页取全文,英文取 X 的中文翻译再读。
- 🗣️ **多音色 + 变速** —— 6 个中文音色、0.8×–2.0× 六档语速,即时生效。
- 💾 **离线缓存 + 后台预合成** —— 刷新后台预生成 MP3(LRU 缓存),命中即播、可离线重听。
- ✅ **已读管理** —— 开始播即标记已读、变淡;下次刷新或双击 TAB 才移入历史。
- ⏰ **定时关闭** —— 20 / 30 / 45 / 60 分钟后自动暂停,睡前听不怕。
- 🔁 **续播不重头** —— 来回切换从上次位置继续。
- 🔐 **登录持久** —— App 内登录一次,原生 cookie 桥持久保存,重启不掉线。

## 🧠 工作原理 How it works

```
内嵌 WebView 登录 x.com ──▶ 注入 JS 抓取 article(作者/正文/时间/链接)
        │                              │
        ▼                              ▼
  原生 cookie 桥(持久登录)      去重 / 过滤 / 未读队列(ChangeNotifier)
                                       │
                                       ▼
                    Edge‑TTS(WebSocket)合成 MP3 ──▶ just_audio 播放 + 连读
```

- 抓取:`webview_flutter` 隐藏页面 + JavaScript channel 注入提取脚本。
- 朗读:直连 **Microsoft Edge‑TTS** 的 WebSocket 端点(`zh-CN-XiaoxiaoNeural` 等),本地落 MP3 做 LRU 缓存。
- 播放:`just_audio` + `audio_session`,以「条目身份」为中心编排连读 / 预取。

## 🛠️ 技术栈 Tech stack

Flutter 3.24 · Dart 3.5 · `webview_flutter` · `just_audio` · `audio_session` · `shared_preferences` · `path_provider` · `crypto` · `url_launcher` · Edge‑TTS(晓晓)· Android(Kotlin 原生 cookie 桥)

## 🚀 构建 Build

```bash
# 需要 Flutter 3.24+ 与 JDK 17
flutter pub get
flutter build apk --release
# 产物:build/app/outputs/flutter-apk/app-release.apk(直接侧载安装)
```

首次使用:打开 App → 在内嵌页面登录你自己的 X 账号 → 自动抓取并开始朗读。
详细使用说明见 [`README_使用说明.md`](README_使用说明.md)。

## ⚠️ 免责声明 Disclaimer

- 本项目仅供**个人学习与自用**:读你**自己**账号的时间线。请自行遵守 [X 服务条款](https://x.com/tos) 与 Microsoft 相关条款。
- 自动化访问可能违反平台服务条款,**存在账号被限制 / 封禁的风险,后果自负**。
- 项目**不收集、不上传**任何用户数据;登录 cookie 只保存在你自己的设备本地。
- 按 **「现状(AS‑IS)」** 提供,不作任何担保。请勿用于批量抓取或商业服务。
- This tool is for **personal, educational use only**. Automated access may violate the platform's Terms of Service; use at your own risk. No data is collected or transmitted; credentials stay on your device.

## 📄 License

[MIT](LICENSE)
