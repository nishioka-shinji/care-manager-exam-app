import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 移植元 .badge / .badge--ok / .badge--ng / .badge--none 相当。
/// 文字色は状態ごとの on* トークンを使う（固定色だと dark で WCAG AA を割り込む）。
enum AppBadgeStatus { ok, ng, none }

class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.label, required this.status});

  final String label;
  final AppBadgeStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final Color background;
    final Color foreground;
    switch (status) {
      case AppBadgeStatus.ok:
        background = tokens.ok;
        foreground = tokens.onOk;
      case AppBadgeStatus.ng:
        background = tokens.ng;
        foreground = tokens.onNg;
      case AppBadgeStatus.none:
        background = tokens.none;
        foreground = tokens.onNone;
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
