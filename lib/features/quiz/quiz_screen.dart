import 'package:flutter/material.dart';

import '../../routes.dart';
import '../../core/models/question.dart';
import '../../core/models/session.dart';
import '../../core/scoring.dart';
import '../../data/exam_repository.dart';
import '../../data/storage_repository.dart';
import '../../notifications/study_reminder.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_sheet.dart';
import '../../widgets/footer_credit.dart';
import 'quiz_controller.dart';
import 'widgets/answer_sheet.dart';
import 'widgets/choice_tile.dart';

/// 演習画面 #/quiz。移植元 public/js/quiz.js の Dart 版。
///
/// ★不変条件2: 選択肢タップ・答え合わせでは設問（問題文・選択肢リスト）を
/// 作り直さない。revealCurrent() も notifyListeners() を呼ぶため、
/// cursorIndex 等の変化だけを自前フィルタで見て setState する。選択状態・
/// 答え合わせ済み状態は設問ごとの ValueNotifier で該当箇所だけ再構築する。
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
  // revealCurrent() も notifyListeners() を呼ぶため、この3値以外の変化では
  // setState しない（cursorIndex は下の _lastCursorIndex で別途見る）。
  bool? _lastLoading;
  bool? _lastLoadError;
  bool? _lastShouldRedirectHome;

  // drill の答え合わせ済み状態。選択状態（selectionOf）と同じく設問ごとの
  // ValueNotifier に分け、答え合わせボタン押下でも _QuizBody を作り直さない
  // （不変条件2）。
  final Map<int, ValueNotifier<bool>> _revealedByNo = {};

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        QuizController(
          examRepository: ExamRepository(),
          storageRepository: StorageRepository(),
          studyReminder: appStudyReminder,
        );
    // 画面構造が変わるときだけ setState する自前フィルタ（クラス doc 参照）。
    _controller.addListener(_onControllerChanged);
    _controller.load();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final loading = _controller.loading;
    final loadError = _controller.loadError;
    final shouldRedirectHome = _controller.shouldRedirectHome;
    final cursorIndex = loading ? null : _controller.cursorIndex;
    final changed =
        loading != _lastLoading ||
        loadError != _lastLoadError ||
        shouldRedirectHome != _lastShouldRedirectHome ||
        cursorIndex != _lastCursorIndex;
    if (!changed) return;
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _scrollController.dispose();
    for (final notifier in _revealedByNo.values) {
      notifier.dispose();
    }
    // 注入されたコントローラはテスト側が所有するため、生成した場合のみ破棄する。
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  ValueNotifier<bool> _revealedNotifierOf(int no) {
    return _revealedByNo.putIfAbsent(
      no,
      () => ValueNotifier<bool>(_controller.isRevealed(no)),
    );
  }

  Future<void> _handleReveal(int no, int selectCount) async {
    final ok = await _controller.revealCurrent(selectCount);
    if (!ok) {
      if (!_controller.isRevealed(no) && mounted) {
        AppToast.show(context, '$selectCountつ選んでください');
      }
      return;
    }
    _revealedNotifierOf(no).value = true;
  }

  Future<void> _handleFinishDrill() async {
    final result = await _controller.finishDrill();
    if (result.noRevealed) {
      if (mounted) AppToast.show(context, 'まず1問以上、答え合わせをしてください');
      return;
    }
    if (result.id == null || !mounted) return;
    Navigator.of(context)
        .pushReplacementNamed(Routes.result, arguments: result.id);
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
    _lastLoading = _controller.loading;
    _lastLoadError = _controller.loadError;
    _lastShouldRedirectHome = _controller.shouldRedirectHome;

    if (_controller.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_controller.loadError) {
      return const _LoadErrorScaffold();
    }
    _maybeRedirectHome();
    if (_controller.shouldRedirectHome) {
      return const Scaffold(body: SizedBox.shrink());
    }

    // 設問が切り替わったときだけ先頭へ戻す（選択トグル・答え合わせからは
    // この build 自体が呼ばれないため、ここに到達するのは設問切替時のみ）。
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
      revealedNotifierOf: _revealedNotifierOf,
      onReveal: _handleReveal,
      onFinishDrill: _handleFinishDrill,
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

/// 実機の一部環境（Android edge-to-edge + 3ボタンナビゲーション）では
/// viewPadding.bottom が 0 を返す既知の問題があるため、padding.bottom も
/// 併せて見て大きい方を採用する（この画面はテキスト入力が無く IME による
/// padding.bottom の減少は起こらない）。
double _bottomSafeInset(BuildContext context) {
  final mediaQuery = MediaQuery.of(context);
  return mediaQuery.viewPadding.bottom > mediaQuery.padding.bottom
      ? mediaQuery.viewPadding.bottom
      : mediaQuery.padding.bottom;
}

class _QuizBody extends StatelessWidget {
  const _QuizBody({
    required this.controller,
    required this.scrollController,
    required this.onSubmit,
    required this.revealedNotifierOf,
    required this.onReveal,
    required this.onFinishDrill,
  });

  final QuizController controller;
  final ScrollController scrollController;
  final VoidCallback onSubmit;
  final ValueNotifier<bool> Function(int no) revealedNotifierOf;
  final Future<void> Function(int no, int selectCount) onReveal;
  final VoidCallback onFinishDrill;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);
    final question = controller.currentQuestion;
    final no = controller.currentNo;
    final total = controller.questionNos.length;
    final progress = (controller.cursorIndex + 1) / total;
    final isDrill = controller.mode == QuizMode.drill;
    final revealedNotifier = revealedNotifierOf(no);

    final String subtitle;
    switch (controller.mode) {
      case QuizMode.full:
        subtitle = '本番通し';
      case QuizMode.review:
        subtitle = '復習モード';
      case QuizMode.drill:
        subtitle = '一問一答';
    }

    return Scaffold(
      // 移植元 quiz.js の setHeader({title, subtitle}) 相当。
      // subtitle は本番通し/復習モード/一問一答の区別を示す。
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(controller.exam?.title ?? ''),
            Text(
              subtitle,
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
                    onPressed: () => AnswerSheet.show(
                      context,
                      controller,
                      onFinishDrill: onFinishDrill,
                    ),
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
              if (isDrill && question != null) ...[
                const SizedBox(height: 14),
                _FeedbackBanner(
                  revealedNotifier: revealedNotifier,
                  question: question,
                  selection: controller.selectionOf(no),
                ),
              ],
              const SizedBox(height: 14),
              if (question != null)
                _ChoiceList(
                  controller: controller,
                  no: no,
                  question: question,
                  isDrill: isDrill,
                  revealedNotifier: revealedNotifier,
                ),
              const SizedBox(height: 20),
              const FooterCredit(hasBottomBar: true),
            ],
          ),
        ),
      ),
      // 高さに safe-area 分を足す。足さないとシステムのナビゲーションバーに
      // ボタンが隠れて押せない。上限を外すとボタンが画面全高に広がるため、
      // ConstrainedBox ではなく高さを決めて締める。
      bottomNavigationBar: SizedBox(
        height: tokens.barHeight + _bottomSafeInset(context),
        child: Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 10,
            bottom: 10 + _bottomSafeInset(context),
          ),
          child: isDrill && question != null
              ? _DrillBottomBar(
                  controller: controller,
                  no: no,
                  selectCount: question.selectCount,
                  revealedNotifier: revealedNotifier,
                  onReveal: onReveal,
                  onFinishDrill: onFinishDrill,
                )
              : Row(
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

/// drill の下部バー。答え合わせ済みかどうか（[revealedNotifier]）だけを
/// 購読して自分だけ再構築する（不変条件2: 答え合わせボタン押下でも
/// _QuizBody は作り直さない）。移植元 quiz.js:281-296 の updateControls。
class _DrillBottomBar extends StatelessWidget {
  const _DrillBottomBar({
    required this.controller,
    required this.no,
    required this.selectCount,
    required this.revealedNotifier,
    required this.onReveal,
    required this.onFinishDrill,
  });

  final QuizController controller;
  final int no;
  final int selectCount;
  final ValueNotifier<bool> revealedNotifier;
  final Future<void> Function(int no, int selectCount) onReveal;
  final VoidCallback onFinishDrill;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: revealedNotifier,
      builder: (context, revealed, _) {
        final isLast =
            controller.cursorIndex == controller.questionNos.length - 1;
        return Row(
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
              child: revealed && isLast
                  ? AppButton(
                      label: '結果を見る',
                      variant: AppButtonVariant.primary,
                      onPressed: onFinishDrill,
                    )
                  : AppButton(
                      label: revealed ? '次の問題へ' : '次へ',
                      variant: revealed
                          ? AppButtonVariant.primary
                          : AppButtonVariant.ghost,
                      onPressed: controller.canGoNext
                          ? () => controller.goTo(controller.cursorIndex + 1)
                          : null,
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: revealed
                  ? const SizedBox.shrink()
                  : ValueListenableBuilder<Set<int>>(
                      valueListenable: controller.selectionOf(no),
                      builder: (context, selected, _) {
                        return AppButton(
                          label: '答え合わせ',
                          variant: AppButtonVariant.primary,
                          onPressed: selected.length == selectCount
                              ? () => onReveal(no, selectCount)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// 答え合わせ結果のバナー。移植元 quiz.js:96-103 と同じく問題文・選択数
/// ヒントと選択肢リストの間に置く。答え合わせ前は非表示（quiz-feedback）。
class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({
    required this.revealedNotifier,
    required this.question,
    required this.selection,
  });

  final ValueNotifier<bool> revealedNotifier;
  final Question question;
  final ValueNotifier<Set<int>> selection;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: revealedNotifier,
      builder: (context, revealed, _) {
        if (!revealed) return const SizedBox.shrink();
        final tokens = context.appTokens;
        final theme = Theme.of(context);
        final chosen = selection.value.toList()..sort();
        final ok = isCorrect(chosen, question.answers);
        final answerLabel = (question.answers.toList()..sort()).join('・');
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppBadge(
                label: ok ? '正解' : '不正解',
                status: ok ? AppBadgeStatus.ok : AppBadgeStatus.ng,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '正解は $answerLabel',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.muted,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
/// 選択トグル・答え合わせのどちらも [ChoiceTile] 単体の再構築で済ませ、
/// この親は再構築しない（不変条件2）。
class _ChoiceList extends StatelessWidget {
  const _ChoiceList({
    required this.controller,
    required this.no,
    required this.question,
    required this.isDrill,
    required this.revealedNotifier,
  });

  final QuizController controller;
  final int no;
  final Question question;
  final bool isDrill;
  final ValueNotifier<bool> revealedNotifier;

  @override
  Widget build(BuildContext context) {
    final selection = controller.selectionOf(no);
    return Column(
      children: [
        for (final choice in question.choices)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: !isDrill
                ? ValueListenableBuilder<Set<int>>(
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
                            AppToast.show(
                              context,
                              '${question.selectCount}つまで選べます',
                            );
                          }
                        },
                      );
                    },
                  )
                : ValueListenableBuilder<bool>(
                    valueListenable: revealedNotifier,
                    builder: (context, revealed, _) {
                      return ValueListenableBuilder<Set<int>>(
                        valueListenable: selection,
                        builder: (context, selected, _) {
                          return ChoiceTile(
                            no: choice.no,
                            text: choice.text,
                            selected: selected.contains(choice.no),
                            revealed: revealed,
                            isAnswer: question.answers.contains(choice.no),
                            explanation: choice.explanation,
                            onTap: () {
                              final ok = controller.toggleChoice(
                                no,
                                choice.no,
                                question.selectCount,
                              );
                              if (!ok) {
                                AppToast.show(
                                  context,
                                  '${question.selectCount}つまで選べます',
                                );
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
      ],
    );
  }
}
