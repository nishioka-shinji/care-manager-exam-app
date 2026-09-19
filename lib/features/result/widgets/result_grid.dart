import 'package:flutter/material.dart';

import '../../../core/scoring.dart';
import '../../../widgets/app_badge.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/number_grid.dart';

/// 全問の正誤一覧グリッド。移植元 result.js の buildGridNums 相当。
/// 移植元 .grid-nums のレイアウト（5/6 列・44px タップ領域）は演習画面の
/// 回答状況シートと共通のため [NumberGrid] を使う（統合レビュー F1）。
/// タップで [onTapNo] を呼び、画面側が該当問の解説へスクロールする。
class ResultGrid extends StatelessWidget {
  const ResultGrid({super.key, required this.results, required this.onTapNo});

  final List<QuestionResult> results;
  final void Function(int no) onTapNo;

  AppBadgeStatus _statusOf(QuestionResult r) {
    if (r.correct) return AppBadgeStatus.ok;
    if (r.answered) return AppBadgeStatus.ng;
    return AppBadgeStatus.none;
  }

  String _labelOf(QuestionResult r) {
    if (r.correct) return '正解';
    if (r.answered) return '不正解';
    return '未回答';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (results.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('正誤一覧', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('回答記録がありません。', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('正誤一覧', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          // セルは問番号しか表示しないため、正誤は読み上げ用のラベルで補う。
          // 色だけに頼るとスクリーンリーダーで区別できないため。
          NumberGrid(
            count: results.length,
            labelOf: (index) => '${results[index].no}',
            statusOf: (index) => _statusOf(results[index]),
            semanticsLabelOf: (index) =>
                '問${results[index].no}（${_labelOf(results[index])}）。タップで解説へ移動',
            onTap: (index) => onTapNo(results[index].no),
          ),
        ],
      ),
    );
  }
}
