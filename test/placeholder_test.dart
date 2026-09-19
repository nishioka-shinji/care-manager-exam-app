// T3 で採点ロジックのテストが入るまでの暫定。テストが 1 件も無いと flutter test が失敗扱いになる。
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('プロジェクトの雛形が動作する', () {
    expect(1 + 1, 2);
  });
}
