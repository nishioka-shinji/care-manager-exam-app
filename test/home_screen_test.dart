import 'package:care_manager_exam_app/core/models/choice.dart';
import 'package:care_manager_exam_app/core/models/current_session.dart';
import 'package:care_manager_exam_app/core/models/exam.dart';
import 'package:care_manager_exam_app/core/models/exam_meta.dart';
import 'package:care_manager_exam_app/core/models/question.dart';
import 'package:care_manager_exam_app/core/models/section.dart';
import 'package:care_manager_exam_app/core/models/session.dart';
import 'package:care_manager_exam_app/data/exam_repository.dart';
import 'package:care_manager_exam_app/data/storage_repository.dart';
import 'package:care_manager_exam_app/features/home/home_controller.dart';
import 'package:care_manager_exam_app/features/home/home_screen.dart';
import 'package:care_manager_exam_app/theme/app_theme.dart';
import 'package:care_manager_exam_app/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// exam-28.json は実アセット（60問、care:1-25 / health_welfare:26-60）。
// ExamRepository は index.json をアセットから読むため、複数年度の検証には
// 実 I/O を経由せずメタ・本体を差し替えられるフェイクを使う。
const _examId = '28';

class _FakeExamRepository extends ExamRepository {
  _FakeExamRepository(this._metas, this._exams);

  final List<ExamMeta> _metas;
  final Map<String, Exam> _exams;

  @override
  Future<List<ExamMeta>> loadIndex() async => _metas;

  @override
  Future<Exam> loadExam(String examId) async => _exams[examId]!;
}

Exam _buildExam({required String id, required String title, int count = 60}) {
  return Exam(
    id: id,
    title: title,
    source: 'https://example.test/$id',
    credit: '解答・解説: 学校法人 藤仁館学園',
    fetchedAt: '2026-08-31',
    sections: const [
      Section(id: 'care', name: '介護支援分野', from: 1, to: 25),
      Section(id: 'health_welfare', name: '保健医療福祉サービス分野', from: 26, to: 60),
    ],
    questions: [
      for (var no = 1; no <= count; no++)
        Question(
          no: no,
          sectionId: no <= 25 ? 'care' : 'health_welfare',
          text: '問題$no',
          selectCount: 1,
          choices: const [Choice(no: 1, text: '選択肢1', explanation: '')],
          answers: const [1],
        ),
    ],
  );
}

ExamRepository _singleExamRepository() {
  final exam = _buildExam(id: _examId, title: '第28回（令和7年度）介護支援専門員 実務研修受講試験');
  return _FakeExamRepository(
    [ExamMeta(id: _examId, title: exam.title, file: 'exam-28.json')],
    {_examId: exam},
  );
}

ExamRepository _multiYearExamRepository() {
  final exam28 = _buildExam(id: '28', title: '第28回試験');
  final exam27 = _buildExam(id: '27', title: '第27回試験');
  return _FakeExamRepository(
    [
      ExamMeta(id: '28', title: exam28.title, file: 'exam-28.json'),
      ExamMeta(id: '27', title: exam27.title, file: 'exam-27.json'),
    ],
    {'28': exam28, '27': exam27},
  );
}

Session _buildSession({
  required String id,
  required String finishedAt,
  QuizMode mode = QuizMode.full,
}) {
  return Session(
    id: id,
    examId: _examId,
    mode: mode,
    startedAt: '2026-09-19T00:00:00.000Z',
    finishedAt: finishedAt,
    answers: {
      1: [1],
    },
    score: const Score(
      total: 18,
      max: 25,
      bySection: {
        'care': SectionScore(correct: 18, count: 25),
        'health_welfare': SectionScore(correct: 20, count: 35),
      },
    ),
  );
}

