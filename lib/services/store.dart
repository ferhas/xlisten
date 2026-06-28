import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/voices.dart';
import '../models/timeline_item.dart';

/// 本地持久化:已听 seen 集合、两个未读队列、历史归档、设置。
class Store {
  static const String _kSeen = 'seen_v1';
  static const String _kHistory = 'history_v1';
  static const String _kVoice = 'voice_v1';
  static const String _kRate = 'rate_v1';
  static const String _kAuthCookies = 'auth_cookies_v1';
  static String _queueKey(String tab) => 'queue_${tab}_v1';
  static const int _seenCap = 5000;
  static const int _historyCap = 500;

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  Future<Set<String>> loadSeen() async {
    final s = (await _p).getString(_kSeen);
    if (s == null) return {};
    try {
      return (jsonDecode(s) as List).cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> saveSeen(Set<String> seen) async {
    var list = seen.toList();
    if (list.length > _seenCap) list = list.sublist(list.length - _seenCap);
    await (await _p).setString(_kSeen, jsonEncode(list));
  }

  Future<List<TimelineItem>> loadQueue(String tab) async =>
      _decode((await _p).getString(_queueKey(tab)));

  Future<void> saveQueue(String tab, List<TimelineItem> q) async {
    await (await _p)
        .setString(_queueKey(tab), jsonEncode(q.map((e) => e.toJson()).toList()));
  }

  Future<List<TimelineItem>> loadHistory() async =>
      _decode((await _p).getString(_kHistory));

  Future<void> saveHistory(List<TimelineItem> h) async {
    final list = h.length > _historyCap ? h.sublist(0, _historyCap) : h;
    await (await _p)
        .setString(_kHistory, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  List<TimelineItem> _decode(String? s) {
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List)
          .map((e) => TimelineItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAuthCookies(String authToken, String ct0) async {
    await (await _p).setString(
        _kAuthCookies, jsonEncode({'auth_token': authToken, 'ct0': ct0}));
  }

  Future<Map<String, String>> loadAuthCookies() async {
    final s = (await _p).getString(_kAuthCookies);
    if (s == null) return {};
    try {
      return (jsonDecode(s) as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  Future<void> clearAuthCookies() async =>
      (await _p).remove(_kAuthCookies);

  Future<String> getVoice() async => (await _p).getString(_kVoice) ?? kDefaultVoice;
  Future<void> setVoice(String v) async => (await _p).setString(_kVoice, v);
  Future<String> getRate() async => (await _p).getString(_kRate) ?? kDefaultRate;
  Future<void> setRate(String r) async => (await _p).setString(_kRate, r);
  Future<bool> getBool(String key, bool def) async => (await _p).getBool(key) ?? def;
  Future<void> setBool(String key, bool v) async => (await _p).setBool(key, v);
}
