import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/session.dart';
import '../../../core/scoring.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/number_grid.dart';
import '../quiz_controller.dart';

/// 回答状況シート。移植元 .sheet + .grid-nums 相当。タップした問へジャンプし
/// 自身を閉じる。共通の [NumberGrid] / Overlay パターンは [ConfirmSheet] に揃える。
class AnswerSheet {
  AnswerSheet._();

  /// [onFinishDrill] は一問一答モードの「ここまでの結果を見る」用。
  /// 移植元 quiz.js:638-641 と同じく、シートを閉じてから呼ぶ。
  static Future<void> show(
    BuildContext context,
    QuizController controller, {
    VoidCallback? onFinishDrill,
  }) {
    final completer = Completer<void>();
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;

    void close() {
      if (!completer.isCompleted) completer.complete();
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (context) => _AnswerSheetOverlay(
        controller: controller,
        onClose: close,
        onJump: (index) {
          controller.goTo(index);
          close();
        },
        onFinishDrill: onFinishDrill == null
            ? null
            : () {
                close();
                onFinishDrill();
              },
      ),
    );

    overlay.insert(entry);
    return completer.future;
  }
}

class _AnswerSheetOverlay extends StatefulWidget {
  const _AnswerSheetOverlay({
    required this.controller,
    required this.onClose,
    required this.onJump,
    required this.onFinishDrill,
  });

  final QuizController controller;
  final VoidCallback onClose;
  final void Function(int index) onJump;
  final VoidCallback? onFinishDrill;

  @override
  State<_AnswerSheetOverlay> createState() => _AnswerSheetOverlayState();
}

class _AnswerSheetOverlayState extends State<_AnswerSheetOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final controller = widget.controller;
    final questionNos = controller.questionNos;
    final isDrill = controller.mode == QuizMode.drill;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.4 * t),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FractionalTranslation(
                translation: Offset(0, 1 - t),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: screenHeight * 0.7),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('回答状況', style: theme.textTheme.titleMedium),
                              AppButton(
                                label: '閉じる',
                                variant: AppButtonVariant.ghost,
                                onPressed: widget.onClose,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isDrill
                                ? 'タップした問題へ移動します。緑は正解・赤は不正解・グレーはまだ答え合わせしていない問題です。'
                                : 'タップした問題へ移動します。グレーは未回答です。',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          NumberGrid(
                            count: questionNos.length,
                            labelOf: (index) => '${questionNos[index]}',
                            cellStatusOf: (index) =>
                                _cellStatusOf(controller, questionNos[index]),
                            currentIndex: controller.cursorIndex,
                            onTap: widget.onJump,
                          ),
                          if (isDrill && widget.onFinishDrill != null) ...[
                            const SizedBox(height: 14),
                            AppButton(
                              label: 'ここまでの結果を見る',
                              variant: AppButtonVariant.primary,
                              onPressed: widget.onFinishDrill,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// グリッド1セル分の状態判定。移植元 quiz.js:455-470 の openSheet と同じ:
/// 答え合わせ済み（drill）は正誤、それ以外は回答済み/未回答の2値で塗る。
CellStatus _cellStatusOf(QuizController controller, int no) {
  final answered = controller.isAnswered(no);
  if (controller.mode == QuizMode.drill && controller.isRevealed(no)) {
    List<int> answers = const [];
    final questions = controller.exam?.questions;
    if (questions != null) {
      for (final q in questions) {
        if (q.no == no) {
          answers = q.answers;
          break;
        }
      }
    }
    final selected = controller.selectionOf(no).value.toList()..sort();
    return isCorrect(selected, answers) ? CellStatus.ok : CellStatus.ng;
  }
  return answered ? CellStatus.answered : CellStatus.none;
}
