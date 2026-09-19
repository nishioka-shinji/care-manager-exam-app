import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 移植元 .card 相当。surface 背景・1px border・radius 12・padding 16。
/// 影は付けない（移植元で影があるのはトーストのみ）。
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: tokens.border, width: 1),
        borderRadius: BorderRadius.circular(tokens.radius),
      ),
      child: child,
    );
  }
}
