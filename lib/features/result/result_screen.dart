import 'package:flutter/material.dart';

import '../../routes.dart';
import '../../data/exam_repository.dart';
import '../../data/storage_repository.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/footer_credit.dart';
import 'result_controller.dart';
import 'widgets/explanation_card.dart';
import 'widgets/result_grid.dart';
import 'widgets/score_card.dart';
import 'widgets/section_bar.dart';

/// 結果画面 #/result/{sessionId}。移植元 public/js/result.js の Dart 版。
///
/// 保存済み session.score は信用せず、session.answers から常に
/// [ResultController] が再採点した score/results で描画する。
class ResultScreen extends StatefulWidget {
  // controller はテストからの差し替え用（省略時は自前で生成する）。
  const ResultScreen({super.key, this.sessionId, this.controller});

  final String? sessionId;
  final ResultController? controller;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final ResultController _controller;
  final Map<int, GlobalKey> _explanationKeys = {};
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        ResultController(
          examRepository: ExamRepository(),
          storageRepository: StorageRepository(),
          sessionId: widget.sessionId,
        );
    _controller.load();
  }

  @override
  void dispose() {
    // 注入されたコントローラはテスト側が所有するため、生成した場合のみ破棄する。
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _maybeRedirectHome() {
    if (_redirected) return;
    if (_controller.notFound) {
      _redirected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(Routes.home);
      });
    }
  }

  GlobalKey _keyFor(int no) => _explanationKeys.putIfAbsent(no, GlobalKey.new);

  void _scrollToQuestion(int no) {
    final key = _explanationKeys[no];
    final context = key?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 250),
      alignment: 0,
    );
  }

  Future<void> _startReview() async {
    await _controller.startReview();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(Routes.quiz);
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
        _maybeRedirectHome();
        if (_controller.notFound) {
          return const Scaffold(body: SizedBox.shrink());
        }
        if (_controller.loadError) {
          return const _LoadErrorScaffold();
        }
        return _ResultBody(
          controller: _controller,
          keyFor: _keyFor,
          onTapGridNo: _scrollToQuestion,
          onReview: _startReview,
        );
      },
    );
  }
}

/// 問題データの読み込み失敗時の表示。演習画面の同種の表示に揃える。
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

class _ResultBody extends StatelessWidget {
  const _ResultBody({
    required this.controller,
    required this.keyFor,
    required this.onTapGridNo,
    required this.onReview,
  });

  final ResultController controller;
  final GlobalKey Function(int no) keyFor;
  final void Function(int no) onTapGridNo;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final session = controller.session!;
    final exam = controller.exam!;
    final gradeResult = controller.gradeResult!;
    final wrongCount = controller.wrongQuestionNos.length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('採点結果'),
            Text(
              modeLabel(session.mode),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.muted),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScoreCard(session: session, score: gradeResult.score),
              const SizedBox(height: 16),
              SectionBreakdownCard(exam: exam, score: gradeResult.score),
              const SizedBox(height: 16),
              ResultGrid(results: gradeResult.results, onTapNo: onTapGridNo),
              const SizedBox(height: 16),
              for (final r in gradeResult.results) ...[
                Container(
                  key: keyFor(r.no),
                  child: ExplanationCard(exam: exam, result: r),
                ),
                const SizedBox(height: 16),
              ],
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
                  label: 'ホームへ',
                  variant: AppButtonVariant.ghost,
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: wrongCount == 0
                      ? '間違えた問題はありません'
                      : '間違えた問題だけ復習する（$wrongCount問）',
                  variant: AppButtonVariant.primary,
                  onPressed: wrongCount == 0 ? null : onReview,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
