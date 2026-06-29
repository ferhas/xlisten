package com.xlisten.xlisten

import android.webkit.CookieManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 继承 AudioServiceActivity(就是带正确引擎的 FlutterActivity):
// 让 just_audio_background 复用本引擎/同一 isolate,避免再起第二个 isolate 抢库写坏 prefs。
class MainActivity : AudioServiceActivity() {
    private val channelName = "xlisten/cookies"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                val cm = CookieManager.getInstance()
                when (call.method) {
                    // 读出某站点全部 cookie(含 HttpOnly 的 auth_token),用于持久化登录
                    "get" -> {
                        val url = call.argument<String>("url") ?: "https://x.com"
                        result.success(cm.getCookie(url))
                    }
                    // 写入一条带过期时间的【持久】cookie(会话级会重启即失,持久才不丢登录)
                    "set" -> {
                        val url = call.argument<String>("url") ?: "https://x.com"
                        val cookie = call.argument<String>("cookie") ?: ""
                        cm.setCookie(url, cookie)
                        cm.flush()
                        result.success(null)
                    }
                    // 把内存里的 cookie 强制落盘,防止被杀掉登录
                    "flush" -> {
                        cm.flush()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
