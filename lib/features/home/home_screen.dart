import 'package:flutter/material.dart';

import '../../core/models/current_session.dart';
import '../../core/models/exam.dart';
import '../../core/models/session.dart';
import '../../core/scoring.dart';
import '../../data/exam_repository.dart';
import '../../data/storage_repository.dart';
import '../../routes.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirm_sheet.dart';
import '../../widgets/footer_credit.dart';
import 'home_controller.dart';

/// ホーム画面 #/。移植元 public/js/home.js の Dart 版。表示順は移植元どおり:
/// 1. ストレージ利用不可バナー 2. 再開カード 3. 年度カード 4. 開始ボタン
/// 5. 直近の受験履歴。
class HomeScreen extends StatefulWidget {
  // controller はテストからの差し替え用（省略時は自前で生成する）。
  const HomeScreen({super.key, this.controller});

  final HomeController? controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  late final HomeController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        HomeController(
          examRepository: ExamRepository(),
          storageRepository: StorageRepository(),
        );
    _controller.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    // 注入されたコントローラはテスト側が所有するため、生成した場合のみ破棄する。
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  // 演習・結果・履歴から popUntil/pop でホームへ戻ったとき、State が
  // 再利用され initState の load() は再実行されないため、ここで拾い直す
  // （移植元はハッシュ遷移のたびに renderHome を呼び直す。routes.dart 参照）。
  @override
  void didPopNext() {
    _controller.load();
  }

  Future<void> _discardCurrent() async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: '演習の破棄',
      message: '中断中の演習を破棄して最初からやり直します。よろしいですか？',
      confirmLabel: 'やめて最初から',
    );
    if (confirmed) {
      await _controller.discardCurrent();
    }
  }

  Future<void> _startSession(QuizMode mode, List<int> questionNos) async {
    final targetExam = _controller.selectedExam;
    if (targetExam == null) return;
    final current = _controller.current;
    if (current != null) {
      final currentTitle = _controller.examTitleOf(current.examId);
      final confirmed = await ConfirmSheet.show(
        context,
        title: '演習の上書き',
        message:
            '中断中の『$currentTitle』を破棄して'
            '『${targetExam.title}』を始めますか？',
        confirmLabel: '破棄して新しく始める',
      );
      if (!confirmed) return;
    }
    await _controller.startSession(mode, questionNos);
    if (!mounted) return;
    Navigator.of(context).pushNamed(Routes.quiz);
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
        return _HomeBody(
          controller: _controller,
          onDiscardCurrent: _discardCurrent,
          onStartSession: _startSession,
        );
      },
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.controller,
    required this.onDiscardCurrent,
    required this.onStartSession,
  });

  final HomeController controller;
  final VoidCallback onDiscardCurrent;
  final void Function(QuizMode mode, List<int> questionNos) onStartSession;

  @override
  Widget build(BuildContext context) {
    final current = controller.current;
    final selectedExam = controller.selectedExam;
    final examsById = {
      for (final entry in controller.examEntries) entry.exam.id: entry.exam,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('ケアマネ過去問')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!controller.storageAvailable) const _StorageWarningBanner(),
            if (!controller.storageAvailable) const SizedBox(height: 16),
            if (current != null)
              _ResumeCard(
                current: current,
                examTitle: controller.examTitleOf(current.examId),
                onDiscard: onDiscardCurrent,
              ),
            if (current != null) const SizedBox(height: 16),
            if (controller.loadError) const _LoadErrorNotice(),
            if (selectedExam != null) ...[
              _ExamSelector(
                entries: controller.examEntries,
                selectedExamId: selectedExam.id,
                onSelected: controller.selectExam,
              ),
              const SizedBox(height: 12),
              _SelectedExamCard(
                exam: selectedExam,
                wrongNos: controller.wrongNos,
                onStart: onStartSession,
              ),
              const SizedBox(height: 16),
            ],
            _HistorySection(
              sessions: controller.sessions,
              examsById: examsById,
            ),
            const FooterCredit(),
          ],
        ),
      ),
    );
  }
}

