import 'package:flutter/material.dart';

import '../../../core/models/choice.dart';
import '../../../core/models/exam.dart';
import '../../../core/models/question.dart';
import '../../../core/scoring.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_badge.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/footer_credit.dart';
import '../../../widgets/result_mark.dart';

/// 問ごとの解説カード。移植元 result.js の buildExplanationBlock 相当。
/// 選択肢ごとに「正解」「あなたの回答」マークと解説文を出し、末尾に出典を
/// 媒体名のみで表示する（T7 の年度カードと同じ方針。生 URL は出さない）。
class ExplanationCard extends StatelessWidget {
  const ExplanationCard({super.key, required this.exam, required this.result});

  final Exam exam;
  final QuestionResult result;

  Question? get _question {
    for (final q in exam.questions) {
      if (q.no == result.no) return q;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final question = _question;
    if (question == null) {
      return AppCard(
        child: Text(
          '問${result.no} のデータが見つかりません。',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final AppBadgeStatus status;
    final String statusLabel;
    if (result.correct) {
      status = AppBadgeStatus.ok;
      statusLabel = '正解';
    } else if (result.answered) {
      status = AppBadgeStatus.ng;
      statusLabel = '不正解';
    } else {
      status = AppBadgeStatus.none;
      statusLabel = '未回答';
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('問${result.no}', style: theme.textTheme.titleMedium),
              AppBadge(label: statusLabel, status: status),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            question.text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          for (final choice in question.choices) ...[
            _ChoiceRow(
              choice: choice,
              isAnswer: question.answers.contains(choice.no),
              isSelected: result.selected.contains(choice.no),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            '出典: $kExamSourceMediaName\n解答・解説: ${exam.credit}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.choice,
    required this.isAnswer,
    required this.isSelected,
  });

  final Choice choice;
  final bool isAnswer;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.appTokens;

    Color background = theme.colorScheme.surface;
    if (isAnswer && isSelected) {
      background = Color.alphaBlend(
        tokens.ok.withValues(alpha: 0.14),
        theme.colorScheme.surface,
      );
    } else if (isSelected) {
      background = Color.alphaBlend(
        theme.colorScheme.primary.withValues(alpha: 0.10),
        theme.colorScheme.surface,
      );
    }

    // Border は単色でなければ borderRadius と併用できないため、正解の左アクセント
    // バーは別レイヤーの Container で重ねる（移植元の border-left: 4px と同じ見た目）。
    // Row を stretch させる高さは IntrinsicHeight で内容分に確定させる
    // （親がスクロール内の無限高さ制約のため、そのままでは stretch できない）。
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radius),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: tokens.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: isAnswer ? 4 : 0, color: tokens.ok),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${choice.no}.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: tokens.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            choice.text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isAnswer)
                            const ResultMark(label: '正解', isAnswer: true),
                          if (isSelected)
                            const ResultMark(label: 'あなたの回答', isAnswer: false),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        choice.explanation,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
