import 'package:flutter/material.dart';

import '../../../core/models/exam.dart';
import '../../../core/models/session.dart';
import '../../../core/scoring.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_card.dart';

/// 分野別得点カード。移植元 result.js の buildSectionBreakdown 相当。
/// 70% の位置に参考ラインの破線を描くが、合否判定はしない（不変条件1）。
class SectionBreakdownCard extends StatelessWidget {
  const SectionBreakdownCard({
    super.key,
    required this.exam,
    required this.score,
  });

  final Exam exam;
  final Score score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('分野別の得点', style: theme.textTheme.titleMedium),
          for (final section in exam.sections) ...[
            const SizedBox(height: 16),
            _SectionRow(name: section.name, pair: score.bySection[section.id]),
          ],
          const SizedBox(height: 16),
          Text(
            '点線は参考ライン（70%）です。合格基準は年度ごとに補正されるため、'
            'ここでは合否判定を行いません。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.name, required this.pair});

  final String name;
  final SectionScore? pair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final correct = pair?.correct ?? 0;
    final count = pair?.count ?? 0;
    final rate = count == 0 ? 0.0 : correct / count;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '$correct / $count（${formatRate(correct, count)}）',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          label: '正答率 ${formatRate(correct, count)}',
          child: _SectionBar(rate: rate),
        ),
      ],
    );
  }
}

/// 正答率バー本体。高さ14px・角丸999、70%位置に2px dashed の目安線
/// （opacity 0.55）を描く。目安線は参考表示のみで判定には使わない。
class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.rate});

  final double rate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 14,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: tokens.surface2),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: rate.clamp(0.0, 1.0),
              child: Container(color: theme.colorScheme.primary),
            ),
            CustomPaint(
              painter: _TargetLinePainter(color: theme.colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

/// 70% 位置の 2px dashed 縦線（opacity 0.55）。
class _TargetLinePainter extends CustomPainter {
  const _TargetLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * 0.7;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 2;
    const dashHeight = 3.0;
    const dashGap = 2.0;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(Offset(x, y), Offset(x, y + dashHeight), paint);
      y += dashHeight + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant _TargetLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
