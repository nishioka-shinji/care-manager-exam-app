import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 移植元 .grid-nums 相当。問番号などを並べるグリッド。5 列、380px 超で 6 列。
///
/// 移植元 quiz.css の .quiz-navcell--* は「回答済み/未回答」と「現在地か」が
/// 直交する 2 軸（現在地は枠強調のみで背景と共存する）。[answeredOf] と
/// [currentIndex] を分けて渡すことでこれを再現する。
class NumberGrid extends StatelessWidget {
  const NumberGrid({
    super.key,
    required this.count,
    required this.answeredOf,
    required this.onTap,
    this.labelOf,
    this.currentIndex,
  });

  final int count;
  final bool Function(int index) answeredOf;
  final void Function(int index) onTap;

  /// セルに表示するラベル（実際の問番号など）。未指定時は index+1 を表示する。
  final String Function(int index)? labelOf;

  final int? currentIndex;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 380 ? 6 : 5;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: tokens.tap,
          ),
          itemBuilder: (context, index) {
            return _NumberGridCell(
              label: labelOf != null ? labelOf!(index) : '${index + 1}',
              answered: answeredOf(index),
              isCurrent: index == currentIndex,
              onTap: () => onTap(index),
            );
          },
        );
      },
    );
  }
}

class _NumberGridCell extends StatelessWidget {
  const _NumberGridCell({
    required this.label,
    required this.answered,
    required this.isCurrent,
    required this.onTap,
  });

  final String label;
  final bool answered;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);

    // 背景色は回答済み/未回答の軸、枠色は現在地の軸。移植元 quiz.css の
    // .quiz-navcell--answered/--unanswered と .quiz-navcell--current は
    // 独立して重ねがけされる（現在地は枠強調のみ）。
    // 非現在地の既定枠は style.css の .grid-nums > * にある --border（全セル共通）。
    final background = answered ? theme.colorScheme.primary : tokens.none;
    final foreground = answered ? theme.colorScheme.onPrimary : tokens.onNone;
    final borderColor = isCurrent ? theme.colorScheme.onSurface : tokens.border;
    final borderWidth = isCurrent ? 2.0 : 1.0;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: BoxConstraints(
            minWidth: tokens.tap,
            minHeight: tokens.tap,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: borderWidth),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 15.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
