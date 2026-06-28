import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xlisten/services/edge_tts.dart';

void main() {
  group('Sec-MS-GEC token', () {
    test('64 位大写十六进制', () {
      final t = EdgeTts.generateSecMsGec(now: DateTime.utc(2026, 6, 28, 12, 2));
      expect(t, matches(RegExp(r'^[0-9A-F]{64}$')));
    });
    test('同一 5 分钟窗口内相同', () {
      final a = EdgeTts.generateSecMsGec(now: DateTime.utc(2026, 6, 28, 12, 2));
      final b = EdgeTts.generateSecMsGec(now: DateTime.utc(2026, 6, 28, 12, 3));
      expect(a, b);
    });
    test('跨窗口不同', () {
      final a = EdgeTts.generateSecMsGec(now: DateTime.utc(2026, 6, 28, 12, 2));
      final c = EdgeTts.generateSecMsGec(now: DateTime.utc(2026, 6, 28, 12, 7));
      expect(a, isNot(c));
    });
  });

  group('buildSsml', () {
    final s = EdgeTts.buildSsml('你好<b>', voice: 'zh-CN-XiaoxiaoNeural', rate: '+20%');
    test('含 voice', () => expect(s.contains("name='zh-CN-XiaoxiaoNeural'"), isTrue));
    test('含 rate', () => expect(s.contains("rate='+20%'"), isTrue));
    test('XML 转义', () => expect(s.contains('&lt;b&gt;'), isTrue));
    test('含正文', () => expect(s.contains('你好'), isTrue));
  });

  group('parseAudioFrame', () {
    test('提取音频负载', () {
      const header ='X-RequestId:abc\r\nContent-Type:audio/mpeg\r\nPath:audio\r\n';
      final headerBytes = ascii.encode(header);
      final len = headerBytes.length;
      final payload = [10, 20, 30, 40];
      final frame = Uint8List.fromList(
          [(len >> 8) & 0xff, len & 0xff, ...headerBytes, ...payload]);
      final out = EdgeTts.parseAudioFrame(frame);
      expect(out, equals(Uint8List.fromList(payload)));
    });

    test('非音频帧返回 null', () {
      const header ='Path:turn.start\r\n';
      final headerBytes = ascii.encode(header);
      final len = headerBytes.length;
      final frame =
          Uint8List.fromList([(len >> 8) & 0xff, len & 0xff, ...headerBytes]);
      expect(EdgeTts.parseAudioFrame(frame), isNull);
    });
  });
}
