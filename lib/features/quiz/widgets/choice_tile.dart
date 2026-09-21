import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../../widgets/result_mark.dart';

/// 選択肢1件。移植元 .quiz-choice 相当。選択・答え合わせ済み（[revealed]）の
/// どちらも自身の上書きだけで描き、親（設問全体）を作り直さない
/// （不変条件2。drill の描画は移植元 quiz.js:305-345 の applyFeedback 相当）。
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.no,
    required this.text,
    required this.selected,
    required this.onTap,
    this.revealed = false,
    this.isAnswer = false,
    this.explanation,
  });

  final int no;
  final String text;
  final bool selected;
  final VoidCallback onTap;
  final bool revealed;
  final bool isAnswer;
  final String? explanation;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);

    final Color borderColor;
    Color background;
    if (revealed) {
      // 答え合わせ後は選択中の青枠をやめ、正解／誤選択の色だけで示す
      // （移植元 quiz-choice--answer / --miss）。
      borderColor = tokens.border;
      background = theme.colorScheme.surface;
      if (isAnswer && selected) {
        background = Color.alphaBlend(
          tokens.ok.withValues(alpha: 0.14),
          theme.colorScheme.surface,
        );
      } else if (selected) {
        background = Color.alphaBlend(
          theme.colorScheme.primary.withValues(alpha: 0.10),
          theme.colorScheme.surface,
        );
      }
    } else {
      borderColor = selected ? theme.colorScheme.primary : tokens.border;
      background = selected
          ? Color.alphaBlend(
              theme.colorScheme.primary.withValues(alpha: 0.14),
              theme.colorScheme.surface,
            )
          : theme.colorScheme.surface;
    }

    return Semantics(
      checked: selected,
      // 答え合わせ後は選択を変更できない（移植元 aria-disabled、quiz.js:330）。
      enabled: !revealed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radius),
        child: Container(
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: borderColor, width: 1),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: revealed && isAnswer ? 4 : 0,
                  color: tokens.ok,
                ),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: revealed ? null : onTap,
                      child: Container(
                        constraints: BoxConstraints(minHeight: tokens.tap),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 14,
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
                                border: Border.all(
                                  color: borderColor,
                                  width: 1,
                                ),
                                color: selected && !revealed
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                              child: Text(
                                '$no',
                                style: TextStyle(
                                  fontSize: 13.6,
                                  fontWeight: FontWeight.w700,
                                  color: selected && !revealed
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        text,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(height: 1.6),
                                      ),
                                      if (revealed && isAnswer)
                                        const ResultMark(
                                          label: '正解',
                                          isAnswer: true,
                                        ),
                                      if (revealed && selected)
                                        const ResultMark(
                                          label: 'あなたの回答',
                                          isAnswer: false,
                                        ),
                                    ],
                                  ),
                                  if (revealed && explanation != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      explanation!,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
