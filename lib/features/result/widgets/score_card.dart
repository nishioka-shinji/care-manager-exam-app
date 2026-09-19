import 'package:flutter/material.dart';

import '../../../core/models/session.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_card.dart';

/// モードの表示ラベル。移植元 result.js の modeLabel と同じ。
String modeLabel(QuizMode mode) => mode == QuizMode.review ? '復習' : '本番通し';

/// ISO 文字列をローカル日時表記に整形する。壊れていれば元の値をそのまま返す。
/// 移植元 result.js の formatDateTime と同じ規則。
String formatDateTime(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso.isEmpty ? '-' : iso;
  final local = parsed.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$y/$m/$d $hh:$mm';
}

/// 総合点カード。移植元 result.js の buildScoreCard 相当。
/// 大きな数字（41.6px w800）と、合否判定は行わない旨の注記を表示する。
class ScoreCard extends StatelessWidget {
  const ScoreCard({super.key, required this.session, required this.score});

  final Session session;
  final Score score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.appTokens;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '${formatDateTime(session.finishedAt)}・${modeLabel(session.mode)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${score.total}',
                  style: theme.textTheme.displayLarge,
                ),
                TextSpan(
                  text: ' / ',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: tokens.muted,
                  ),
                ),
                TextSpan(
                  text: '${score.max}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: tokens.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('総合得点（合否判定は行いません）', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