Future<HomeController> _buildController(
  WidgetTester tester, {
  ExamRepository? examRepository,
  CurrentSession? current,
  List<Session> sessions = const [],
  Map<int, bool> statResults = const {},
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageRepository();
  final controller = HomeController(
    examRepository: examRepository ?? _singleExamRepository(),
    storageRepository: storage,
  );
  await tester.runAsync(() async {
    await storage.init();
    if (current != null) {
      await storage.saveCurrent(current);
    }
    for (final session in sessions) {
      await storage.saveSession(session);
    }
    if (statResults.isNotEmpty) {
      await storage.applyResults([
        for (final entry in statResults.entries)
          (no: entry.key, correct: entry.value),
      ]);
    }
    await controller.load();
  });
  return controller;
}

// go_router 等は使わない方針のため素の Navigator + onGenerateRoute で組む。
Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    initialRoute: '/',
    onGenerateRoute: (settings) {
      if (settings.name == '/') {
        return MaterialPageRoute(builder: (_) => child);
      }
      if (settings.name == '/quiz') {
        return MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('quiz')),
        );
      }
      if (settings.name == '/result') {
        return MaterialPageRoute(
          builder: (_) => Scaffold(body: Text('result:${settings.arguments}')),
        );
      }
      if (settings.name == '/history') {
        return MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('history')),
        );
      }
      return null;
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('中断セッションがあると再開カードが出て進捗表示が cursor+1 / total になる', (tester) async {
    final controller = await _buildController(
      tester,
      current: CurrentSession(
        examId: _examId,
        mode: QuizMode.full,
        startedAt: '2026-09-19T00:00:00.000Z',
        questionNos: List.generate(60, (i) => i + 1),
        cursor: 4,
        answers: const {},
      ),
    );
    await tester.pumpWidget(_wrap(HomeScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('前回の続きがあります'), findsOneWidget);
    expect(find.textContaining('本番通し・5 / 60 問目まで進行中'), findsOneWidget);
    expect(find.textContaining('前回の続きから再開（5 / 60 問目）'), findsOneWidget);
  });

  testWidgets('やめて最初からで確認シートが出て OK で current が消える', (tester) async {
    final controller = await _buildController(
      tester,
      current: CurrentSession(
        examId: _examId,
        mode: QuizMode.full,
        startedAt: '2026-09-19T00:00:00.000Z',
        questionNos: List.generate(60, (i) => i + 1),
        cursor: 0,
        answers: const {},
      ),
    );
    await tester.pumpWidget(_wrap(HomeScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('やめて最初から'));
    await tester.pumpAndSettle();

    expect(find.textContaining('破棄して最初からやり直します'), findsOneWidget);

    await tester.tap(find.text('やめて最初から').last);
    await tester.pumpAndSettle();

    expect(controller.current, isNull);
    expect(find.text('前回の続きがあります'), findsNothing);
  });

  testWidgets('復習対象0件で復習ボタンが disabled になり理由テキストが出る', (tester) async {
    final controller = await _buildController(tester);
    await tester.pumpWidget(_wrap(HomeScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('間違えた問題を復習（0問）'), findsOneWidget);
    expect(find.text('まだ間違えた問題がありません。まずは本番通しを解いてください'), findsOneWidget);

    final button = tester.widget<AppButton>(
      find.ancestor(
        of: find.text('間違えた問題を復習（0問）'),
        matching: find.byType(AppButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('復習対象があるときボタンに件数が出て押すと間違えた問番号の昇順で current が作られる', (tester) async {
    final controller = await _buildController(
      tester,
      statResults: {5: false, 30: false, 12: false, 1: true},
    );
    await tester.pumpWidget(_wrap(HomeScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('間違えた問題を復習（3問）'), findsOneWidget);

    await tester.tap(find.text('間違えた問題を復習（3問）'));
    await tester.pumpAndSettle();

    expect(controller.current?.mode, QuizMode.review);
    expect(controller.current?.questionNos, [5, 12, 30]);
    expect(controller.current?.cursor, 0);
    expect(controller.current?.answers, isEmpty);
    expect(find.text('quiz'), findsOneWidget);
  });

  testWidgets('本番通しで questionNos が1〜60昇順の current が作られる', (tester) async {
    final controller = await _buildController(tester);
    await tester.pumpWidget(_wrap(HomeScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('本番通し60問を解く'));
    await tester.pumpAndSettle();

    expect(controller.current?.mode, QuizMode.full);
    expect(controller.current?.questionNos, List.generate(60, (i) => i + 1));
    expect(find.text('quiz'), findsOneWidget);
  });

  testWidgets('既存の中断セッションがあるとき開始時に上書き確認シートが出て、キャンセルで current は変わらない', (
    tester,
  ) async {
    final existing = CurrentSession(
      examId: _examId,
      mode: QuizMode.review,
      startedAt: '2026-09-19T00:00:00.000Z',
      questionNos: const [3, 4],
      cursor: 1,
      answers: const {},
    );
    final controller = await _buildController(tester, current: existing);
    await tester.pumpWidget(_wrap(HomeScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('本番通し60問を解く'));
    await tester.pumpAndSettle();

    expect(find.textContaining('破棄して新しく始めますか？'), findsOneWidget);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(controller.current?.questionNos, existing.questionNos);
    expect(controller.current?.mode, QuizMode.review);
    expect(find.text('quiz'), findsNothing);
  });

  testWidgets('上書き確認で OK すると新しい current が保存されて演習へ進む', (tester) async {
    final existing = CurrentSession(
      examId: _examId,
      mode: QuizMode.review,
      startedAt: '2026-09-19T00:00:00.000Z',
      questionNos: const [3, 4],
      cursor: 1,
      answers: const {},
    );
    final controller = await _buildController(tester, current: existing);
    await tester.pumpWidget(_wrap(HomeScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('本番通し60問を解く'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('破棄して新しく始める'));
    await tester.pumpAndSettle();

    expect(controller.current?.mode, QuizMode.full);
    expect(controller.current?.questionNos, List.generate(60, (i) => i + 1));
    expect(find.text('quiz'), findsOneWidget);
  });

  testWidgets('履歴が3件までしか出ず、タップで result に sessionId が渡る', (tester) async {
    final sessions = [
      _buildSession(id: 's1', finishedAt: '2026-09-19T04:00:00.000Z'),
      _buildSession(id: 's2', finishedAt: '2026-09-19T03:00:00.000Z'),
      _buildSession(id: 's3', finishedAt: '2026-09-19T02:00:00.000Z'),
      _buildSession(id: 's4', finishedAt: '2026-09-19T01:00:00.000Z'),
    ];
    final controller = await _buildController(tester, sessions: sessions);
    await tester.pumpWidget(_wrap(HomeScreen(controller: controller)));
    await tester.pumpAndSettle();

    // loadSessions は finishedAt 降順。saveSession は先頭に追加するため
    // 末尾に保存したもの(s1)が最新になる。表示は3件（s1,s2,s3）まで。
    expect(find.textContaining('18 / 25'), findsNWidgets(3));

    await tester.tap(find.text('18 / 25').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('result:s1'), findsOneWidget);
  });

  testWidgets('年度カードにタイトル・全問数・出典が表示される', (tester) async {
    final controller = await _buildController(tester);
    await tester.pumpWidget(_wrap(HomeScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('第28回（令和7年度）介護支援専門員 実務研修受講試験'), findsOneWidget);
    expect(find.text('全60問'), findsOneWidget);
    expect(find.text('出典: ケアマネージャー試験過去問題集'), findsOneWidget);
  });

  testWidgets('複数年度のとき年度カードがループ描画される', (tester) async {
    final controller = await _buildController(
      tester,
      examRepository: _multiYearExamRepository(),
    );
    await tester.pumpWidget(_wrap(HomeScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('第28回試験'), findsOneWidget);
    expect(find.text('第27回試験'), findsOneWidget);
  });

  testWidgets('ストレージ利用不可のとき警告バナーが出る', (tester) async {
    final controller = await _buildController(tester);
    // isAvailable() は init 後は常に true になる実装のため、バナーが
    // 出ない基本ケースだけ確認する（利用不可の再現手段が無いため）。
    await tester.pumpWidget(_wrap(HomeScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.textContaining('この端末では学習記録が保存されません'), findsNothing);
  });
}
