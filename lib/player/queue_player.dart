import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../models/timeline_item.dart';

/// 以「条目身份」为中心的播放器:播放某条 → 合成该条 mp3 → 播 → 完成由外部决定下一条。
/// 队列会变(听完即出队),所以不用 index、用 TimelineItem 身份。
class QueuePlayer {
  QueuePlayer({required this.synthesize});

  /// 合成某条 → 本地 mp3。抛异常表示该条不可读(应跳过)。
  final Future<File> Function(TimelineItem item) synthesize;

  /// 正常播完一条(外部:标记已听 + 决定/播放下一条)。
  Future<void> Function(TimelineItem item)? onCompleted;

  /// 一条【真正开始播放】(合成成功、音源就绪)。失败的条目不会触发,故用于「开始即已读」。
  void Function(TimelineItem item)? onStarted;

  /// 合成/加载失败一条(外部:不标记已听,跳到下一条)。
  Future<void> Function(TimelineItem item)? onFailed;

  /// 手动「下一条」:返回 current 之后那条(不标记已听);null = 到底。
  TimelineItem? Function(TimelineItem current)? onSkipNext;

  /// 预取用:返回 current 之后会播的那条(无副作用)。
  TimelineItem? Function(TimelineItem current)? onPeekNext;

  final AudioPlayer _player = AudioPlayer();
  final Map<String, Future<File>> _cache = {}; // key = item.key
  final StreamController<TimelineItem?> _currentCtl =
      StreamController<TimelineItem?>.broadcast();
  final StreamController<TimelineItem> _completedCtl =
      StreamController<TimelineItem>.broadcast();

  TimelineItem? _current;
  bool _disposed = false;
  StreamSubscription<PlayerState>? _stateSub;

  TimelineItem? get current => _current;
  Stream<TimelineItem?> get currentStream => _currentCtl.stream;
  Stream<TimelineItem> get completedStream => _completedCtl.stream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Duration? get duration => _player.duration;
  bool get playing => _player.playing;
  bool get isCompleted =>
      _player.processingState == ProcessingState.completed;

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    session.interruptionEventStream.listen((e) {
      if (e.begin) _player.pause();
    });
    session.becomingNoisyEventStream.listen((_) => _player.pause());
    _stateSub = _player.playerStateStream
        .where((s) => s.processingState == ProcessingState.completed)
        .listen((_) async {
      final d = _current;
      if (d != null) {
        if (!_completedCtl.isClosed) _completedCtl.add(d);
        if (onCompleted != null) await onCompleted!(d);
      }
    });
  }

  Future<void> playItem(TimelineItem it) async {
    _current = it;
    _emit();
    try {
      final file = await _warm(it);
      if (_disposed) return;
      await _player.setAudioSource(AudioSource.uri(Uri.file(file.path)));
      if (_disposed) return;
      onStarted?.call(it); // 合成成功+音源就绪 → 真正开始,可安全标记已读
      await _player.play();
      final nxt = onPeekNext?.call(it);
      if (nxt != null) _warm(nxt); // 边播边预取下一条
    } catch (_) {
      _cache.remove(it.key);
      if (onFailed != null && !_disposed) await onFailed!(it);
    }
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> seek(Duration p) => _player.seek(p);

  Future<void> next() async {
    final c = _current;
    if (c == null) return;
    final n = onSkipNext?.call(c);
    if (n != null) await playItem(n);
  }

  /// v1:回到开头重听当前条(已听的旧条去「历史」回看)。
  Future<void> previous() async {
    await _player.seek(Duration.zero);
    if (!_player.playing) await _player.play();
  }

  Future<void> stop() async {
    await _player.stop();
    _current = null;
    _emit();
  }

  /// 直接播一个本地文件(试听用):_current=null,完成不触发连读编排。
  Future<void> playSample(String path) async {
    _current = null;
    _emit();
    await _player.setAudioSource(AudioSource.uri(Uri.file(path)));
    await _player.play();
  }

  Future<File> _warm(TimelineItem it) =>
      _cache.putIfAbsent(it.key, () => synthesize(it));

  /// 改音色/语速后:作废尚未播放的预取(保留当前条)。只清内存,不删持久缓存文件。
  Future<void> invalidatePrefetch() async {
    final keep = _current?.key;
    _cache.removeWhere((k, v) => k != keep);
  }

  void _emit() {
    if (!_currentCtl.isClosed) _currentCtl.add(_current);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _stateSub?.cancel();
    await _player.dispose();
    await _currentCtl.close();
    await _completedCtl.close();
    _cache.clear(); // 音频文件由 TtsService 的 LRU 缓存管理,不在此删除
  }
}
