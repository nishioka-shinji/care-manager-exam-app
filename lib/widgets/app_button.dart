import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 移植元 .btn(基底) / .btn--primary / .btn--ghost / .btn--danger 相当。
/// base が無指定時の .btn 基底（surface-2 背景）に対応する。
enum AppButtonVariant { base, primary, ghost, danger }

/// min 44x44・padding 縦10横18・radius 12。disabled は opacity 0.5。
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.base,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);
    final disabled = onPressed == null;

    final Color background;
    final Color foreground;
    final Color borderColor;
    switch (variant) {
      case AppButtonVariant.base:
        background = tokens.surface2;
        foreground = theme.colorScheme.onSurface;
        borderColor = tokens.border;
      case AppButtonVariant.primary:
        background = theme.colorScheme.primary;
        foreground = theme.colorScheme.onPrimary;
        borderColor = theme.colorScheme.primary;
      case AppButtonVariant.ghost:
        background = Colors.transparent;
        foreground = theme.colorScheme.onSurface;
        borderColor = tokens.border;
      case AppButtonVariant.danger:
        background = tokens.ng;
        foreground = tokens.onNg;
        borderColor = tokens.ng;
    }

    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(tokens.radius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(tokens.radius),
          child: Container(
            constraints: BoxConstraints(
              minWidth: tokens.tap,
              minHeight: tokens.tap,
            ),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: 1),
              borderRadius: BorderRadius.circular(tokens.radius),
            ),
            alignment: Alignment.center,
            // 移植元は折り返す（.btn に white-space 指定が無い）が、外側の
            // 下部バーは高さ固定のため折り返すと文字が上下に切れる。
            // FittedBox で 1 行に収まるよう縮小し、全文を読めるようにする。
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: foreground,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
