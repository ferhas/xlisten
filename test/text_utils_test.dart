import 'package:flutter_test/flutter_test.dart';
import 'package:xlisten/core/text_utils.dart';

void main() {
  group('detectLang', () {
    test('中文为主 → zh', () {
      expect(detectLang('如果我醒来时超重14公斤，想在夏天前减掉所有体重'), 'zh');
    });
    test('长英文 → en', () {
      expect(detectLang('Hello world this is a long english sentence here'), 'en');
    });
    test('短混合 → other', () {
      expect(detectLang('OK 好'), 'other');
    });
  });

  group('isEnglish', () {
    test('英文带链接 → true（剥链接后仍英文）', () {
      expect(
          isEnglish('Check this out https://t.co/abcdefghijklmnop more text here'),
          isTrue);
    });
    test('中文带长链接 → false（链接碎片不算英文）', () {
      expect(
          isEnglish('看这个 https://t.co/abcdefghijklmnop 视频很有意思啊朋友们一起来'),
          isFalse);
    });
  });

  group('clean', () {
    test('换行→逗号、折叠空白', () {
      expect(clean('a\n\nb   c'), 'a，b，c');
    });
    test('剥链接', () {
      expect(clean('看 https://t.co/abcdefghijklmnop 这个'), '看，这个');
    });
  });

  group('parseNum', () {
    test('带逗号数字', () => expect(parseNum('1,234 likes'), 1234));
    test('开头数字', () => expect(parseNum('28 Replies'), 28));
    test('无数字 → null', () => expect(parseNum('查看'), isNull));
    test('null → null', () => expect(parseNum(null), isNull));
  });

  group('itemKey', () {
    test('有 url 用 url', () {
      expect(itemKey('@x', 'text', 'https://x.com/s/1'), 'https://x.com/s/1');
    });
    test('无 url 用 handle|head', () {
      expect(itemKey('@x', 'hello', ''), '@x|hello');
    });
  });

  group('makeReadingText', () {
    test('正常 → 作者：正文', () {
      expect(makeReadingText('硅基人老王', '如果我醒来时超重14公斤想减肥'),
          '硅基人老王：如果我醒来时超重14公斤想减肥');
    });
    test('过短 → null', () {
      expect(makeReadingText('a', '短'), isNull);
    });
  });

  group('stripUrls', () {
    test('去 http 链接与长 ASCII 碎片', () {
      final r = stripUrls('hi https://t.co/abc then abcdefghijklmnopqrst end');
      expect(r.contains('https'), isFalse);
      expect(r.contains('abcdefghijklmnopqrst'), isFalse);
      expect(r.contains('hi'), isTrue);
      expect(r.contains('end'), isTrue);
    });
  });
}
