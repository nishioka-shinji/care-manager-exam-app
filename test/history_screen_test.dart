import 'package:care_manager_exam_app/core/models/choice.dart';
import 'package:care_manager_exam_app/core/models/exam.dart';
import 'package:care_manager_exam_app/core/models/exam_meta.dart';
import 'package:care_manager_exam_app/core/models/question.dart';
import 'package:care_manager_exam_app/core/models/section.dart';
import 'package:care_manager_exam_app/core/models/session.dart';
import 'package:care_manager_exam_app/data/exam_repository.dart';
import 'package:care_manager_exam_app/data/storage_repository.dart';
import 'package:care_manager_exam_app/features/history/history_controller.dart';
import 'package:care_manager_exam_app/features/history/history_screen.dart';
import 'package:care_manager_exam_app/routes.dart';
import 'package:care_manager_exam_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ExamRepository は index.json をアセットから読むため、分野名解決の検証には
// 実 I/O を経由せずメタ・本体を差し替えられるフェイクを使う
// （home_screen_test.dart の _FakeExamRepository と同じ理由）。
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

/// loadIndex/loadExam が例外を投げるフェイク。exam の読み込み失敗時に
/// 履歴一覧が sectionId へフォールバックすることを確認するために使う。
class _FailingExamRepository extends ExamRepository {
  @override
  Future<List<ExamMeta>> loadIndex() async {
    throw Exception('index load failed');
  }
}

/// isAvailable() を常に false に固定したフェイク。ネイティブでは実質
/// 起きない「ストレージ利用不可」状態を警告バナー検証のために再現する。
class _UnavailableStorageRepository extends StorageRepository {
  @override
  bool isAvailable() => false;
}

