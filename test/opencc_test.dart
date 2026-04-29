import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/opencc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hasChineseSimplified scans every rune', () async {
    await OpenCC.init();

    expect(OpenCC.hasChineseSimplified('简体'), isTrue);
    expect(OpenCC.hasChineseSimplified('繁體'), isFalse);
  });
}
