import 'dart:io';

import 'package:xlisten/services/edge_tts.dart';

/// 手动验证 Edge-TTS 协议：经代理真连微软合成一句中文，写出 mp3。
/// 微软对直连中国 IP 区域封锁，所以这里通过 build_audio.py 同款代理走。
///   dart run tool/tts_spike.dart [代理host:port]
Future<void> main(List<String> args) async {
  final proxy = args.isNotEmpty
      ? args[0]
      : (Platform.environment['HTTPS_PROXY'] ??
              Platform.environment['HTTP_PROXY'] ??
              '')
          .replaceAll('http://', '')
          .replaceAll('https://', '');

  HttpClient? client;
  if (proxy.isNotEmpty) {
    stdout.writeln('使用代理: $proxy');
    client = HttpClient()..findProxy = (uri) => 'PROXY $proxy';
  } else {
    stdout.writeln('未设代理，直连（中国 IP 可能被微软区域封锁）');
  }

  try {
    final sw = Stopwatch()..start();
    final bytes = await EdgeTts.synthesize(
      text: '硅基人老王：你好，这是一条来自 X 时间线收听 App 的测试。',
      voice: 'zh-CN-XiaoxiaoNeural',
      rate: '+20%',
      timeout: const Duration(seconds: 25),
      httpClient: client,
    );
    sw.stop();
    final f = File('tts_spike_out.mp3');
    await f.writeAsBytes(bytes);
    final id3 =
        bytes.length >= 3 && bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
    final frame = bytes.isNotEmpty && bytes[0] == 0xFF;
    stdout.writeln('✅ OK: ${bytes.length} 字节, ${sw.elapsedMilliseconds}ms, '
        'mp3=${id3 || frame} -> ${f.absolute.path}');
  } catch (e) {
    stdout.writeln('❌ FAIL: $e');
    exitCode = 1;
  } finally {
    client?.close();
  }
}
