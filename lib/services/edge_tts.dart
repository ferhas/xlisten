import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 微软 Edge “大声朗读” TTS（无需 API key），直连 WebSocket。
/// 协议常量对照 edge-tts 7.x 源码（Chromium 143），截至 2026-01 有效。
/// 注意：国内需走能访问 speech.platform.bing.com 的网络（与访问 X 同一通道）。
class EdgeTts {
  static const String _trustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const String _chromiumFullVersion = '143.0.3650.75';
  static const String _secMsGecVersion = '1-$_chromiumFullVersion';
  static const int _winEpoch = 11644473600; // 1601→1970 的秒数
  // 用 https 走 HttpClient 手动 Upgrade（不用 WebSocket.connect，见 synthesize 注释）。
  static const String _wssBase =
      'https://speech.platform.bing.com/consumer/speech/synthesize/'
      'readaloud/edge/v1?TrustedClientToken=$_trustedClientToken';

  static final Random _rng = Random.secure();

  /// Sec-MS-GEC：把当前时间换算成 Windows FILETIME ticks、按 5 分钟向下取整，
  /// 拼上 TrustedClientToken 做 SHA-256，输出大写十六进制。
  static String generateSecMsGec({DateTime? now}) {
    final n = (now ?? DateTime.now()).toUtc();
    double ticks = n.millisecondsSinceEpoch / 1000.0;
    ticks += _winEpoch;
    ticks -= ticks % 300; // 向下取整到 5 分钟窗口
    ticks *= 1e9 / 100; // 秒 → 100 纳秒间隔
    final ticksStr = ticks.toStringAsFixed(0);
    final digest = sha256.convert(ascii.encode('$ticksStr$_trustedClientToken'));
    return digest.toString().toUpperCase();
  }

  static String _uuidHex() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _xTimestampGmt(DateTime now) {
    final d = now.toUtc();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${days[d.weekday - 1]} ${months[d.month - 1]} ${p2(d.day)} ${d.year} '
        '${p2(d.hour)}:${p2(d.minute)}:${p2(d.second)} '
        'GMT+0000 (Coordinated Universal Time)';
  }

  static String escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll("'", '&apos;')
      .replaceAll('"', '&quot;');

  static String buildSsml(
    String text, {
    required String voice,
    required String rate,
    String pitch = '+0Hz',
    String volume = '+0%',
  }) {
    return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
        "xml:lang='en-US'><voice name='$voice'>"
        "<prosody pitch='$pitch' rate='$rate' volume='$volume'>"
        "${escapeXml(text)}</prosody></voice></speak>";
  }

  /// 解析一个二进制帧 → mp3 负载；若不是音频帧返回 null。
  /// 帧格式：前 2 字节大端 = 头部长度；头部文本占 [2, 2+len)；音频从 2+len 开始。
  static Uint8List? parseAudioFrame(Uint8List bytes) {
    if (bytes.length < 2) return null;
    final headerLength = (bytes[0] << 8) | bytes[1];
    final audioStart = headerLength + 2;
    if (audioStart > bytes.length) return null;
    final headerStr =
        ascii.decode(bytes.sublist(2, audioStart), allowInvalid: true);
    if (!headerStr.contains('Path:audio')) return null;
    return Uint8List.sublistView(bytes, audioStart);
  }

  /// 合成 [text]，返回完整 mp3 字节。失败抛异常（调用方决定重试/跳过）。
  static Future<Uint8List> synthesize({
    required String text,
    String voice = 'zh-CN-XiaoxiaoNeural',
    String rate = '+20%',
    Duration timeout = const Duration(seconds: 30),
    HttpClient? httpClient, // 可选：自定义 HttpClient（如需走代理）；手机端通常不用
  }) async {
    final now = DateTime.now();
    final url = '$_wssBase'
        '&ConnectionId=${_uuidHex()}'
        '&Sec-MS-GEC=${generateSecMsGec(now: now)}'
        '&Sec-MS-GEC-Version=$_secMsGecVersion';

    // 不用 WebSocket.connect（它对此端点握手会返回 "not upgraded"）；
    // 改为 HttpClient 手动发起 Upgrade（已验证返回 101），再包成 WebSocket。
    final ownClient = httpClient == null;
    final client = httpClient ?? HttpClient();
    final WebSocket ws;
    try {
      final req = await client.openUrl('GET', Uri.parse(url));
      req.followRedirects = false;
      final nonce =
          base64.encode(List<int>.generate(16, (_) => _rng.nextInt(256)));
      req.headers
        ..set(HttpHeaders.connectionHeader, 'Upgrade')
        ..set(HttpHeaders.upgradeHeader, 'websocket')
        ..set('Sec-WebSocket-Key', nonce)
        ..set('Sec-WebSocket-Version', '13')
        ..set('Origin', 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold')
        ..set('Pragma', 'no-cache')
        ..set('Cache-Control', 'no-cache')
        ..set('User-Agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0')
        ..set('Accept-Encoding', 'gzip, deflate, br, zstd')
        ..set('Accept-Language', 'en-US,en;q=0.9');
      final resp = await req.close();
      if (resp.statusCode != HttpStatus.switchingProtocols) {
        throw WebSocketException('Edge-TTS 握手未升级: HTTP ${resp.statusCode}');
      }
      final socket = await resp.detachSocket();
      ws = WebSocket.fromUpgradedSocket(socket, serverSide: false);
    } catch (e) {
      if (ownClient) client.close(force: true);
      rethrow;
    }

    final completer = Completer<Uint8List>();
    final audio = BytesBuilder(copy: false);
    StreamSubscription<dynamic>? sub;

    final to = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Edge-TTS 超时'));
      }
      ws.close();
    });

    sub = ws.listen((message) {
      if (message is String) {
        final sep = message.indexOf('\r\n\r\n');
        final head = sep >= 0 ? message.substring(0, sep) : message;
        if (head.contains('Path:turn.end')) {
          if (!completer.isCompleted) completer.complete(audio.toBytes());
          ws.close();
        }
      } else if (message is List<int>) {
        final payload = parseAudioFrame(Uint8List.fromList(message));
        if (payload != null) audio.add(payload);
      }
    }, onError: (Object e) {
      if (!completer.isCompleted) completer.completeError(e);
    }, onDone: () {
      if (!completer.isCompleted) {
        final b = audio.toBytes();
        if (b.isNotEmpty) {
          completer.complete(b);
        } else {
          completer.completeError(StateError('Edge-TTS 未返回音频'));
        }
      }
    });

    // 1) speech.config（设定 mp3 输出格式）
    ws.add('X-Timestamp:${_xTimestampGmt(now)}\r\n'
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":'
        '{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},'
        '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}\r\n');

    // 2) SSML 合成请求
    final iso = now.toUtc().toIso8601String(); // 形如 2026-06-28T12:34:56.789Z
    ws.add('X-RequestId:${_uuidHex()}\r\n'
        'Content-Type:application/ssml+xml\r\n'
        'X-Timestamp:$iso\r\n'
        'Path:ssml\r\n\r\n'
        '${buildSsml(text, voice: voice, rate: rate)}');

    try {
      return await completer.future;
    } finally {
      to.cancel();
      await sub.cancel();
      if (ownClient) client.close(force: true);
    }
  }
}
