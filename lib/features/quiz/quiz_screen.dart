import 'package:flutter/material.dart';

import '../../routes.dart';
import '../../core/models/question.dart';
import '../../core/models/session.dart';
import '../../data/exam_repository.dart';
import '../../data/storage_repository.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_sheet.dart';
import '../../widgets/footer_credit.dart';
import 'quiz_controller.dart';
import 'widgets/answer_sheet.dart';
import 'widgets/choice_tile.dart';

/// 演習画面 #/quiz。移植元 public/js/quiz.js の Dart 版。
///
/// ★不変条件2: 選択肢タップでは設問（問題文・選択肢リスト）を作り直さない。
/// [QuizController] の cursorIndex（設問切替）だけを [ListenableBuilder] で
/// 監視し、選択状態は設問ごとの ValueNotifier に分けて [ChoiceTile] の内側
/// だけを再構築する。ScrollController は設問切替時のみ先頭へ戻す。
class QuizScreen extends StatefulWidget {
  // controller はテストからの差し替え用（省略時は自前で生成する）。
  const QuizScreen({super.key, this.controller});

  final QuizController? controller;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final QuizController _controller;
  final ScrollController _scrollController = ScrollController();
  int? _lastCursorIndex;
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        QuizController(
          examRepository: ExamRepository(),
          storageRepository: StorageRepository(),
        );
    _controller.load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // 注入されたコントローラはテスト側が所有するため、生成した場合のみ破棄する。
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _maybeRedirectHome() {
    if (_redirected) return;
    if (_controller.shouldRedirectHome) {
      _redirected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(Routes.home);
      });
    }
  }

  Future<void> _handleSubmit() async {
    final n = _controller.unansweredCount;
    if (n == 0) {
      await _finish();
      return;
    }
    final confirmed = await ConfirmSheet.show(
      context,
      title: '採点確認',
      message: '未回答が$n問あります。採点しますか？',
      confirmLabel: '採点する',
    );
    if (confirmed) {
      await _finish();
    }
  }

  Future<void> _finish() async {
    final id = await _controller.gradeAndFinish();
    if (id == null || !mounted) return;
    Navigator.of(context).pushReplacementNamed(Routes.result, arguments: id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (_controller.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (_controller.loadError) {
          return const _LoadErrorScaffold();
        }
        _maybeRedirectHome();
        if (_controller.shouldRedirectHome) {
          return const Scaffold(body: SizedBox.shrink());
        }

        // 設問が切り替わったときだけ先頭へ戻す（選択トグルからは呼ばれない）。
        if (_lastCursorIndex != _controller.cursorIndex) {
          _lastCursorIndex = _controller.cursorIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
          });
        }

        return _QuizBody(
          controller: _controller,
          scrollController: _scrollController,
          onSubmit: _handleSubmit,
        );
      },
    );
  }
}

/// 問題データの読み込み失敗時の表示。移植元 quiz.js:163-174 の
/// `.notice.notice--warn` 相当。自動遷移はせず、ホームへ戻る導線を出す。
class _LoadErrorScaffold extends StatelessWidget {
  const _LoadErrorScaffold();

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    tokens.ng.withValues(alpha: 0.12),
                    theme.colorScheme.surface,
                  ),
                  border: Border.all(color: tokens.ng),
                  borderRadius: BorderRadius.circular(tokens.radius),
                ),
                child: Text(
                  '問題データの読み込みに失敗しました。通信状態を確認し、ホームからやり直してください。',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: 'ホームへ戻る',
                variant: AppButtonVariant.base,
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuizBody extends StatelessWidget {
  const _QuizBody({
    required this.controller,
    required this.scrollController,
    required this.onSubmit,
  });

  final QuizController controller;
  final ScrollController scrollController;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);
    final question = controller.currentQuestion;
    final no = controller.currentNo;
    final total = controller.questionNos.length;
    final progress = (controller.cursorIndex + 1) / total;

    return Scaffold(
      // 移植元 quiz.js の setHeader({title, subtitle}) 相当。
      // subtitle は復習モード/本番通しの区別を示す。
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(controller.exam?.title ?? ''),
            Text(
              controller.mode == QuizMode.review ? '復習モード' : '本番通し',
              style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------- ヘッダー ----------
              Row(
                children: [
                  Text(
                    '${controller.cursorIndex + 1} / $total',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      controller.sectionNameOf(no),
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AppButton(
                    label: '回答状況',
                    variant: AppButtonVariant.base,
                    onPressed: () => AnswerSheet.show(context, controller),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: tokens.surface2,
                ),
              ),
              const SizedBox(height: 20),
              // ---------- 問題本文（設問切替時のみ作り直す） ----------
              Text(
                question?.text ?? '(この問題のデータが見つかりません)',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (question != null)
                    Text(
                      '${question.selectCount}つ選べ',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (question != null)
                    _SelectionCount(
                      controller: controller,
                      no: no,
                      selectCount: question.selectCount,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (question != null)
                _ChoiceList(controller: controller, no: no, question: question),
              const SizedBox(height: 20),
              const FooterCredit(hasBottomBar: true),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SizedBox(
        height: tokens.barHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: AppButton(
                  label: '前へ',
                  variant: AppButtonVariant.ghost,
                  onPressed: controller.canGoPrev
                      ? () => controller.goTo(controller.cursorIndex - 1)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: '次へ',
                  variant: AppButtonVariant.ghost,
                  onPressed: controller.canGoNext
                      ? () => controller.goTo(controller.cursorIndex + 1)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: '採点する',
                  variant: AppButtonVariant.primary,
                  onPressed: onSubmit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 選択数表示（`{selected} / {selectCount} 選択中`）。選択トグルのたびに
/// 変わるため、選択状態の ValueNotifier だけを購読しここだけ再構築する。
class _SelectionCount extends StatelessWidget {
  const _SelectionCount({
    required this.controller,
    required this.no,
    required this.selectCount,
  });

  final QuizController controller;
  final int no;
  final int selectCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<Set<int>>(
      valueListenable: controller.selectionOf(no),
      builder: (context, selected, _) {
        return Text(
          '${selected.length} / $selectCount 選択中',
          style: theme.textTheme.bodySmall,
        );
      },
    );
  }
}

/// 選択肢一覧。設問切替時にこのウィジェットごと作り直される（★意図的）。
/// 選択トグル自体は [ChoiceTile] 単体の再構築で済ませ、この親は再構築しない。
class _ChoiceList extends StatelessWidget {
  const _ChoiceList({
    required this.controller,
    required this.no,
    required this.question,
  });

  final QuizController controller;
  final int no;
  final Question question;

  @override
  Widget build(BuildContext context) {
    final selection = controller.selectionOf(no);
    return Column(
      children: [
        for (final choice in question.choices)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ValueListenableBuilder<Set<int>>(
              valueListenable: selection,
              builder: (context, selected, _) {
                return ChoiceTile(
                  no: choice.no,
                  text: choice.text,
                  selected: selected.contains(choice.no),
                  onTap: () {
                    final ok = controller.toggleChoice(
                      no,
                      choice.no,
                      question.selectCount,
                    );
                    if (!ok) {
                      AppToast.show(context, '${question.selectCount}つまで選べます');
                    }
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
