/// Edge-TTS 中文音色与语速档位。
class VoiceOption {
  final String id; // Edge-TTS voice id
  final String name; // 显示名
  final String desc; // 简短描述
  const VoiceOption(this.id, this.name, this.desc);
}

const List<VoiceOption> kVoices = [
  VoiceOption('zh-CN-XiaoxiaoNeural', '晓晓', '女声 · 默认'),
  VoiceOption('zh-CN-YunxiNeural', '云希', '男声 · 沉稳'),
  VoiceOption('zh-CN-YunyangNeural', '云扬', '男声 · 新闻播报'),
  VoiceOption('zh-CN-XiaoyiNeural', '晓伊', '女声 · 亲和'),
  VoiceOption('zh-CN-YunjianNeural', '云健', '男声 · 浑厚'),
  VoiceOption('zh-CN-liaoning-XiaobeiNeural', '辽宁小北', '东北女声'),
];

VoiceOption voiceById(String id) =>
    kVoices.firstWhere((v) => v.id == id, orElse: () => kVoices.first);

class SpeedOption {
  final double mult; // 1.2 等显示倍数
  final String rate; // SSML rate,如 '+20%'
  const SpeedOption(this.mult, this.rate);
  String get label => '${mult.toStringAsFixed(mult % 1 == 0 ? 0 : 1)}×';
}

const List<SpeedOption> kSpeeds = [
  SpeedOption(0.8, '-20%'),
  SpeedOption(1.0, '+0%'),
  SpeedOption(1.2, '+20%'), // 默认
  SpeedOption(1.5, '+50%'),
  SpeedOption(1.8, '+80%'),
  SpeedOption(2.0, '+100%'),
];

const String kDefaultVoice = 'zh-CN-XiaoxiaoNeural';
const String kDefaultRate = '+20%';

SpeedOption speedByRate(String rate) =>
    kSpeeds.firstWhere((s) => s.rate == rate, orElse: () => kSpeeds[2]);
