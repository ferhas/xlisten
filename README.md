# xlisten

**Listen to your X (Twitter) home timeline.** xlisten is a privacy-first Android application that turns the posts in your own timeline into a continuous, hands-free, eyes-free audio stream — so you can keep up with what you follow while driving, walking, or resting your eyes.

![Flutter](https://img.shields.io/badge/Flutter-3.24-02569B?logo=flutter)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Overview

Most timelines are built to be *read*. xlisten is built to be *heard*. After you sign in to your own account, the app collects the posts from your **For You** and **Following** timelines and reads them aloud one after another, automatically advancing from one post to the next. A full-screen, swipe-driven player lets you move through posts with a single gesture and keep your attention on the road or the world around you instead of the screen.

xlisten runs entirely on your device. It does not operate a server, create an account, or transmit your data anywhere. Your session stays on your phone.

## Features

- **Continuous playback** — your timeline is read aloud post by post, with automatic advance and gap-free transitions.
- **Full-screen player** — a distraction-free reader with swipe navigation and tap-to-pause; no controls to hunt for.
- **Two timelines** — independent, unread-aware queues for *For You* and *Following*, deduplicated against each other.
- **Read tracking** — posts are marked as heard and quietly set aside, so you never listen to the same post twice.
- **Long-form & translation aware** — truncated posts are expanded on demand, and non-native posts are read in translation.
- **Inline media** — images are shown alongside the text; videos display a thumbnail with a link to the source.
- **Natural speech** — high-quality neural text-to-speech with selectable voices and adjustable reading speed.
- **Offline-friendly** — synthesized audio is cached locally for instant, repeatable playback.
- **Sleep timer** — pause automatically after a chosen interval.

## How it works

xlisten loads your timeline in an embedded web view using your existing session, extracts the visible posts, and synthesizes speech for each one through a neural text-to-speech service. Audio is produced ahead of time and cached on device, so playback starts instantly and works without re-fetching. Collection is paced to resemble ordinary human browsing.

**Built with:** Flutter · Dart · Android (Kotlin) · embedded WebView · on-device audio playback and caching.

## Getting started

Requirements: Flutter 3.24+ and JDK 17.

```bash
flutter pub get
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

Install the APK, open the app, sign in to your own account in the embedded page, and playback begins automatically. A short walkthrough (Chinese) is available in [`README_使用说明.md`](README_使用说明.md).

## Privacy

- No backend, no analytics, no account. Everything runs locally.
- Your login is stored only on your device and is never transmitted to any third party.

## Disclaimer

xlisten is provided for **personal and educational use** and is intended to read **your own** timeline. Automated access to a platform may be restricted by that platform's Terms of Service; you are responsible for ensuring your use complies with them, and you accept any associated risk to your account. The software is provided "as is", without warranty of any kind. It is not affiliated with, endorsed by, or sponsored by X Corp. or any other company.

## License

Released under the [MIT License](LICENSE).
