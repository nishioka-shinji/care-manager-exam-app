import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// 移植元 public/css/style.css のトークンをそのまま Flutter の [ThemeData] に写す。
/// ColorScheme で表現できない値（surface2/ok/ng/none/on*/border/muted）は
/// [AppTokens] の ThemeExtension で補う。
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(
    brightness: Brightness.light,
    bg: const Color(0xfff5f6fa),
    surface: const Color(0xffffffff),
    text: const Color(0xff1a1d29),
    accent: const Color(0xff2f6fed),
    accentText: const Color(0xffffffff),
    tokens: AppTokens.light,
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    bg: const Color(0xff12131a),
    surface: const Color(0xff1c1e29),
    text: const Color(0xffeef0f5),
    accent: const Color(0xff6f9bff),
    accentText: const Color(0xff0b1020),
    tokens: AppTokens.dark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color text,
    required Color accent,
    required Color accentText,
    required AppTokens tokens,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: accentText,
      secondary: accent,
      onSecondary: accentText,
      error: tokens.ng,
      onError: tokens.onNg,
      surface: surface,
      onSurface: text,
    );

    final textTheme = TextTheme(
      // 本文 16px / line-height 1.6（移植元 body の指定）。
      bodyMedium: TextStyle(fontSize: 16, height: 1.6, color: text),
      bodyLarge: TextStyle(fontSize: 16, height: 1.6, color: text),
      // 見出し 1.1rem(17.6px) w700。
      titleLarge: TextStyle(
        fontSize: 17.6,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      // セクション見出し 1.05rem(16.8px) w700。
      titleMedium: TextStyle(
        fontSize: 16.8,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      // 補助テキスト 0.8〜0.9rem(12.8〜14.4px)。
      bodySmall: TextStyle(fontSize: 14.4, color: tokens.muted),
      labelSmall: TextStyle(fontSize: 12.8, color: tokens.muted),
      // 結果画面の総合点 2.6rem(41.6px) w800。
      displayLarge: TextStyle(
        fontSize: 41.6,
        fontWeight: FontWeight.w800,
        color: text,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      textTheme: textTheme,
      dividerColor: tokens.border,
      extensions: [tokens],
    );
  }
}
