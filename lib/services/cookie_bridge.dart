import 'package:flutter/services.dart';

/// 原生 cookie 桥:读 WebView 真实 cookie(含 HttpOnly)、强制落盘。
class CookieBridge {
  static const MethodChannel _ch = MethodChannel('xlisten/cookies');

  /// 返回 "k=v; k2=v2; ..." 或 null。
  static Future<String?> getCookies(String url) async {
    try {
      return await _ch.invokeMethod<String>('get', {'url': url});
    } catch (_) {
      return null;
    }
  }

  /// 写入一条带过期时间的持久 cookie(cookie 串形如
  /// "auth_token=xxx; Domain=.x.com; Path=/; Max-Age=31536000; Secure")。
  static Future<void> setCookie(String url, String cookie) async {
    try {
      await _ch.invokeMethod('set', {'url': url, 'cookie': cookie});
    } catch (_) {}
  }

  /// 强制把 cookie 落盘(防止进程被杀后登录丢失)。
  static Future<void> flush() async {
    try {
      await _ch.invokeMethod('flush');
    } catch (_) {}
  }

  /// 从 cookie 串里抽出 auth_token / ct0。
  static Map<String, String> parse(String? cookieStr) {
    final out = <String, String>{};
    if (cookieStr == null) return out;
    for (final part in cookieStr.split(';')) {
      final i = part.indexOf('=');
      if (i > 0) {
        final k = part.substring(0, i).trim();
        final v = part.substring(i + 1).trim();
        if (k == 'auth_token' || k == 'ct0') out[k] = v;
      }
    }
    return out;
  }
}
