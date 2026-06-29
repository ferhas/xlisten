import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/voices.dart';
import 'edge_tts.dart';

/// 把 Edge-TTS 合成的 mp3 落到【持久】目录,做 LRU 缓存:只保留最近 [_cap] 条,
/// 命中缓存直接返回(可离线重听、不重新合成、不再联网),超量删最旧。
/// 文件名按 (id|voice|rate) 取 md5,改音色/语速自然换文件,避免 stale 重放。
class TtsService {
  String rate;
  String voice;

  TtsService({this.rate = kDefaultRate, this.voice = kDefaultVoice});

  static const int _cap = 100; // 缓存上限 100 条(预生成全部未读用)
  static const String _lruKey = 'audio_lru_v1';
  Directory? _dir;

  Future<Directory> _audioDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory(); // 持久,不像 temp 会被系统清
    final d = Directory('${base.path}/audio');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  /// 解析这条实际用的音色:非随机直接用 voice;随机则按 id 稳定地挑一个具体音色
  /// (同一条始终同一个 → 缓存稳定;不同条不同 → 听起来随机)。
  String _effectiveVoice(String id) {
    if (voice != kRandomVoice) return voice;
    final cs = concreteVoices();
    final b = md5.convert(utf8.encode(id)).bytes;
    final n = ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) % cs.length;
    return cs[n].id;
  }

  String _hash(String id) =>
      md5.convert(utf8.encode('$id|${_effectiveVoice(id)}|$rate')).toString();

  Future<File> synthToFile(String text, String id) async {
    final dir = await _audioDir();
    final h = _hash(id);
    final f = File('${dir.path}/tts_$h.mp3');
    final p = await SharedPreferences.getInstance();
    final lru = p.getStringList(_lruKey) ?? [];

    if (await f.exists() && await f.length() > 0) {
      lru.remove(h);
      lru.add(h); // 命中 → 移到队尾(最近用)
      await p.setStringList(_lruKey, lru);
      return f;
    }

    final bytes = await EdgeTts.synthesize(
        text: text, rate: rate, voice: _effectiveVoice(id));
    await f.writeAsBytes(bytes, flush: true);
    lru.remove(h);
    lru.add(h);
    while (lru.length > _cap) {
      final old = lru.removeAt(0); // 删最旧
      try {
        final of = File('${dir.path}/tts_$old.mp3');
        if (await of.exists()) await of.delete();
      } catch (_) {}
    }
    await p.setStringList(_lruKey, lru);
    return f;
  }

  /// 该条是否已有缓存(可离线重听)。
  Future<bool> isCached(String id) async {
    final dir = await _audioDir();
    final f = File('${dir.path}/tts_${_hash(id)}.mp3');
    return await f.exists() && await f.length() > 0;
  }

  /// 同步缓存检查(供后台预合成快速跳过)。_dir 未初始化时返回 false(保守)。
  bool isCachedSync(String id) {
    final d = _dir;
    if (d == null) return false;
    final f = File('${d.path}/tts_${_hash(id)}.mp3');
    return f.existsSync() && f.lengthSync() > 0;
  }

  /// 预热:确保音频目录已建好,让 isCachedSync 立即可用。
  Future<void> warmup() async {
    await _audioDir();
  }

  /// 试听:合成样例到 temp(不进 LRU 缓存)。随机音色时用第一个具体音色示范。
  Future<File> synthSample(String text) async {
    final v = voice == kRandomVoice ? concreteVoices().first.id : voice;
    final bytes = await EdgeTts.synthesize(text: text, rate: rate, voice: v);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/tts_sample.mp3');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }
}
