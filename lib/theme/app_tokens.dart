import 'package:flutter/material.dart';

/// Material の [ColorScheme] だけでは表現できない移植元 CSS 変数
/// （--surface-2 / --ok / --ng / --none / --on-* / --border / --muted）を
/// 保持する [ThemeExtension]。onOk/onNg/onNone は WCAG AA を満たすために
/// 個別トークン化されたものなので統合しない。
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.surface2,
    required this.border,
    required this.muted,
    required this.ok,
    required this.ng,
    required this.none,
    required this.onOk,
    required this.onNg,
    required this.onNone,
    required this.radius,
    required this.tap,
    required this.barHeight,
  });

  final Color surface2;
  final Color border;
  final Color muted;
  final Color ok;
  final Color ng;
  final Color none;
  final Color onOk;
  final Color onNg;
  final Color onNone;
  final double radius;
  final double tap;
  final double barHeight;

  static const light = AppTokens(
    surface2: Color(0xffeef0f5),
    border: Color(0xffdde1e8),
    muted: Color(0xff6b7280),
    ok: Color(0xff1a9e5c),
    ng: Color(0xffd64545),
    none: Color(0xff9aa1ae),
    onOk: Color(0xff0b1020),
    onNg: Color(0xff000000),
    onNone: Color(0xff0b1020),
    radius: 12.0,
    tap: 44.0,
    barHeight: 64.0,
  );

  // ダークでも 4.5:1 を満たすためライト値を流用する。
  static const dark = AppTokens(
    surface2: Color(0xff262835),
    border: Color(0xff33364a),
    muted: Color(0xff9aa1ae),
    ok: Color(0xff3ecf8e),
    ng: Color(0xffff6b6b),
    none: Color(0xff6b7280),
    onOk: Color(0xff0b1020),
    onNg: Color(0xff000000),
    onNone: Color(0xffffffff),
    radius: 12.0,
    tap: 44.0,
    barHeight: 64.0,
  );

  @override
  AppTokens copyWith({
    Color? surface2,
    Color? border,
    Color? muted,
    Color? ok,
    Color? ng,
    Color? none,
    Color? onOk,
    Color? onNg,
    Color? onNone,
    double? radius,
    double? tap,
    double? barHeight,
  }) {
    return AppTokens(
      surface2: surface2 ?? this.surface2,
      border: border ?? this.border,
      muted: muted ?? this.muted,
      ok: ok ?? this.ok,
      ng: ng ?? this.ng,
      none: none ?? this.none,
      onOk: onOk ?? this.onOk,
      onNg: onNg ?? this.onNg,
      onNone: onNone ?? this.onNone,
      radius: radius ?? this.radius,
      tap: tap ?? this.tap,
      barHeight: barHeight ?? this.barHeight,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      surface2: Color.lerp(surface2, other.surface2, t)!,
      border: Color.lerp(border, other.border, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
      ng: Color.lerp(ng, other.ng, t)!,
      none: Color.lerp(none, other.none, t)!,
      onOk: Color.lerp(onOk, other.onOk, t)!,
      onNg: Color.lerp(onNg, other.onNg, t)!,
      onNone: Color.lerp(onNone, other.onNone, t)!,
      radius: radius,
      tap: tap,
      barHeight: barHeight,
    );
  }
}

extension AppTokensContext on BuildContext {
  AppTokens get appTokens {
    final tokens = Theme.of(this).extension<AppTokens>();
    assert(
      tokens != null,
      'AppTokens が ThemeData.extensions に登録されていません。'
      'AppTheme.light / AppTheme.dark を使ってください。',
    );
    return tokens!;
  }
}
