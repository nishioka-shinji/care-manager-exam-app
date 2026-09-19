import 'package:flutter/material.dart';

import '../../core/models/exam.dart';
import '../../core/models/session.dart';
import '../../data/exam_repository.dart';
import '../../data/storage_repository.dart';
import '../../routes.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirm_sheet.dart';
import '../../widgets/footer_credit.dart';
import 'history_controller.dart';

/// 履歴画面 #/history。移植元 public/js/history.js の Dart 版。表示順は
/// 移植元どおり: 1. ストレージ利用不可バナー 2. 成績サマリ
/// 3. 受験履歴一覧（全件） 4. 履歴をすべて削除。
class HistoryScreen extends StatefulWidget {
  // controller はテストからの差し替え用（省略時は自前で生成する）。
  const HistoryScreen({super.key, this.controller});

  final HistoryController? controller;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with RouteAware {
  late final HistoryController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        HistoryController(
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

  // 結果画面から戻ったとき、State が再利用され initState の load() は
  // 再実行されないため、ここで拾い直す（home_screen.dart と同じ理由）。
  @override
  void didPopNext() {
    _controller.load();
  }

  Future<void> _clearAll() async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: '履歴の削除',
      message: '受験履歴と正誤記録をすべて削除します。元に戻せません。よろしいですか？',
      confirmLabel: '削除する',
    );
    if (confirmed) {
      await _controller.clearAllAndReload();
    }
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
        return _HistoryBody(controller: _controller, onClearAll: _clearAll);
      },
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.controller, required this.onClearAll});

  final HistoryController controller;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final sessions = controller.sessions;
    final stats = controller.stats;
    final showDelete = sessions.isNotEmpty || stats.tracked > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('受験履歴')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!controller.storageAvailable) const _StorageWarningBanner(),
            if (!controller.storageAvailable) const SizedBox(height: 16),
            _SummaryCard(stats: stats),
            const SizedBox(height: 16),
            if (sessions.isEmpty)
              const _EmptyState()
            else
              for (final session in sessions)
                _HistoryItem(
                  session: session,
                  exam: controller.examFor(session.examId),
                ),
            if (showDelete) const SizedBox(height: 20),
            if (showDelete)
              AppButton(
                label: '履歴をすべて削除',
                variant: AppButtonVariant.danger,
                onPressed: onClearAll,
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
      child: const Text('この端末では記録が保存されないため、履歴は残りません。'),
    );
  }
}

/// 「問題ごとの成績サマリ」カード。summarizeStats() の3指標。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.stats});

  final StatsSummary stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('問題ごとの成績サマリ', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          Text(
            '一度でも間違えた問題: ${stats.everWrong}問',
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            '連続正解2回以上: ${stats.streak2plus}問',
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            '記録のある問題: ${stats.tracked}問',
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.appTokens.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'まだ受験履歴がありません。演習を1回解くとここに記録されます。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'ホームへ',
            variant: AppButtonVariant.primary,
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
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
    final score = session.score;
    final sectionTexts = score.bySection.entries
        .map((entry) {
          final name = _sectionNameOf(entry.key);
          return '$name ${entry.value.correct}/${entry.value.count}';
        })
        .join(' ／ ');

    return InkWell(
      onTap: () =>
          Navigator.of(context).pushNamed(Routes.result, arguments: session.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.appTokens.muted,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${score.total} / ${score.max}',
                  style: theme.textTheme.titleMedium,
                ),
                if (sectionTexts.isNotEmpty)
                  Text(
                    sectionTexts,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.appTokens.muted,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
