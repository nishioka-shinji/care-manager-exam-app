import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 移植元 .grid-nums 相当。問番号などを並べるグリッド。5 列、380px 超で 6 列。
enum NumberGridCellState { answered, unanswered, current }

class NumberGrid extends StatelessWidget {
  const NumberGrid({
    super.key,
    required this.count,
    required this.stateOf,
    required this.onTap,
  });

  final int count;
  final NumberGridCellState Function(int index) stateOf;
  final void Function(int index) onTap;

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
            final cellState = stateOf(index);
            return _NumberGridCell(
              label: '${index + 1}',
              state: cellState,
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
    required this.state,
    required this.onTap,
  });

  final String label;
  final NumberGridCellState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);

    Color background;
    Color foreground;
    Color borderColor;
    switch (state) {
      case NumberGridCellState.answered:
        background = tokens.ok;
        foreground = tokens.onOk;
        borderColor = tokens.ok;
      case NumberGridCellState.unanswered:
        background = tokens.none;
        foreground = tokens.onNone;
        borderColor = tokens.none;
      case NumberGridCellState.current:
        background = theme.colorScheme.surface;
        foreground = theme.colorScheme.onSurface;
        borderColor = theme.colorScheme.primary;
    }

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
            border: Border.all(color: borderColor, width: 1),
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
