import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:xlisten/services/edge_tts.dart';

/// 诊断：对 Edge-TTS 端点发一个带 Upgrade 头的原始请求，看微软返回什么状态码/头/体。
Future<void> main() async {
  final rng = Random.secure();
  String hex(int n) =>
      List.generate(n, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  final key = base64.encode(List.generate(16, (_) => rng.nextInt(256)));
  final url =
      'https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1'
      '?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4'
      '&ConnectionId=${hex(16)}'
      '&Sec-MS-GEC=${EdgeTts.generateSecMsGec()}'
      '&Sec-MS-GEC-Version=1-143.0.3650.75';

  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('Upgrade', 'websocket');
    req.headers.set('Connection', 'Upgrade');
    req.headers.set('Sec-WebSocket-Version', '13');
    req.headers.set('Sec-WebSocket-Key', key);
    req.headers.set('Origin', 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold');
    req.headers.set('Pragma', 'no-cache');
    req.headers.set('Cache-Control', 'no-cache');
    req.headers.set('User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0');
    req.headers.set('Accept-Encoding', 'gzip, deflate, br, zstd');
    req.headers.set('Accept-Language', 'en-US,en;q=0.9');
    final resp = await req.close();
    stdout.writeln('STATUS = ${resp.statusCode} ${resp.reasonPhrase}');
    resp.headers.forEach((k, v) => stdout.writeln('  $k: ${v.join(", ")}'));
    final body = await resp.transform(utf8.decoder).join();
    stdout.writeln('BODY(<=400): ${body.length > 400 ? body.substring(0, 400) : body}');
  } catch (e) {
    stdout.writeln('REQUEST ERROR: $e');
  } finally {
    client.close(force: true);
  }
}
