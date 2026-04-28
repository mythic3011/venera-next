import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';

void main() {
  test('resolveNaviPaneTarget_returns_0_below_600', () {
    expect(resolveNaviPaneTarget(320), 0);
    expect(resolveNaviPaneTarget(599.99), 0);
  });

  test('resolveNaviPaneTarget_returns_2_from_600_to_below_1300', () {
    expect(resolveNaviPaneTarget(600), 2);
    expect(resolveNaviPaneTarget(700), 2);
    expect(resolveNaviPaneTarget(839.99), 2);
    expect(resolveNaviPaneTarget(840), 2);
    expect(resolveNaviPaneTarget(1299.99), 2);
  });

  test('resolveNaviPaneTarget_returns_3_from_1300', () {
    expect(resolveNaviPaneTarget(1300), 3);
    expect(resolveNaviPaneTarget(1440), 3);
  });
}
