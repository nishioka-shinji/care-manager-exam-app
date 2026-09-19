import 'package:care_manager_exam_app/theme/app_theme.dart';
import 'package:care_manager_exam_app/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ライトテーマから AppTokens.light の値が引ける', () {
    final tokens = AppTheme.light.extension<AppTokens>();

    expect(tokens, isNotNull);
    expect(tokens!.surface2, const Color(0xffeef0f5));
    expect(tokens.border, const Color(0xffdde1e8));
    expect(tokens.muted, const Color(0xff6b7280));
    expect(tokens.ok, const Color(0xff1a9e5c));
    expect(tokens.ng, const Color(0xffd64545));
    expect(tokens.none, const Color(0xff9aa1ae));
    expect(tokens.onOk, const Color(0xff0b1020));
    expect(tokens.onNg, const Color(0xff000000));
    expect(tokens.onNone, const Color(0xff0b1020));
    expect(tokens.radius, 12.0);
    expect(tokens.tap, 44.0);
    expect(tokens.barHeight, 64.0);
    expect(AppTheme.light.scaffoldBackgroundColor, const Color(0xfff5f6fa));
    expect(AppTheme.light.colorScheme.primary, const Color(0xff2f6fed));
  });

  test('ダークテーマから AppTokens.dark の値が引ける', () {
    final tokens = AppTheme.dark.extension<AppTokens>();

    expect(tokens, isNotNull);
    expect(tokens!.surface2, const Color(0xff262835));
    expect(tokens.border, const Color(0xff33364a));
    expect(tokens.ok, const Color(0xff3ecf8e));
    expect(tokens.ng, const Color(0xffff6b6b));
    expect(tokens.none, const Color(0xff6b7280));
    // onOk/onNg はライトと同じ値のまま流用する。
    expect(tokens.onOk, const Color(0xff0b1020));
    expect(tokens.onNg, const Color(0xff000000));
    expect(tokens.onNone, const Color(0xffffffff));
    expect(AppTheme.dark.scaffoldBackgroundColor, const Color(0xff12131a));
    expect(AppTheme.dark.colorScheme.primary, const Color(0xff6f9bff));
  });
}
