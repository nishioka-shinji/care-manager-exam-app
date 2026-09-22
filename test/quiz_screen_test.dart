import 'dart:convert';

import 'package:care_manager_exam_app/core/models/current_session.dart';
import 'package:care_manager_exam_app/core/models/session.dart';
import 'package:care_manager_exam_app/data/exam_repository.dart';
import 'package:care_manager_exam_app/data/storage_repository.dart';
import 'package:care_manager_exam_app/features/quiz/quiz_controller.dart';
import 'package:care_manager_exam_app/features/quiz/quiz_screen.dart';
import 'package:care_manager_exam_app/features/quiz/widgets/answer_sheet.dart';
import 'package:care_manager_exam_app/features/quiz/widgets/choice_tile.dart';
import 'package:care_manager_exam_app/theme/app_theme.dart';
import 'package:care_manager_exam_app/theme/app_tokens.dart';
import 'package:care_manager_exam_app/widgets/app_badge.dart';
import 'package:care_manager_exam_app/widgets/app_button.dart';
import 'package:care_manager_exam_app/widgets/number_grid.dart';
import 'package:care_manager_exam_app/widgets/result_mark.dart';
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

  group('NumberGrid の cellStatusOf', () {
    // 一問一答モードの回答状況シートは「正解/不正解/回答済み(答え合わせ前)/
    // 未回答」の4値を同時に扱うため、answeredOf・statusOf では表現できない
    // （T5）。cellStatusOf で4値それぞれの背景色を検証する。
    Color materialColorOf(WidgetTester tester, String label) {
      final material = tester.widget<Material>(
        find
            .ancestor(
              of: find.descendant(
                of: find.byType(NumberGrid),
                matching: find.text(label),
              ),
              matching: find.byType(Material),
            )
            .first,
      );
      return material.color!;
    }

    testWidgets('answered/ok/ng/none で背景色が4値とも異なる', (tester) async {
      const statuses = [
        CellStatus.answered,
        CellStatus.ok,
        CellStatus.ng,
        CellStatus.none,
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NumberGrid(
              count: statuses.length,
              cellStatusOf: (index) => statuses[index],
              onTap: (_) {},
            ),
          ),
        ),
      );

      final theme = AppTheme.light;
      final tokens = theme.extension<AppTokens>()!;

      // answered は accent（primary）、ok は正解の緑（tokens.ok）で、
      // 同じ色に潰れていないことが4値対応の核心。
      expect(materialColorOf(tester, '1'), theme.colorScheme.primary);
      expect(materialColorOf(tester, '2'), tokens.ok);
      expect(materialColorOf(tester, '3'), tokens.ng);
      expect(materialColorOf(tester, '4'), tokens.none);

      expect(materialColorOf(tester, '1'), isNot(materialColorOf(tester, '2')));
    });

    testWidgets('answeredOf・statusOf と併用しても cellStatusOf が優先される', (
      tester,
    ) async {
      // cellStatusOf は「他のコールバックより優先する」契約（number_grid.dart）。
      // answeredOf/statusOf も同時に渡し、判定順が入れ替わっていないかを見る。
      // 判定順を statusOf 最優先や answeredOf 最優先に入れ替えても、
      // cellStatusOf 単独指定のテストだけでは検出できない（統合レビュー F1）。
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NumberGrid(
              count: 1,
              cellStatusOf: (_) => CellStatus.ok,
              answeredOf: (_) => true,
              statusOf: (_) => AppBadgeStatus.ng,
              onTap: (_) {},
            ),
          ),
        ),
      );

      final theme = AppTheme.light;
      final tokens = theme.extension<AppTokens>()!;

      // cellStatusOf が優先されるなら tokens.ok。answeredOf が勝てば primary、
      // statusOf が勝てば tokens.ng になり、どちらもここでは不正解。
      expect(materialColorOf(tester, '1'), tokens.ok);
      expect(materialColorOf(tester, '1'), isNot(theme.colorScheme.primary));
      expect(materialColorOf(tester, '1'), isNot(tokens.ng));
    });
  });

  group('drill モード（一問一答）', () {
    // exam-28.json: 1番は selectCount=2 answers=[3,4]、2番は selectCount=3
    // answers=[1,2,3]、3番は selectCount=3 answers=[2,3,4]。

    testWidgets('選択数未達なら revealCurrent は拒否され、revealed にも stats にも何も記録されない', (
      tester,
    ) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 2, 3],
        mode: QuizMode.drill,
        answers: const {
          1: [3],
        },
      );

      final ok = await controller.revealCurrent(2);

      expect(ok, isFalse);
      expect(controller.isRevealed(1), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cme:stats'), isNull);
      final raw = prefs.getString('cme:current');
      expect(raw, isNot(contains('revealed')));
    });

    testWidgets(
      '選択数到達で revealCurrent すると revealed が問番号昇順で永続化され、stats.attempts が1増える',
      (tester) async {
        final controller = await _buildController(
          tester,
          questionNos: const [1, 2, 3],
          mode: QuizMode.drill,
          answers: const {
            1: [3, 4],
          },
        );

        final ok = await controller.revealCurrent(2);

        expect(ok, isTrue);
        expect(controller.isRevealed(1), isTrue);

        final prefs = await SharedPreferences.getInstance();
        final currentRaw = prefs.getString('cme:current')!;
        expect(currentRaw, contains('"revealed":[1]'));

        final statsRaw = jsonDecode(prefs.getString('cme:stats')!) as Map;
        final entry = (statsRaw[_examId] as Map)['1'] as Map;
        expect(entry['attempts'], 1);
        expect(entry['correct'], 1);
      },
    );

    testWidgets('不正解を選択してrevealCurrentするとcorrectは0、lastCorrectはfalseになる', (
      tester,
    ) async {
      final controller = await _buildController(
        tester,
        questionNos: const [2],
        mode: QuizMode.drill,
        answers: const {
          2: [1, 2, 4], // 2番の正解は[1,2,3]なので不正解
        },
      );

      final ok = await controller.revealCurrent(3);

      expect(ok, isTrue);
      final prefs = await SharedPreferences.getInstance();
      final statsRaw = jsonDecode(prefs.getString('cme:stats')!) as Map;
      final entry = (statsRaw[_examId] as Map)['2'] as Map;
      expect(entry['attempts'], 1);
      expect(entry['correct'], 0);
      expect(entry['lastCorrect'], isFalse);
    });

    testWidgets('答え合わせ済みの問に再度revealCurrentしても拒否され、attemptsは1のまま', (
      tester,
    ) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1],
        mode: QuizMode.drill,
        answers: const {
          1: [3, 4],
        },
      );

      final first = await controller.revealCurrent(2);
      final second = await controller.revealCurrent(2);

      expect(first, isTrue);
      expect(second, isFalse);

      final prefs = await SharedPreferences.getInstance();
      final statsRaw = jsonDecode(prefs.getString('cme:stats')!) as Map;
      final entry = (statsRaw[_examId] as Map)['1'] as Map;
      expect(entry['attempts'], 1);
    });

    testWidgets('答え合わせした問の後にgoToしてもrevealedが消えず、新しいcontrollerでloadしても復元される', (
      tester,
    ) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 2, 3],
        mode: QuizMode.drill,
        answers: const {
          1: [3, 4],
        },
      );

      await controller.revealCurrent(2);
      await controller.goTo(1);

      final prefs = await SharedPreferences.getInstance();
      final currentRaw = prefs.getString('cme:current')!;
      expect(currentRaw, contains('"revealed":[1]'));

      final storage = StorageRepository();
      await storage.init();
      final reloaded = QuizController(
        examRepository: ExamRepository(),
        storageRepository: storage,
      );
      await tester.runAsync(() => reloaded.load());

      expect(reloaded.isRevealed(1), isTrue);
    });

    testWidgets('答え合わせした問の後に別の問をtoggleChoiceしてもrevealedがcme:currentに残る', (
      tester,
    ) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 2, 3],
        mode: QuizMode.drill,
        cursor: 1,
        answers: const {
          1: [3, 4],
        },
      );
      await controller.goTo(0);
      await controller.revealCurrent(2);
      await controller.goTo(1);

      controller.toggleChoice(2, 1, 3);

      final prefs = await SharedPreferences.getInstance();
      final currentRaw = prefs.getString('cme:current')!;
      expect(currentRaw, contains('"revealed":[1]'));
    });

    testWidgets('答え合わせした問が複数のときrevealedは問番号昇順で永続化される', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 2, 3],
        mode: QuizMode.drill,
        cursor: 1,
        answers: const {
          1: [3, 4],
          2: [1, 2, 3],
        },
      );
      await controller.goTo(0);
      await controller.revealCurrent(2);
      await controller.goTo(1);
      final ok = await controller.revealCurrent(3);

      expect(ok, isTrue);
      final prefs = await SharedPreferences.getInstance();
      final currentRaw = prefs.getString('cme:current')!;
      expect(currentRaw, contains('"revealed":[1,2]'));
    });

    testWidgets('二重計上しない: 3問中2問を答え合わせしてfinishDrillしてもattemptsは1のまま', (
      tester,
    ) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 2, 3],
        mode: QuizMode.drill,
        answers: const {
          1: [3, 4], // 正解
          2: [1, 2, 4], // 不正解
        },
      );

      await controller.goTo(0);
      await controller.revealCurrent(2);
      await controller.goTo(1);
      await controller.revealCurrent(3);

      final result = await controller.finishDrill();
      expect(result.id, isNotNull);
      expect(result.noRevealed, isFalse);

      final prefs = await SharedPreferences.getInstance();
      final statsRaw = jsonDecode(prefs.getString('cme:stats')!) as Map;
      final bucket = statsRaw[_examId] as Map;
      expect((bucket['1'] as Map)['attempts'], 1);
      expect((bucket['2'] as Map)['attempts'], 1);
    });

    testWidgets('部分採点: 3問中2問だけ答え合わせしてfinishDrillするとscore.maxは2、1問正解ならtotalは1', (
      tester,
    ) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 2, 3],
        mode: QuizMode.drill,
        answers: const {
          1: [3, 4], // 正解
          2: [1, 2, 4], // 不正解
        },
      );

      await controller.goTo(0);
      await controller.revealCurrent(2);
      await controller.goTo(1);
      await controller.revealCurrent(3);

      final result = await controller.finishDrill();
      expect(result.id, isNotNull);
      expect(result.noRevealed, isFalse);

      final storage = StorageRepository();
      await storage.init();
      final session = storage.getSessionById(result.id!)!;
      expect(session.score.max, 2);
      expect(session.score.total, 1);
    });

    testWidgets('0件でfinishDrillしてもsessionが作られず、cme:currentも消えない', (
      tester,
    ) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 2, 3],
        mode: QuizMode.drill,
      );

      final result = await controller.finishDrill();

      expect(result.id, isNull);
      expect(result.noRevealed, isTrue);

      final storage = StorageRepository();
      await storage.init();
      expect(storage.loadSessions(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cme:current'), isNotNull);
    });

    testWidgets('2回目のfinishDrillは採点済みでnullだが、0件（noRevealed）とは区別される', (
      tester,
    ) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1],
        mode: QuizMode.drill,
        answers: const {
          1: [3, 4],
        },
      );
      await controller.revealCurrent(2);

      final first = await controller.finishDrill();
      expect(first.id, isNotNull);
      expect(first.noRevealed, isFalse);

      final second = await controller.finishDrill();
      expect(second.id, isNull);
      expect(second.noRevealed, isFalse);
    });

    testWidgets('答え合わせ済みの問でtoggleChoiceが拒否される', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1],
        mode: QuizMode.drill,
        answers: const {
          1: [3, 4],
        },
      );
      await controller.revealCurrent(2);

      final result = controller.toggleChoice(1, 3, 2);

      expect(result, isFalse);
      expect(controller.selectionOf(1).value, {3, 4});
    });

    testWidgets('中断・再開: revealed入りのcme:currentからloadするとisRevealedが復元される', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageRepository();
      await storage.init();
      await storage.saveCurrent(
        CurrentSession(
          examId: _examId,
          mode: QuizMode.drill,
          startedAt: '2026-09-19T00:00:00.000Z',
          questionNos: const [1, 2, 3],
          cursor: 0,
          answers: const {
            1: [3, 4],
          },
          revealed: const [1],
        ),
      );
      final controller = QuizController(
        examRepository: ExamRepository(),
        storageRepository: storage,
      );

      await tester.runAsync(() => controller.load());

      expect(controller.isRevealed(1), isTrue);
      expect(controller.isRevealed(2), isFalse);
      expect(controller.isCurrentRevealed, isTrue);
    });

    testWidgets(
      'fullモード+revealed入りのcme:currentをloadしてもisRevealedにならず選択肢がタップできる（外部改変耐性）',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final storage = StorageRepository();
        await storage.init();
        await storage.saveCurrent(
          CurrentSession(
            examId: _examId,
            mode: QuizMode.full,
            startedAt: '2026-09-19T00:00:00.000Z',
            questionNos: const [1, 2, 3],
            cursor: 0,
            answers: const {},
            revealed: const [1, 2],
          ),
        );
        final controller = QuizController(
          examRepository: ExamRepository(),
          storageRepository: storage,
        );

        await tester.runAsync(() => controller.load());

        expect(controller.isRevealed(1), isFalse);
        expect(controller.toggleChoice(1, 3, 2), isTrue);
        expect(controller.selectionOf(1).value, {3});
      },
    );

    testWidgets('full/reviewモードではrevealCurrentは常に拒否される（回帰防止）', (tester) async {
      final controllerFull = await _buildController(
        tester,
        questionNos: const [1],
        answers: const {
          1: [3, 4],
        },
      );
      expect(await controllerFull.revealCurrent(2), isFalse);
      expect(controllerFull.isCurrentRevealed, isFalse);

      final controllerReview = await _buildController(
        tester,
        questionNos: const [1],
        mode: QuizMode.review,
        answers: const {
          1: [3, 4],
        },
      );
      expect(await controllerReview.revealCurrent(2), isFalse);
      expect(controllerReview.isCurrentRevealed, isFalse);
    });

    testWidgets('full/reviewモードの既存挙動は変わらない: gradeAndFinishが引数なしで出題全件を採点する', (
      tester,
    ) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 2],
        answers: const {
          1: [3, 4],
        },
      );

      final id = await controller.gradeAndFinish();
      expect(id, isNotNull);

      final storage = StorageRepository();
      await storage.init();
      final session = storage.getSessionById(id!)!;
      expect(session.score.max, 2);

      final statsRaw = jsonDecode(
        (await SharedPreferences.getInstance()).getString('cme:stats')!,
      );
      final bucket = (statsRaw as Map)[_examId] as Map;
      expect(bucket.containsKey('1'), isTrue);
      expect(bucket.containsKey('2'), isTrue);
    });
  });

  group('drill モードの演習画面UI', () {
    // exam-28.json 24番: selectCount=2 answers=[2,3]、本文219文字の長文問題。
    // 1番: selectCount=2 answers=[3,4]。3番: selectCount=3 answers=[2,3,4]。

    testWidgets('答え合わせボタン押下でスクロール位置が変わらず、設問切替でのみ先頭へ戻る', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [_longQuestionNo, 1],
        mode: QuizMode.drill,
        answers: const {
          _longQuestionNo: [2, 3],
        },
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pumpAndSettle();

      final scrollableState = tester.state<ScrollableState>(scrollable);
      final offsetBefore = scrollableState.position.pixels;
      expect(offsetBefore, greaterThan(0));

      await tester.tap(find.text('答え合わせ'));
      await tester.pump();

      expect(scrollableState.position.pixels, offsetBefore);

      await tester.tap(find.text('次の問題へ'));
      await tester.pumpAndSettle();

      expect(scrollableState.position.pixels, 0);
    });

    testWidgets('答え合わせボタン押下では問題文（_QuizBody）が作り直されない', (tester) async {
      // ScrollController.offset は同一インスタンスなら Widget 再構築だけでは
      // リセットされないため、上のスクロールテストだけでは「_QuizBody が
      // 作り直されていないか」を検出できない。問題文 Text の Widget
      // インスタンスの identical 比較で、_QuizBody が再構築されていないこと
      // を直接見る（ChoiceTile 自体はフィードバック反映のため作り直されて
      // よい。作り直してはいけないのは _ChoiceList の外側）。
      final controller = await _buildController(
        tester,
        questionNos: const [1],
        mode: QuizMode.drill,
        answers: const {
          1: [3, 4],
        },
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      final questionTextFinder = find.text(controller.currentQuestion!.text);
      final textBefore = tester.widget<Text>(questionTextFinder);

      await tester.tap(find.text('答え合わせ'));
      await tester.pump();

      final textAfter = tester.widget<Text>(questionTextFinder);
      expect(identical(textBefore, textAfter), isTrue);
    });

    testWidgets('選択数未達では答え合わせが非活性、到達すると活性になる', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1],
        mode: QuizMode.drill,
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      AppButton buttonOf(String label) =>
          tester.widget<AppButton>(find.widgetWithText(AppButton, label));

      expect(buttonOf('答え合わせ').onPressed, isNull);

      await tester.tap(find.text('3').first);
      await tester.pump();
      expect(buttonOf('答え合わせ').onPressed, isNull);

      await tester.tap(find.text('4').first);
      await tester.pump();
      expect(buttonOf('答え合わせ').onPressed, isNotNull);
    });

    testWidgets('答え合わせで正誤バッジ・正解番号・選択肢のマークと解説が出る', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1],
        mode: QuizMode.drill,
        answers: const {
          1: [3, 4],
        },
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('正解'), findsNothing);

      await tester.tap(find.text('答え合わせ'));
      await tester.pump();

      // 1番の正解は選択肢3・4の2件のみ（1,2,5は不正解）。件数まで見ないと
      // 表示条件の反転（不正解側に付く）を見逃す。ResultMark で絞り込み、
      // AppBadge（正誤バッジ）の「正解」ラベルと混同しないようにする。
      expect(find.widgetWithText(ResultMark, '正解'), findsNWidgets(2));
      expect(find.textContaining('正解は 3・4'), findsOneWidget);
      expect(find.widgetWithText(ResultMark, 'あなたの回答'), findsNWidgets(2));
      expect(find.textContaining('社会保険は、保険料を納めて加入者が給付を'), findsOneWidget);

      // バナー（正解は…）が問題文と選択肢リストの間にあること（移植元
      // quiz.js:96-103 の DOM 順）。座標比較なら本番の Widget 構造を
      // 書き写さずに済む。選択肢1件目は「1.」の丸数字バッジで特定する。
      final questionY = tester
          .getTopLeft(find.text(controller.currentQuestion!.text))
          .dy;
      final bannerY = tester.getTopLeft(find.textContaining('正解は 3・4')).dy;
      final firstChoiceY = tester.getTopLeft(find.text('1').first).dy;
      expect(bannerY, greaterThan(questionY));
      expect(bannerY, lessThan(firstChoiceY));
    });

    testWidgets('答え合わせ後は選択肢のInkWellが無効化されタップしても選択もトーストも変わらない', (tester) async {
      // controller.toggleChoice の isRevealed ガードだけでも
      // selectionOf の値は満たせてしまう（QuizController 側の担保）ため、
      // ここでは ChoiceTile 側の onTap: revealed ? null : onTap が
      // 実際に外れていることを直接見る。トーストが出ないことも検証する
      // （UI ガードが外れると「2つまで選べます」という文脈外のトーストが
      // 答え合わせ後の選択肢タップで出てしまう）。
      final controller = await _buildController(
        tester,
        questionNos: const [1],
        mode: QuizMode.drill,
        answers: const {
          1: [3, 4],
        },
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('答え合わせ'));
      await tester.pump();

      final firstTile = find.byType(ChoiceTile).first;
      final inkWell = tester.widget<InkWell>(
        find.descendant(of: firstTile, matching: find.byType(InkWell)).first,
      );
      expect(inkWell.onTap, isNull);

      await tester.tap(find.text('1').first);
      await tester.pump();

      expect(controller.selectionOf(1).value, {3, 4});
      expect(find.text('2つまで選べます'), findsNothing);

      // AppToast 内部の Future.delayed のタイマーを消化してから終える。
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('答え合わせ後は下部バーが次の問題へに変わり、最後の問では結果を見るになる', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1],
        mode: QuizMode.drill,
        answers: const {
          1: [3, 4],
        },
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('次へ'), findsOneWidget);
      expect(find.text('採点する'), findsNothing);

      await tester.tap(find.text('答え合わせ'));
      await tester.pump();

      expect(find.text('答え合わせ'), findsNothing);
      expect(find.text('次の問題へ'), findsNothing);
      expect(find.text('結果を見る'), findsOneWidget);

      await tester.tap(find.text('結果を見る'));
      await tester.pumpAndSettle();

      expect(find.textContaining('result:'), findsOneWidget);
    });

    testWidgets('答え合わせ後、最後の問でなければ次の問題への遷移で先頭問へ戻れる', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 3],
        mode: QuizMode.drill,
        answers: const {
          1: [3, 4],
        },
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('答え合わせ'));
      await tester.pump();

      expect(find.text('次の問題へ'), findsOneWidget);
      expect(find.text('結果を見る'), findsNothing);

      await tester.tap(find.text('次の問題へ'));
      await tester.pumpAndSettle();

      expect(controller.cursorIndex, 1);
    });

    testWidgets('前の問へ戻ると答え合わせ済みの解説表示状態で復帰する', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 3],
        mode: QuizMode.drill,
        cursor: 1,
        answers: const {
          1: [3, 4],
        },
      );
      await controller.goTo(0);
      await controller.revealCurrent(2);
      await controller.goTo(1);

      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('答え合わせ'), findsOneWidget);

      await tester.tap(find.text('前へ'));
      await tester.pumpAndSettle();

      expect(find.text('正解'), findsWidgets);
      expect(find.textContaining('正解は 3・4'), findsOneWidget);
      expect(find.text('答え合わせ'), findsNothing);
    });

    testWidgets('drillのsubtitleは一問一答になる', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1],
        mode: QuizMode.drill,
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('一問一答'), findsOneWidget);
      expect(find.text('本番通し'), findsNothing);
      expect(find.text('復習モード'), findsNothing);
    });

    testWidgets('full（本番通し）では答え合わせボタンもフィードバックも一切出ない（回帰防止）', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1],
        answers: const {
          1: [3, 4],
        },
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('答え合わせ'), findsNothing);
      expect(find.text('本番通し'), findsOneWidget);
      expect(find.textContaining('正解は'), findsNothing);
    });

    testWidgets('review（復習モード）では答え合わせボタンもフィードバックも一切出ない（回帰防止）', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1],
        mode: QuizMode.review,
        answers: const {
          1: [3, 4],
        },
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('答え合わせ'), findsNothing);
      expect(find.text('復習モード'), findsOneWidget);
      expect(find.textContaining('正解は'), findsNothing);
    });
  });

  group('回答状況シート（drill対応）', () {
    // exam-28.json: 1番 selectCount=2 answers=[3,4]、2番 selectCount=3
    // answers=[1,2,3]、3番 selectCount=3 answers=[2,3,4]。

    testWidgets('drillでは説明文が差し替わり、full/reviewでは従来文言のまま', (tester) async {
      final drillController = await _buildController(
        tester,
        questionNos: const [1],
        mode: QuizMode.drill,
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: drillController)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('回答状況'));
      await tester.pumpAndSettle();

      expect(
        find.text('タップした問題へ移動します。緑は正解・赤は不正解・グレーはまだ答え合わせしていない問題です。'),
        findsOneWidget,
      );
      expect(find.text('タップした問題へ移動します。グレーは未回答です。'), findsNothing);
    });

    testWidgets('fullでは従来文言のまま', (tester) async {
      final controller = await _buildController(tester, questionNos: const [1]);
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('回答状況'));
      await tester.pumpAndSettle();

      expect(find.text('タップした問題へ移動します。グレーは未回答です。'), findsOneWidget);
      expect(
        find.text('タップした問題へ移動します。緑は正解・赤は不正解・グレーはまだ答え合わせしていない問題です。'),
        findsNothing,
      );
    });

    testWidgets('答え合わせ済みの正解問は緑、不正解問は赤、未答え合わせの回答済みはaccent、未回答はグレー', (
      tester,
    ) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 2, 3],
        mode: QuizMode.drill,
        cursor: 1,
        answers: const {
          1: [3, 4], // 正解、答え合わせ済み
          2: [1, 2, 4], // 不正解、答え合わせ済み
          3: [2, 3], // 回答済みだが答え合わせしていない（selectCount未達で保存）
        },
      );
      await controller.goTo(0);
      await controller.revealCurrent(2);
      await controller.goTo(1);
      await controller.revealCurrent(3);
      await controller.goTo(2);

      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('回答状況'));
      await tester.pumpAndSettle();

      Color materialColorOf(String label) {
        final material = tester.widget<Material>(
          find
              .ancestor(
                of: find.descendant(
                  of: find.byType(NumberGrid),
                  matching: find.text(label),
                ),
                matching: find.byType(Material),
              )
              .first,
        );
        return material.color!;
      }

      final theme = AppTheme.light;
      final tokens = theme.extension<AppTokens>()!;

      expect(materialColorOf('1'), tokens.ok);
      expect(materialColorOf('2'), tokens.ng);
      expect(materialColorOf('3'), theme.colorScheme.primary);
    });

    testWidgets('drillでは「ここまでの結果を見る」が出る', (tester) async {
      final drillController = await _buildController(
        tester,
        questionNos: const [1, 2],
        mode: QuizMode.drill,
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: drillController)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答状況'));
      await tester.pumpAndSettle();

      expect(find.text('ここまでの結果を見る'), findsOneWidget);
    });

    testWidgets('fullでは「ここまでの結果を見る」が出ない', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 2],
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答状況'));
      await tester.pumpAndSettle();

      expect(find.text('ここまでの結果を見る'), findsNothing);
    });

    testWidgets('reviewでは「ここまでの結果を見る」が出ない', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 2],
        mode: QuizMode.review,
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答状況'));
      await tester.pumpAndSettle();

      expect(find.text('ここまでの結果を見る'), findsNothing);
    });

    testWidgets('「ここまでの結果を見る」押下でシートを閉じてから結果画面へ遷移し、母数が答え合わせ済みの件数になる', (
      tester,
    ) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 2, 3],
        mode: QuizMode.drill,
        cursor: 1,
        answers: const {
          1: [3, 4], // 正解、答え合わせ済み
          2: [1, 2, 4], // 不正解、答え合わせ済み
        },
      );
      await controller.goTo(0);
      await controller.revealCurrent(2);
      await controller.goTo(1);
      await controller.revealCurrent(3);

      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答状況'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ここまでの結果を見る'));
      await tester.pumpAndSettle();
      expect(find.textContaining('result:'), findsOneWidget);

      final storage = StorageRepository();
      await storage.init();
      final id =
          find.textContaining('result:').evaluate().single.widget as Text;
      final sessionId = id.data!.substring('result:'.length);
      final session = storage.getSessionById(sessionId)!;
      expect(session.score.max, 2);
    });

    testWidgets('「ここまでの結果を見る」でfinishDrillが呼ばれ、シートも閉じる', (tester) async {
      // AnswerSheet.show を直接呼び、onFinishDrill が実際に呼ばれることと
      // シートが最終的に閉じることを確認する。close() と onFinishDrill() の
      // 呼び出し順序そのものは、finishDrill 内部の await がテスト環境では
      // 同期的に解決されてしまうため widget テストでは判別できない
      // （T7報告の懸念事項を参照。実装は移植元 quiz.js:638-641 と同じ
      // close() → onFinishDrill() の順を維持する）。
      final controller = await _buildController(
        tester,
        questionNos: const [1],
        mode: QuizMode.drill,
        answers: const {
          1: [3, 4],
        },
      );
      await controller.revealCurrent(2);

      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: AppButton(
                  label: 'open',
                  variant: AppButtonVariant.base,
                  onPressed: () => AnswerSheet.show(
                    context,
                    controller,
                    onFinishDrill: () => calls.add('finishDrill'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ここまでの結果を見る'));
      await tester.pumpAndSettle();

      expect(calls, ['finishDrill']);
      expect(find.byType(NumberGrid), findsNothing);
      expect(find.text('閉じる'), findsNothing);
    });

    testWidgets('答え合わせ0件で「ここまでの結果を見る」を押してもトーストが出るだけで遷移しない', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 2],
        mode: QuizMode.drill,
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回答状況'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ここまでの結果を見る'));
      await tester.pumpAndSettle();

      expect(find.text('まず1問以上、答え合わせをしてください'), findsOneWidget);
      expect(find.textContaining('result:'), findsNothing);

      // AppToast 内部の Future.delayed のタイマーを消化してから終える。
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('二重送信（採点済みで下部バーの結果を見るを連打）ではトーストが出ない', (tester) async {
      // _handleFinishDrill を経由させ、id: null（二重送信）と
      // noRevealed: true（0件）の取り違えを実際のハンドラで検出する。
      // controller.finishDrill() を直接呼ぶだけではハンドラ内のロジックの
      // バグ（id==nullでトーストを出す誤り）を検出できない。onPressed を
      // 直接2回呼び、1回目の非同期処理が終わる前に2回目を送る連打を再現する
      // （tester.tap の連続呼び出しは1回目のジェスチャー処理待ちで
      // ヒットテストに失敗するため使えない）。
      final controller = await _buildController(
        tester,
        questionNos: const [1],
        mode: QuizMode.drill,
        answers: const {
          1: [3, 4],
        },
      );
      await controller.revealCurrent(2);
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      final onPressed = tester
          .widget<AppButton>(find.widgetWithText(AppButton, '結果を見る'))
          .onPressed!;
      onPressed();
      onPressed();
      await tester.pumpAndSettle();

      expect(find.textContaining('result:'), findsOneWidget);
      expect(find.text('まず1問以上、答え合わせをしてください'), findsNothing);
    });

    testWidgets('drillで未回答があっても採点する（結果を見る）で確認シートが出ない', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 3],
        mode: QuizMode.drill,
        answers: const {
          1: [3, 4],
        },
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('答え合わせ'));
      await tester.pump();

      expect(find.text('結果を見る'), findsNothing);

      await tester.tap(find.text('次の問題へ'));
      await tester.pumpAndSettle();

      // 3番は未回答のまま。「結果を見る」は出ないが、回答状況シートの
      // 「ここまでの結果を見る」から未回答確認シートを挟まずに遷移できる。
      await tester.tap(find.text('回答状況'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ここまでの結果を見る'));
      await tester.pumpAndSettle();

      expect(find.textContaining('採点確認'), findsNothing);
      expect(find.textContaining('未回答が'), findsNothing);
      expect(find.textContaining('result:'), findsOneWidget);
    });

    testWidgets('full/reviewでは未回答確認シートが出ること（既存挙動の回帰防止）', (tester) async {
      final controller = await _buildController(
        tester,
        questionNos: const [1, 2],
      );
      await tester.pumpWidget(_wrap(QuizScreen(controller: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('採点する'));
      await tester.pumpAndSettle();

      expect(find.textContaining('未回答が2問あります'), findsOneWidget);
      expect(find.textContaining('result:'), findsNothing);
    });
  });
}