/// storage.isAvailable() が false のときの警告バナー。
class _StorageWarningBanner extends StatelessWidget {
  const _StorageWarningBanner();

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          tokens.ng.withValues(alpha: 0.12),
          theme.colorScheme.surface,
        ),
        border: Border.all(color: tokens.ng),
        borderRadius: BorderRadius.circular(tokens.radius),
      ),
      child: Text(
        'この端末では学習記録が保存されません（演習と採点は使えます）',
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}

class _LoadErrorNotice extends StatelessWidget {
  const _LoadErrorNotice();

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            tokens.ng.withValues(alpha: 0.12),
            theme.colorScheme.surface,
          ),
          border: Border.all(color: tokens.ng),
          borderRadius: BorderRadius.circular(tokens.radius),
        ),
        child: Text(
          '年度データの読み込みに失敗しました。通信状況を確認して再読み込みしてください。',
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// 中断中セッションの再開カード。
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.current,
    required this.examTitle,
    required this.onDiscard,
  });

  final CurrentSession current;
  final String examTitle;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = current.questionNos.length;
    final cursorNo = current.cursor + 1;
    final label = modeLabel(current.mode);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('前回の続きがあります', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(examTitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(
            '$label・$cursorNo / $total 問目まで進行中',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          AppButton(
            label: '前回の続きから再開（$cursorNo / $total 問目）',
            variant: AppButtonVariant.primary,
            onPressed: () => Navigator.of(context).pushNamed(Routes.quiz),
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'やめて最初から',
            variant: AppButtonVariant.ghost,
            onPressed: onDiscard,
          ),
        ],
      ),
    );
  }
}

/// 複数年度を画面幅を増やさず選べる横スクロールのカード群。
/// カードは全件をセマンティクスツリーに載せ、スクリーンリーダーでも
/// 選択状態と問題数が分かるようにする。
class _ExamSelector extends StatelessWidget {
  const _ExamSelector({
    required this.entries,
    required this.selectedExamId,
    required this.onSelected,
  });

