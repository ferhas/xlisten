import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 前台服务 + 媒体通知:息屏/后台也能继续朗读,锁屏有播放控制。
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.xlisten.xlisten.channel.audio',
    androidNotificationChannelName: 'xlisten 朗读',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );
  runApp(const XListenApp());
}

class XListenApp extends StatelessWidget {
  const XListenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'X 时间线收听',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D9BF0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1D9BF0)),
        useMaterial3: true,
      ),
      // 尊重系统大字号,仅在 >2.0× 时温和钳制,绝不调小用户选择。
      builder: (ctx, child) {
        final mq = MediaQuery.of(ctx);
        final s = mq.textScaler.scale(1.0).clamp(1.0, 2.0);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(s)),
          child: child!,
        );
      },
      home: const HomeShell(),
    );
  }
}