Exam _buildExam() {
  return Exam(
    id: _examId,
    title: '第28回（令和7年度）介護支援専門員 実務研修受講試験',
    source: 'https://example.test/$_examId',
    credit: '解答・解説: 学校法人 藤仁館学園',
    fetchedAt: '2026-08-31',
    sections: const [
      Section(id: 'care', name: '介護支援分野', from: 1, to: 25),
      Section(id: 'health_welfare', name: '保健医療福祉サービス分野', from: 26, to: 60),
    ],
    questions: [
      for (var no = 1; no <= 60; no++)
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
  final exam = _buildExam();
  return _FakeExamRepository(
    [ExamMeta(id: _examId, title: exam.title, file: 'exam-28.json')],
    {_examId: exam},
  );
}

// F2: 複数年度になっても各セッションの examId で分野名を引けることの確認用。
// 先頭年度（27）と異なる分野名を持つ2件目の年度（28）を用意する。
const _otherExamId = '27';

Exam _buildOtherExam() {
  return Exam(
    id: _otherExamId,
    title: '第27回（令和6年度）介護支援専門員 実務研修受講試験',
    source: 'https://example.test/$_otherExamId',
    credit: '解答・解説: 学校法人 藤仁館学園',
    fetchedAt: '2025-08-31',
    sections: const [
      Section(id: 'care', name: '介護支援分野（27回）', from: 1, to: 25),
      Section(
        id: 'health_welfare',
        name: '保健医療福祉サービス分野（27回）',
        from: 26,
        to: 60,
      ),
    ],
    questions: [
      for (var no = 1; no <= 60; no++)
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

ExamRepository _multiYearExamRepository() {
  final exam28 = _buildExam();
  final exam27 = _buildOtherExam();
  return _FakeExamRepository(
    [
      ExamMeta(id: _otherExamId, title: exam27.title, file: 'exam-27.json'),
      ExamMeta(id: _examId, title: exam28.title, file: 'exam-28.json'),
    ],
    {_otherExamId: exam27, _examId: exam28},
  );
}

Session _buildSession({
  required String id,
  required String finishedAt,
  QuizMode mode = QuizMode.full,
  String examId = _examId,
}) {
  return Session(
    id: id,
    examId: examId,
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

/// load() の呼び出し回数を数えるためのテスト用サブクラス。
/// didPopNext での再読み込みが実際に走ることを検証する。
class _CountingHistoryController extends HistoryController {
  _CountingHistoryController({
    required super.examRepository,
    required super.storageRepository,
  });

  int loadCallCount = 0;

  @override
  Future<void> load() async {
    loadCallCount += 1;
    await super.load();
  }
}

Future<HistoryController> _buildController(
  WidgetTester tester, {
  ExamRepository? examRepository,
  List<Session> sessions = const [],
  List<List<({int no, bool correct})>> statRounds = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageRepository();
  await storage.init();
  for (final session in sessions) {
    await storage.saveSession(session);
  }
  for (final round in statRounds) {
    await storage.applyResults(round);
  }
  final controller = HistoryController(
    examRepository: examRepository ?? _singleExamRepository(),
    storageRepository: storage,
  );
  await controller.load();
  return controller;
}

// go_router 等は使わない方針のため素の Navigator + onGenerateRoute で組む。
// routeObserver も本番と同じく登録し、didPopNext の再読み込みを検証できる
// ようにする（app.dart の navigatorObservers と同じ設定）。
Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    initialRoute: '/history',
    navigatorObservers: [routeObserver],
    onGenerateRoute: (settings) {
      if (settings.name == '/history') {
        return MaterialPageRoute(builder: (_) => child);
      }
      if (settings.name == '/') {
        return MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('home')),
        );
      }
      if (settings.name == '/result') {
        return MaterialPageRoute(
          builder: (_) => Scaffold(body: Text('result:${settings.arguments}')),
        );
      }
      return null;
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('成績サマリの3指標が正しく出る', (tester) async {
    final controller = await _buildController(
      tester,
      statRounds: [
        [
          (no: 5, correct: false),
          (no: 12, correct: false),
          (no: 30, correct: true),
        ],
        [(no: 12, correct: true), (no: 30, correct: true)],
      ],
    );
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();

    // 5:不正解のみ(attempts1,correct0,streak0) 12:不正解→正解
    // (attempts2,correct1,streak1) 30:正解2回(attempts2,correct2,streak2)。
    expect(find.text('一度でも間違えた問題: 2問'), findsOneWidget);
    expect(find.text('連続正解2回以上: 1問'), findsOneWidget);
    expect(find.text('記録のある問題: 3問'), findsOneWidget);
  });

  testWidgets('履歴が全件出る（4件でも3件に制限されない）', (tester) async {
    final sessions = [
      _buildSession(id: 's1', finishedAt: '2026-09-19T04:00:00.000Z'),
      _buildSession(id: 's2', finishedAt: '2026-09-19T03:00:00.000Z'),
      _buildSession(id: 's3', finishedAt: '2026-09-19T02:00:00.000Z'),
      _buildSession(id: 's4', finishedAt: '2026-09-19T01:00:00.000Z'),
    ];
    final controller = await _buildController(tester, sessions: sessions);
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.textContaining('18 / 25'), findsNWidgets(4));
  });

  testWidgets('分野別得点が sectionId でなく日本語の分野名で出る', (tester) async {
    final sessions = [
      _buildSession(id: 's1', finishedAt: '2026-09-19T04:00:00.000Z'),
    ];
    final controller = await _buildController(tester, sessions: sessions);
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.textContaining('介護支援分野 18/25'), findsOneWidget);
    expect(find.textContaining('保健医療福祉サービス分野 20/35'), findsOneWidget);
    expect(find.textContaining('care 18/25'), findsNothing);
  });

  testWidgets('exam の読み込みに失敗しても履歴一覧は表示され、分野名は sectionId にフォールバックする', (
    tester,
  ) async {
    final sessions = [
      _buildSession(id: 's1', finishedAt: '2026-09-19T04:00:00.000Z'),
    ];
    final controller = await _buildController(
      tester,
      examRepository: _FailingExamRepository(),
      sessions: sessions,
    );
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(controller.examFor(_examId), isNull);
    expect(find.text('受験履歴'), findsOneWidget);
    expect(find.textContaining('18 / 25'), findsOneWidget);
    expect(find.textContaining('care 18/25'), findsOneWidget);
  });

  testWidgets('履歴のタップで result に sessionId が渡る', (tester) async {
    final sessions = [
      _buildSession(id: 's1', finishedAt: '2026-09-19T04:00:00.000Z'),
      _buildSession(id: 's2', finishedAt: '2026-09-19T03:00:00.000Z'),
    ];
    final controller = await _buildController(tester, sessions: sessions);
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('18 / 25').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('result:s2'), findsOneWidget);
  });

  testWidgets('空状態の表示とホームへ戻るボタン', (tester) async {
    final controller = await _buildController(tester);
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.textContaining('まだ受験履歴がありません'), findsOneWidget);

    await tester.tap(find.text('ホームへ'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('履歴も統計も無いとき削除ボタンが出ない', (tester) async {
    final controller = await _buildController(tester);
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('履歴をすべて削除'), findsNothing);
  });

  testWidgets('削除ボタンで確認シートが出て、キャンセルで残り、確定で消えて再描画される', (tester) async {
    final sessions = [
      _buildSession(id: 's1', finishedAt: '2026-09-19T04:00:00.000Z'),
    ];
    final controller = await _buildController(tester, sessions: sessions);
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('履歴をすべて削除'), findsOneWidget);

    await tester.tap(find.text('履歴をすべて削除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('元に戻せません'), findsOneWidget);

    // キャンセルではデータが残る。
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(controller.sessions, isNotEmpty);
    expect(find.textContaining('18 / 25'), findsOneWidget);

    // 確定で消えて画面が再描画される。
    await tester.tap(find.text('履歴をすべて削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除する'));
    await tester.pumpAndSettle();

    expect(controller.sessions, isEmpty);
    expect(find.textContaining('まだ受験履歴がありません'), findsOneWidget);
    expect(find.text('履歴をすべて削除'), findsNothing);
  });

  testWidgets('ストレージ利用不可のとき警告バナーが出る', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = HistoryController(
      examRepository: _singleExamRepository(),
      storageRepository: _UnavailableStorageRepository(),
    );
    await controller.load();
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(controller.storageAvailable, isFalse);
    expect(find.textContaining('この端末では記録が保存されない'), findsOneWidget);
  });

  testWidgets('履歴0件でも問題ごとの記録があれば削除ボタンが出る', (tester) async {
    final controller = await _buildController(
      tester,
      statRounds: [
        [(no: 5, correct: false)],
      ],
    );
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(controller.sessions, isEmpty);
    expect(controller.stats.tracked, greaterThan(0));
    expect(find.text('履歴をすべて削除'), findsOneWidget);
  });

  testWidgets('復習モードのセッションは「復習」と表示される', (tester) async {
    final sessions = [
      _buildSession(
        id: 's1',
        finishedAt: '2026-09-19T04:00:00.000Z',
        mode: QuizMode.review,
      ),
    ];
    final controller = await _buildController(tester, sessions: sessions);
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('復習'), findsOneWidget);
    expect(find.text('本番通し'), findsNothing);
  });

  testWidgets('一問一答モードのセッションは「一問一答」と表示される', (tester) async {
    final sessions = [
      _buildSession(
        id: 's1',
        finishedAt: '2026-09-19T04:00:00.000Z',
        mode: QuizMode.drill,
      ),
    ];
    final controller = await _buildController(tester, sessions: sessions);
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('一問一答'), findsOneWidget);
    expect(find.text('本番通し'), findsNothing);
  });

  testWidgets('受験日時が finishedAt から期待どおりの書式で出る', (tester) async {
    final sessions = [
      _buildSession(id: 's1', finishedAt: '2026-09-19T04:05:00.000Z'),
    ];
    final controller = await _buildController(tester, sessions: sessions);
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.textContaining('2026/09/19'), findsOneWidget);
  });

  testWidgets('複数年度でも各セッションの examId で分野名が正しく引かれる', (tester) async {
    final sessions = [
      _buildSession(
        id: 's1',
        finishedAt: '2026-09-19T04:00:00.000Z',
        examId: _examId,
      ),
    ];
    final controller = await _buildController(
      tester,
      examRepository: _multiYearExamRepository(),
      sessions: sessions,
    );
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();

    // index.json の先頭は 27 回だが、セッションの examId は 28 回。
    // 28 回の分野名で出て、27 回の分野名にはならないこと。
    expect(find.textContaining('介護支援分野 18/25'), findsOneWidget);
    expect(find.textContaining('介護支援分野（27回） 18/25'), findsNothing);
  });

  testWidgets('結果画面から pop で戻ると再読み込みされ、履歴の変化が反映される'
      '（RouteAware の didPopNext）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageRepository();
    await storage.init();
    await storage.saveSession(
      _buildSession(id: 's1', finishedAt: '2026-09-19T04:00:00.000Z'),
    );
    final controller = _CountingHistoryController(
      examRepository: _singleExamRepository(),
      storageRepository: storage,
    );

    // initState が controller.load() を呼ぶため、ここでは事前ロードしない。
    await tester.pumpWidget(_wrap(HistoryScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(controller.loadCallCount, 1);
    expect(find.textContaining('18 / 25'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );

    // 結果画面を見ている間に全削除が起きた状態を模す
    // （別タブ・別経路での削除も含め、戻ってきたら最新化されるべき）。
    navigator.pushNamed('/result', arguments: 's1');
    await tester.pumpAndSettle();
    await storage.clearAll();

    navigator.pop();
    await tester.pumpAndSettle();

    expect(controller.loadCallCount, 2);
    expect(find.textContaining('まだ受験履歴がありません'), findsOneWidget);
    expect(find.textContaining('18 / 25'), findsNothing);
  });
}