  final List<ExamEntry> entries;
  final String selectedExamId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('年度を選ぶ', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SingleChildScrollView(
          key: const PageStorageKey<String>('home-exam-selector'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < entries.length; index++) ...[
                _ExamSelectionCard(
                  exam: entries[index].exam,
                  selected: entries[index].exam.id == selectedExamId,
                  onTap: () => onSelected(entries[index].exam.id),
                ),
                if (index != entries.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ExamSelectionCard extends StatelessWidget {
  const _ExamSelectionCard({
    required this.exam,
    required this.selected,
    required this.onTap,
  });

  final Exam exam;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.appTokens;
    final primary = theme.colorScheme.primary;
    final textScaler = MediaQuery.textScalerOf(context)
        .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.5);
    final textScale = textScaler.scale(1);
    final titleStyle = theme.textTheme.bodyMedium!.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.35,
    );
    final metaStyle = theme.textTheme.bodySmall!.copyWith(height: 1.4);
    // 平成表記は2行になるため、高さを固定したまま2行分と下段1行分を確保する。
    double lineHeight(TextStyle style) =>
        (textScaler.scale(style.fontSize!) * style.height!).ceilToDouble();
    final cardHeight =
        20 + lineHeight(titleStyle) * 2 + 4 + lineHeight(metaStyle);
    return Semantics(
      button: true,
      selected: selected,
      onTap: onTap,
      label: '${exam.title}、全${exam.questions.length}問',
      child: ExcludeSemantics(
        child: Material(
          color: selected
              ? Color.alphaBlend(
                  primary.withValues(alpha: 0.10),
                  theme.colorScheme.surface,
                )
              : theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: selected ? primary : tokens.border,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(tokens.radius),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 184 * textScale,
              height: cardHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _compactExamTitle(exam.title),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textScaler: textScaler,
                        style: titleStyle,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '全${exam.questions.length}問',
                          textScaler: textScaler,
                          style: metaStyle,
                        ),
                        const Spacer(),
                        if (selected) ...[
                          Icon(Icons.check_circle, size: 16, color: primary),
                          const SizedBox(width: 3),
                          Text(
                            '選択中',
                            textScaler: textScaler,
                            style: metaStyle.copyWith(
                              color: primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The source title repeats the app's common exam-name suffix. Removing that
/// suffix keeps the meaningful year/round (including the October/March split
/// for 2201/2202) visible at narrow widths and larger text scales.
String _compactExamTitle(String title) {
  final compact = title.replaceFirst(RegExp(r'\s*介護支援専門員\s+実務研修受講試験$'), '');
  return compact.isEmpty ? title : compact;
}

/// 選択中の1年度だけに対し、本番通し・一問一答・復習を開始する。
class _SelectedExamCard extends StatelessWidget {
  const _SelectedExamCard({
    required this.exam,
    required this.wrongNos,
    required this.onStart,
  });

  final Exam exam;
  final List<int> wrongNos;
  final void Function(QuizMode mode, List<int> questionNos) onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final questionNos = exam.questions.map((q) => q.no).toList()..sort();

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(exam.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '全${exam.questions.length}問'
            '${exam.source.isEmpty ? '' : ' ・ 出典: $kExamSourceMediaName'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          AppButton(
            label: '本番通し${exam.questions.length}問を解く',
            variant: AppButtonVariant.primary,
            onPressed: questionNos.isEmpty
                ? null
                : () => onStart(QuizMode.full, questionNos),
          ),
          const SizedBox(height: 8),
          Semantics(
            hint: '1問ごとに答え合わせをして、その場で解説を読みながら進みます',
            child: AppButton(
              label: '一問一答で解く',
              onPressed: questionNos.isEmpty
                  ? null
                  : () => onStart(QuizMode.drill, questionNos),
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            hint: wrongNos.isEmpty ? 'まだ間違えた問題がありません。まずは本番通しを解いてください' : null,
            child: AppButton(
              label: '間違えた問題を復習（${wrongNos.length}問）',
              onPressed: wrongNos.isEmpty
                  ? null
                  : () => onStart(QuizMode.review, wrongNos),
            ),
          ),
          if (wrongNos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'まだ間違えた問題がありません。まずは本番通しを解いてください',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// 直近の受験履歴3件 + 「履歴をすべて見る」。
class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.sessions, required this.examsById});

  final List<Session> sessions;
  final Map<String, Exam> examsById;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = sessions.take(3).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('直近の受験履歴', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          if (recent.isEmpty)
            Text('まだ受験履歴がありません。', style: theme.textTheme.bodyMedium)
          else
            for (final session in recent)
              _HistoryItem(session: session, exam: examsById[session.examId]),
          const SizedBox(height: 10),
          AppButton(
            label: '履歴をすべて見る',
            variant: AppButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pushNamed(Routes.history),
          ),
        ],
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.session, required this.exam});

  final Session session;
  final Exam? exam;

  String _sectionNameOf(String sectionId) {
    final e = exam;
    if (e == null) return sectionId;
    for (final section in e.sections) {
      if (section.id == sectionId) return section.name;
    }
    return sectionId;
  }

  String _formatDateTime(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '(日時不明)';
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${pad(d.month)}/${pad(d.day)} ${pad(d.hour)}:${pad(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText = _formatDateTime(session.finishedAt);
    final label = modeLabel(session.mode);
    final examTitle = exam?.title ?? '第${session.examId}回';
    final score = session.score;
    final sectionTexts = score.bySection.entries
        .map((entry) {
          final name = _sectionNameOf(entry.key);
          final rate = formatRate(entry.value.correct, entry.value.count);
          return '$name ${entry.value.correct}/${entry.value.count}（$rate）';
        })
        .join(' ／ ');

    return InkWell(
      onTap: () =>
          Navigator.of(context).pushNamed(Routes.result, arguments: session.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$dateText・$label',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(examTitle, style: theme.textTheme.bodySmall),
            Text(
              '${score.total} / ${score.max}',
              style: theme.textTheme.titleMedium,
            ),
            if (sectionTexts.isNotEmpty)
              Text(sectionTexts, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
