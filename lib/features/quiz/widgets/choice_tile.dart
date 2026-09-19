import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';

/// 選択肢1件。移植元 .quiz-choice 相当。選択状態は [selected] の値だけを見て
/// 描き分け、親（設問全体）を作り直さずに済むよう単体で完結させる
/// （不変条件2: このタイルの外側は再構築しない）。
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.no,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final int no;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);

    final borderColor = selected ? theme.colorScheme.primary : tokens.border;
    final background = selected
        ? Color.alphaBlend(
            theme.colorScheme.primary.withValues(alpha: 0.14),
            theme.colorScheme.surface,
          )
        : theme.colorScheme.surface;

    return Semantics(
      checked: selected,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(tokens.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tokens.radius),
          child: Container(
            constraints: BoxConstraints(minHeight: tokens.tap),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: 1),
              borderRadius: BorderRadius.circular(tokens.radius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(top: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: 1),
                    color: selected ? theme.colorScheme.primary : null,
                  ),
                  child: Text(
                    '$no',
                    style: TextStyle(
                      fontSize: 13.6,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
