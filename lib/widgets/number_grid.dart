import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_badge.dart';

/// 移植元 .grid-nums 相当。問番号などを並べるグリッド。5 列、
/// viewport 幅 380px 以上で 6 列（移植元 style.css の @media は viewport 基準）。
///
/// セルの色軸は呼び出し元によって異なる。演習画面の回答状況シートは
/// 「回答済み/未回答」の2値（[answeredOf]）、結果画面の正誤一覧は
/// 「正解/不正解/未回答」の3値（[statusOf]）を使うため両方受け付ける。
/// 一問一答モードの回答状況シートのように「正解/不正解/回答済み/未回答」の
/// 4値が同時に必要な場合は [cellStatusOf] を使う。
/// 移植元でも色が違う（回答済み=accent、正解=ok）ため内部で区別して塗る。
/// 移植元 quiz.css の .quiz-navcell--* は色軸と「現在地か」が直交する
/// 2 軸（現在地は枠強調のみで背景と共存する）で、[currentIndex] はこれを再現する。
class NumberGrid extends StatelessWidget {
  const NumberGrid({
    super.key,
    required this.count,
    required this.onTap,
    this.answeredOf,
    this.statusOf,
    this.cellStatusOf,
    this.labelOf,
    this.semanticsLabelOf,
    this.currentIndex,
  }) : assert(
         answeredOf != null || statusOf != null || cellStatusOf != null,
         'answeredOf か statusOf か cellStatusOf のいずれかを渡してください。',
       );

  final int count;
  final void Function(int index) onTap;

  /// 回答済み/未回答の2値軸（演習画面の回答状況シート用）。
  final bool Function(int index)? answeredOf;

  /// 正解/不正解/未回答の3値軸（結果画面の正誤一覧用）。
  final AppBadgeStatus Function(int index)? statusOf;

  /// 正解/不正解/回答済み/未回答の4値軸（一問一答モードの回答状況シート用）。
  /// [answeredOf] / [statusOf] との併用は非推奨（既存呼び出し元の互換のため
  /// 型としては許すが、新規呼び出しでは他を消してこれ単独で使うこと）。
  /// 併用時はこちらが優先し、他のコールバックは無視される。
  final CellStatus Function(int index)? cellStatusOf;

  /// セルに表示するラベル（実際の問番号など）。未指定時は index+1 を表示する。
  final String Function(int index)? labelOf;

  /// セルの Semantics ラベル。未指定時はラベルのテキストのみになる。
  final String Function(int index)? semanticsLabelOf;

  final int? currentIndex;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    // viewport 幅で判定する（移植元の @media (min-width) はビューポート基準で
    // あり、LayoutBuilder の constraints は画面パディング等を引いた内側の幅の
    // ため、それで判定すると閾値がずれる）。
    final columns = MediaQuery.sizeOf(context).width >= 380 ? 6 : 5;
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
        final CellStatus status;
        if (cellStatusOf != null) {
          status = cellStatusOf!(index);
        } else if (statusOf != null) {
          status = statusOf!(index)._asCellStatus;
        } else {
          status = answeredOf!(index) ? CellStatus.answered : CellStatus.none;
        }
        return _NumberGridCell(
          label: labelOf != null ? labelOf!(index) : '${index + 1}',
          semanticsLabel: semanticsLabelOf?.call(index),
          status: status,
          isCurrent: index == currentIndex,
          onTap: () => onTap(index),
        );
      },
    );
  }
}

/// [NumberGrid] の色軸。[AppBadgeStatus.ok] は呼び出し元によって
/// 「正解」（ok=緑）と「回答済み」（answered=accent）の2つの意味を持つため、
/// 色マッピングの段階で区別できるようここで分ける。
enum CellStatus { answered, ok, ng, none }

extension on AppBadgeStatus {
  CellStatus get _asCellStatus => switch (this) {
    AppBadgeStatus.ok => CellStatus.ok,
    AppBadgeStatus.ng => CellStatus.ng,
    AppBadgeStatus.none => CellStatus.none,
  };
}

class _NumberGridCell extends StatelessWidget {
  const _NumberGridCell({
    required this.label,
    required this.status,
    required this.isCurrent,
    required this.onTap,
    this.semanticsLabel,
  });

  final String label;
  final CellStatus status;
  final bool isCurrent;
  final VoidCallback onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);

    // 背景色は状態（回答済み/未回答、または正解/不正解/未回答）の軸、枠色は
    // 現在地の軸。移植元 quiz.css の .quiz-navcell--answered/--unanswered と
    // .quiz-navcell--current は独立して重ねがけされる（現在地は枠強調のみ）。
    // 非現在地の既定枠は style.css の .grid-nums > * にある --border（全セル共通）。
    // answered（演習シートの回答済み）は accent、ok（結果画面の正解）は緑と
    // 移植元でも色が違うため、ここで別々にマッピングする（統合レビュー F7）。
    final Color background;
    final Color foreground;
    switch (status) {
      case CellStatus.answered:
        background = theme.colorScheme.primary;
        foreground = theme.colorScheme.onPrimary;
      case CellStatus.ok:
        background = tokens.ok;
        foreground = tokens.onOk;
      case CellStatus.ng:
        background = tokens.ng;
        foreground = tokens.onNg;
      case CellStatus.none:
        background = tokens.none;
        foreground = tokens.onNone;
    }
    final borderColor = isCurrent ? theme.colorScheme.onSurface : tokens.border;
    final borderWidth = isCurrent ? 2.0 : 1.0;

    final cell = Material(
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

    if (semanticsLabel == null) return cell;
    return Semantics(label: semanticsLabel, button: true, child: cell);
  }
}
