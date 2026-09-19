import 'package:care_manager_exam_app/core/models/current_session.dart';
import 'package:care_manager_exam_app/core/models/session.dart';
import 'package:care_manager_exam_app/data/exam_repository.dart';
import 'package:care_manager_exam_app/data/storage_repository.dart';
import 'package:care_manager_exam_app/features/quiz/quiz_controller.dart';
import 'package:care_manager_exam_app/features/quiz/quiz_screen.dart';
import 'package:care_manager_exam_app/theme/app_theme.dart';
import 'package:care_manager_exam_app/theme/app_tokens.dart';
import 'package:care_manager_exam_app/widgets/number_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// exam-28.json 24番は本文219文字（長文問題の実データ）、selectCount=2。
// 1番は短文の選択肢で構成される。復習/本番の出題順検証にも使う。
const _examId = '28';
const _longQuestionNo = 24;

// QuizController.load() は rootBundle.loadString（プラットフォームチャネル
// 経由の非同期I/O）を含むため、testWidgets 内で直接 await すると解決されず
// ハングする。tester.runAsync で実時間のイベントループに載せる必要がある。
Future<QuizController> _buildController(
  WidgetTester tester, {
  required List<int> questionNos,
  String examId = _examId,
  int cursor = 0,
  Map<int, List<int>> answers = const {},
  QuizMode mode = QuizMode.full,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageRepository();
  final controller = QuizController(
    examRepository: ExamRepository(),
    storageRepository: storage,
  );
  await tester.runAsync(() async {
    await storage.init();
    await storage.saveCurrent(
      CurrentSession(
        examId: examId,
        mode: mode,
        startedAt: '2026-09-19T00:00:00.000Z',
        questionNos: questionNos,
        cursor: cursor,
        answers: answers,
      ),
    );
    await controller.load();
  });
  return controller;
}

// MaterialApp の home パラメータは名前付きルート '/' を home 自身に固定して
// しまい、pushReplacementNamed('/') が QuizScreen を作り直す無限ループになる
// ため使わない。initialRoute + onGenerateRoute だけで組む。
Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    initialRoute: '/quiz',
    onGenerateRoute: (settings) {
      if (settings.name == '/quiz') {
        return MaterialPageRoute(builder: (_) => child);
      }
      if (settings.name == '/result') {
        return MaterialPageRoute(
          builder: (_) => Scaffold(body: Text('result:${settings.arguments}')),
        );
      }
      if (settings.name == '/') {
        return MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('home')),
        );
      }
      return null;
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('current が無い状態で開くとホームへ pushReplacement する', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageRepository();
    await storage.init();
    final controller = QuizController(
      examRepository: ExamRepository(),
      storageRepository: storage,
    );

    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('index.json に無い examId のときは永久スピナーにならず警告からホームへ戻れる', (
    tester,
  ) async {
    final controller = await _buildController(
      tester,
      questionNos: const [1],
      examId: '9999',
    );

    expect(controller.loading, isFalse);
    expect(controller.shouldRedirectHome, isFalse);
    expect(controller.loadError, isTrue);

    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('問題データの読み込みに失敗しました'), findsOneWidget);

    await tester.tap(find.text('ホームへ戻る'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('長い問題文でスクロールした状態から選択肢をタップしてもスクロール位置が変わらない', (tester) async {
    final controller = await _buildController(
      tester,
      questionNos: const [_longQuestionNo],
    );
    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    // 選択肢が画面外に出るよう十分な距離をスクロールする。
    await tester.drag(scrollable, const Offset(0, -400));
    await tester.pumpAndSettle();

    final scrollableState = tester.state<ScrollableState>(scrollable);
    final offsetBefore = scrollableState.position.pixels;
    expect(offsetBefore, greaterThan(0));

    await tester.tap(find.text('1').first);
    await tester.pump();

    final offsetAfter = scrollableState.position.pixels;
    expect(offsetAfter, offsetBefore);
  });

  testWidgets('設問を切り替えたときは先頭に戻る', (tester) async {
    final controller = await _buildController(
      tester,
      questionNos: const [_longQuestionNo, 1],
    );
    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -400));
    await tester.pumpAndSettle();

    final scrollableState = tester.state<ScrollableState>(scrollable);
    expect(scrollableState.position.pixels, greaterThan(0));

    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();

    expect(scrollableState.position.pixels, 0);
  });

  testWidgets('selectCount に達したらそれ以上選べずトーストが出る', (tester) async {
    // 24番は selectCount=2。選択肢は5件（1〜5）。
    final controller = await _buildController(
      tester,
      questionNos: const [_longQuestionNo],
    );
    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1').first);
    await tester.pump();
    await tester.tap(find.text('2').first);
    await tester.pump();

    expect(find.text('2 / 2 選択中'), findsOneWidget);

    await tester.tap(find.text('3').first);
    await tester.pump();

    expect(find.text('2つまで選べます'), findsOneWidget);
    expect(controller.selectionOf(_longQuestionNo).value, {1, 2});

    // AppToast 内部の Future.delayed のタイマーを消化してから終える。
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('選択済みを再タップで解除できる', (tester) async {
    final controller = await _buildController(
      tester,
      questionNos: const [_longQuestionNo],
    );
    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1').first);
    await tester.pump();
    expect(controller.selectionOf(_longQuestionNo).value, {1});

    await tester.tap(find.text('1').first);
    await tester.pump();
    expect(controller.selectionOf(_longQuestionNo).value, isEmpty);
  });

  testWidgets('1問回答するたびに saveCurrent が呼ばれる（cme:current が即時更新される）', (
    tester,
  ) async {
    final controller = await _buildController(
      tester,
      questionNos: const [_longQuestionNo],
    );
    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1').first);
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cme:current');
    expect(raw, contains('"$_longQuestionNo":[1]'));
  });

  testWidgets('未回答があるとき採点するで確認シートが出る', (tester) async {
    final controller = await _buildController(
      tester,
      questionNos: const [1, 2],
    );
    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('採点する'));
    await tester.pumpAndSettle();

    expect(find.textContaining('未回答が2問あります'), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('未回答0件なら確認なしで採点され結果画面へ遷移する', (tester) async {
    final controller = await _buildController(
      tester,
      questionNos: const [1],
      answers: const {
        1: [1, 2, 3],
      },
    );
    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('採点する'));
    await tester.pumpAndSettle();

    expect(find.textContaining('result:'), findsOneWidget);
  });

  testWidgets('二重採点が防止される', (tester) async {
    final controller = await _buildController(
      tester,
      questionNos: const [1],
      answers: const {
        1: [1, 2, 3],
      },
    );

    final firstId = await controller.gradeAndFinish();
    final secondId = await controller.gradeAndFinish();

    expect(firstId, isNotNull);
    expect(secondId, isNull);

    final storage = StorageRepository();
    await storage.init();
    expect(storage.loadSessions(), hasLength(1));
  });

  testWidgets('回答状況シートからジャンプできる', (tester) async {
    final controller = await _buildController(
      tester,
      questionNos: const [1, 2, 3],
    );
    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('回答状況'));
    await tester.pumpAndSettle();

    // labelOf 未指定時のグリッドは index+1（1-indexed）を表示する。
    // 3番目のセルをタップして 3問目へ。
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();

    expect(controller.cursorIndex, 2);
  });

  testWidgets('復習モードでは回答状況シートのグリッドに実際の問番号が表示される', (tester) async {
    final controller = await _buildController(
      tester,
      questionNos: const [3, 17, 42],
      mode: QuizMode.review,
    );
    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('回答状況'));
    await tester.pumpAndSettle();

    // グリッドは questionNos の並び順で実際の問番号をラベル表示する。
    // index+1（1,2,3）ではなく 3,17,42 のはず。グリッド内のセルだけを見る
    // （本文側の選択肢番号バッジにも "1" 等が出るため）。
    final gridLabels = find.descendant(
      of: find.byType(NumberGrid),
      matching: find.byType(Text),
    );
    final labels = tester
        .widgetList<Text>(gridLabels)
        .map((t) => t.data)
        .toList();
    expect(labels, ['3', '17', '42']);

    await tester.tap(
      find.descendant(of: find.byType(NumberGrid), matching: find.text('42')),
    );
    await tester.pumpAndSettle();

    expect(controller.cursorIndex, 2);
    expect(controller.currentNo, 42);
  });

  testWidgets('回答済みかつ現在地のセルは回答済みの背景と現在地の枠を両方示す', (tester) async {
    final controller = await _buildController(
      tester,
      questionNos: const [1, 2, 3],
      answers: const {
        1: [1],
      },
    );
    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('回答状況'));
    await tester.pumpAndSettle();

    final theme = AppTheme.light;
    final tokens = theme.extension<AppTokens>()!;

    // 1問目のセル（回答済みかつ現在地）はグリッド内でだけ探す
    // （本文の選択肢番号バッジにも "1" が出るため）。
    final currentCellLabel = find.descendant(
      of: find.byType(NumberGrid),
      matching: find.text('1'),
    );
    final currentCellContainer = tester.widget<Container>(
      find
          .ancestor(of: currentCellLabel, matching: find.byType(Container))
          .first,
    );
    final decoration = currentCellContainer.decoration! as BoxDecoration;

    // 現在地（1問目）は回答済みの背景色を保ったまま、枠だけが強調される。
    final material = tester.widget<Material>(
      find
          .ancestor(of: currentCellLabel, matching: find.byType(Material))
          .first,
    );
    expect(material.color, theme.colorScheme.primary);
    expect(decoration.border!.top.width, 2.0);
    expect(decoration.border!.top.color, isNot(tokens.none));
  });

  testWidgets('演習中に正誤が表示されない', (tester) async {
    final controller = await _buildController(tester, questionNos: const [1]);
    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1').first);
    await tester.pump();

    expect(find.textContaining('正解'), findsNothing);
    expect(find.textContaining('不正解'), findsNothing);
  });

  testWidgets('下部バーのボタンがシステムのナビゲーションバーに隠れない', (tester) async {
    // 実機（Pixel 8 の縦持ち）で下部バーがシステムのナビゲーションバーに
    // 隠れて押せなかった。viewPadding を与えて再現する。
    const navBarHeight = 48.0;
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.viewPadding = const FakeViewPadding(bottom: navBarHeight);
    tester.view.padding = const FakeViewPadding(bottom: navBarHeight);

    final controller = await _buildController(
      tester,
      questionNos: const [1],
      answers: const {
        1: [1, 2, 3],
      },
    );
    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    final buttonRect = tester.getRect(find.text('採点する'));

    // ボタンの下端がナビゲーションバーの上端より上にあること。
    expect(buttonRect.bottom, lessThanOrEqualTo(800 - navBarHeight));

    // タップが実際に届くこと（ナビゲーションバーに吸われていない）。
    await tester.tap(find.text('採点する'));
    await tester.pumpAndSettle();

    expect(find.textContaining('result:'), findsOneWidget);
  });

  testWidgets('下部バーのボタンがシステムのナビゲーションバーに隠れず、画面全高にも広がらない', (tester) async {
    // 実機（Pixel 8 の縦持ち）でボタンがナビゲーションバーに隠れて押せなかった。
    // 高さの上限を外すとボタンが画面全高のタップ領域になり本文が押せなくなる。
    const navBar = 48.0;
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    tester.view.padding = const FakeViewPadding(bottom: navBar);

    final controller = await _buildController(tester, questionNos: [1, 2]);
    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.text('採点する'));
    expect(bar.bottom, lessThanOrEqualTo(800 - navBar));

    final button = tester.getRect(
      find
          .ancestor(of: find.text('採点する'), matching: find.byType(InkWell))
          .first,
    );
    expect(button.height, lessThan(80));
  });

  testWidgets('採点確認シートのボタンがシステムのナビゲーションバーに隠れない', (tester) async {
    // 実機（Pixel 8 の縦持ち）で確認シートのボタンがナビゲーションバーに
    // 隠れて押せなかった。viewPadding を与えて再現する。
    const navBar = 48.0;
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    tester.view.padding = const FakeViewPadding(bottom: navBar);

    final controller = await _buildController(
      tester,
      questionNos: const [1, 2],
    );
    await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('採点する'));
    await tester.pumpAndSettle();

    final cancelRect = tester.getRect(find.text('キャンセル'));
    final confirmRect = tester.getRect(find.text('採点する').last);

    // シートのボタンの下端がナビゲーションバーの上端より上にあること。
    expect(cancelRect.bottom, lessThanOrEqualTo(800 - navBar));
    expect(confirmRect.bottom, lessThanOrEqualTo(800 - navBar));

    // ボタンが画面全高のタップ領域になっていないこと。
    final button = tester.getRect(
      find
          .ancestor(of: find.text('キャンセル'), matching: find.byType(InkWell))
          .first,
    );
    expect(button.height, greaterThanOrEqualTo(40));
    expect(button.height, lessThan(80));
  });
}
