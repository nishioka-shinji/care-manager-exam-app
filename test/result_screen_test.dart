import 'package:care_manager_exam_app/core/models/session.dart';
import 'package:care_manager_exam_app/data/exam_repository.dart';
import 'package:care_manager_exam_app/data/storage_repository.dart';
import 'package:care_manager_exam_app/features/result/result_controller.dart';
import 'package:care_manager_exam_app/features/result/result_screen.dart';
import 'package:care_manager_exam_app/features/result/widgets/result_grid.dart';
import 'package:care_manager_exam_app/theme/app_theme.dart';
import 'package:care_manager_exam_app/theme/app_tokens.dart';
import 'package:care_manager_exam_app/widgets/app_button.dart';
import 'package:care_manager_exam_app/widgets/footer_credit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// exam-28.json 1番（careセクション）は answers=[3,4]。26番（health_welfareセクション）
// は answers=[1,2,3]。正解/不正解/未回答を1本のセッションで揃えて検証するために使う。
const _examId = '28';

// QuizController.load() と同様、ResultController.load() は
// rootBundle.loadString を含むため tester.runAsync で実時間に載せる必要がある。
Future<ResultController> _buildController(
  WidgetTester tester, {
  required String sessionId,
  required Map<int, List<int>> answers,
  Score? savedScore,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageRepository();
  await tester.runAsync(() async {
    await storage.init();
    await storage.saveSession(
      Session(
        id: sessionId,
        examId: _examId,
        mode: QuizMode.full,
        startedAt: '2026-09-19T00:00:00.000Z',
        finishedAt: '2026-09-19T00:30:00.000Z',
        answers: answers,
        // 保存値は再採点で無視されるはずの値。矛盾させて渡せるようにする。
        score: savedScore ?? const Score(total: 0, max: 0, bySection: {}),
      ),
    );
  });
  final controller = ResultController(
    examRepository: ExamRepository(),
    storageRepository: storage,
    sessionId: sessionId,
  );
  await tester.runAsync(() => controller.load());
  return controller;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    initialRoute: '/result',
    onGenerateRoute: (settings) {
      if (settings.name == '/result') {
        return MaterialPageRoute(builder: (_) => child);
      }
      if (settings.name == '/') {
        return MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('home')),
        );
      }
      if (settings.name == '/quiz') {
        return MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('quiz')),
        );
      }
      return null;
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('セッションが見つからないときホームへ遷移する', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageRepository();
    await storage.init();
    final controller = ResultController(
      examRepository: ExamRepository(),
      storageRepository: storage,
      sessionId: 'missing',
    );

    await tester.pumpWidget(_wrap(ResultScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('保存済み score が answers と矛盾していても answers から再採点した値が表示される', (
    tester,
  ) async {
    // 保存された score は 0/0 だが、実際の answers は1問中1問正解。
    // 画面には再採点した total=1・max=1 が出るはず（保存値の 0/0 ではない）。
    final controller = await _buildController(
      tester,
      sessionId: 's1',
      answers: const {
        1: [3, 4], // 正解
      },
      savedScore: const Score(total: 0, max: 0, bySection: {}),
    );

    expect(controller.gradeResult!.score.total, 1);
    expect(controller.gradeResult!.score.max, 1);

    await tester.pumpWidget(_wrap(ResultScreen(controller: controller)));
    await tester.pumpAndSettle();

    final richText = tester
        .widgetList<RichText>(find.byType(RichText))
        .where((w) => w.text.toPlainText().contains('/'));
    expect(richText.map((w) => w.text.toPlainText()), contains('1 / 1'));
  });

  testWidgets('分野別バーに70%のターゲット線が描かれ、合否判定の文字列が出ない', (tester) async {
    final controller = await _buildController(
      tester,
      sessionId: 's2',
      answers: const {
        1: [3, 4], // care 正解
        26: [1, 2, 3], // health_welfare 正解
      },
    );

    await tester.pumpWidget(_wrap(ResultScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('分野別の得点'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    // 合否判定なしの注記自体には「合格」「判定」という語が含まれるが、
    // それは移植元 result.js:165 の踏襲文言であり判定表示ではない。
    // 独立した「合格」「不合格」の判定ラベル（バッジ等）が出ないことを確認する。
    expect(find.text('合格'), findsNothing);
    expect(find.text('不合格'), findsNothing);
    expect(
      find.textContaining(
        '点線は参考ライン（70%）です。合格基準は年度ごとに補正されるため、'
        'ここでは合否判定を行いません。',
      ),
      findsOneWidget,
    );
  });

  testWidgets('正誤一覧グリッドが正解/不正解/未回答で色分けされる', (tester) async {
    // viewport 360px は移植元の6列ブレークポイント(380px)未満のため5列になる。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);

    // questionNos は session.answers のキーから決まるため、60問全問の
    // 正誤をグリッドに出すには全問キーを埋める必要がある(3問だけだと
    // グリッドが3セルしか無くレイアウト検証にならない)。
    final fullAnswers = <int, List<int>>{
      for (var no = 3; no <= 60; no++) no: const <int>[],
    };
    final controller = await _buildController(
      tester,
      sessionId: 's3',
      answers: {
        1: const [3, 4], // 正解
        2: const [1, 2, 4], // 不正解（正解は1,2,3）
        ...fullAnswers, // 3〜60は未回答
      },
    );

    await tester.pumpWidget(_wrap(ResultScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('正誤一覧'), findsOneWidget);
    expect(controller.gradeResult!.results.length, 60);

    bool hasSemanticsLabel(String label) {
      return tester
          .widgetList<Semantics>(find.byType(Semantics))
          .any((w) => (w.properties.label ?? '').contains(label));
    }

    expect(hasSemanticsLabel('問1（正解）'), isTrue);
    expect(hasSemanticsLabel('問2（不正解）'), isTrue);
    expect(hasSemanticsLabel('問3（未回答）'), isTrue);

    // グリッド先頭が画面外の場合があるため、先頭セル(問1)を可視範囲に入れる。
    await tester.ensureVisible(find.byType(ResultGrid));
    await tester.pumpAndSettle();

    // レイアウト: セルの矩形を集めて top が同一のものを数えて列数を出す(F5)。
    final cellRects = tester
        .widgetList<InkWell>(
          find.descendant(
            of: find.byType(ResultGrid),
            matching: find.byType(InkWell),
          ),
        )
        .map((w) => tester.getRect(find.byWidget(w)))
        .toList();
    expect(cellRects, isNotEmpty);
    final firstRowTop = cellRects
        .map((r) => r.top)
        .reduce((a, b) => a < b ? a : b);
    final firstRowCount = cellRects.where((r) => r.top == firstRowTop).length;
    expect(firstRowCount, 5);
    for (final rect in cellRects) {
      expect(rect.height, greaterThanOrEqualTo(44));
      expect(rect.width, greaterThanOrEqualTo(44));
    }

    // 色: 正解=緑(tokens.ok)、不正解=赤(tokens.ng)、未回答=グレー(tokens.none)。
    // 演習画面の回答済み(accent=青)と混同していないことを確認する(F7)。
    Color materialColorOf(String semanticsLabelSubstring) {
      final semantics = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .firstWhere(
            (w) => (w.properties.label ?? '').contains(semanticsLabelSubstring),
          );
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byWidget(semantics),
          matching: find.byType(Material),
        ),
      );
      return material.color!;
    }

    final theme = AppTheme.light;
    final tokens = theme.extension<AppTokens>()!;
    expect(materialColorOf('問1（正解）'), tokens.ok);
    expect(materialColorOf('問2（不正解）'), tokens.ng);
    expect(materialColorOf('問3（未回答）'), tokens.none);
  });

  testWidgets('正誤一覧グリッドの列数がviewport幅380pxを境に5列/6列に切り替わる', (tester) async {
    // F6: LayoutBuilder の内側幅ではなく viewport 幅で境界を判定する。
    Future<int> columnsAt(double width) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = Size(width, 900);
      final fullAnswers = <int, List<int>>{
        for (var no = 1; no <= 60; no++) no: const <int>[],
      };
      final controller = await _buildController(
        tester,
        sessionId: 'w${width.toInt()}',
        answers: fullAnswers,
      );
      await tester.pumpWidget(_wrap(ResultScreen(controller: controller)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(ResultGrid));
      await tester.pumpAndSettle();

      final cellRects = tester
          .widgetList<InkWell>(
            find.descendant(
              of: find.byType(ResultGrid),
              matching: find.byType(InkWell),
            ),
          )
          .map((w) => tester.getRect(find.byWidget(w)))
          .toList();
      final firstRowTop = cellRects
          .map((r) => r.top)
          .reduce((a, b) => a < b ? a : b);
      return cellRects.where((r) => r.top == firstRowTop).length;
    }

    expect(await columnsAt(379), 5);
    tester.view.reset();
    expect(await columnsAt(380), 6);
    tester.view.reset();
  });

  testWidgets('グリッドのタップで該当問の解説までスクロールする', (tester) async {
    final controller = await _buildController(
      tester,
      sessionId: 's4',
      answers: const {
        1: [3, 4],
        26: [1, 2, 3],
      },
    );

    await tester.pumpWidget(_wrap(ResultScreen(controller: controller)));
    await tester.pumpAndSettle();

    // 問26の解説はスクロール前は下方にあり、ビューポート外にある。
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final explanationBefore = tester.getRect(find.text('問26'));
    expect(
      explanationBefore.bottom,
      greaterThan(scrollable.position.viewportDimension),
    );

    // グリッドのセル自体はテスト用の小さいビューポートでは画面外にある場合が
    // あるため、タップ前に ensureVisible でスクロールしてから押す。
    final gridCell26 = find.descendant(
      of: find.byType(ResultGrid),
      matching: find.text('26'),
    );
    await tester.ensureVisible(gridCell26);
    await tester.pumpAndSettle();
    await tester.tap(gridCell26);
    await tester.pumpAndSettle();

    // Scrollable.ensureVisible が効き、問26の解説見出しがビューポート内に来る。
    final explanationAfter = tester.getRect(find.text('問26'));
    expect(explanationAfter.top, greaterThanOrEqualTo(0));
    expect(
      explanationAfter.top,
      lessThanOrEqualTo(scrollable.position.viewportDimension),
    );
  });

  testWidgets('解説に正解とあなたの回答のマークが出る', (tester) async {
    final controller = await _buildController(
      tester,
      sessionId: 's5',
      answers: const {
        1: [1, 2], // 不正解。正解は3,4。
      },
    );

    await tester.pumpWidget(_wrap(ResultScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('正解'), findsWidgets);
    expect(find.text('あなたの回答'), findsWidgets);
  });

  testWidgets('出典が媒体名のみのテキストとして表示され、リンクになっていない', (tester) async {
    final controller = await _buildController(
      tester,
      sessionId: 's6',
      answers: const {
        1: [3, 4],
      },
    );

    await tester.pumpWidget(_wrap(ResultScreen(controller: controller)));
    await tester.pumpAndSettle();

    // T7 の年度カードと同じ方針（媒体名のみ、URL なし）に揃える。
    expect(
      find.textContaining('https://www.care-news.jp/kakomon/28/all_test.html'),
      findsNothing,
    );
    expect(find.textContaining(kExamSourceMediaName), findsWidgets);
    expect(find.textContaining('学校法人 藤仁館学園'), findsWidgets);
    // タップ可能なリンク要素（GestureDetector/InkWell）が出典のテキストに
    // 紐付いていないこと。出典テキストの祖先を辿って InkWell が無いことを確認する。
    final sourceText = find.textContaining(kExamSourceMediaName);
    final ancestorInkWells = find.ancestor(
      of: sourceText,
      matching: find.byType(InkWell),
    );
    expect(ancestorInkWells, findsNothing);
  });

  testWidgets('間違えた問題が0件のとき復習ボタンがdisabledでラベルが変わる', (tester) async {
    final controller = await _buildController(
      tester,
      sessionId: 's7',
      answers: const {
        1: [3, 4], // 正解のみ
      },
    );

    await tester.pumpWidget(_wrap(ResultScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('間違えた問題はありません'), findsOneWidget);

    await tester.tap(find.text('間違えた問題はありません'));
    await tester.pumpAndSettle();

    // disabled のため画面は変わらない。
    expect(find.text('間違えた問題はありません'), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('復習ボタンを押すと間違えた問番号の昇順でcurrentが作られ/quizへ遷移する', (tester) async {
    final controller = await _buildController(
      tester,
      sessionId: 's8',
      answers: const {
        26: <int>[], // 未回答（不正解扱い）
        1: [1, 2], // 不正解（正解は3,4）
        2: [1, 2, 3], // 正解
      },
    );

    await tester.pumpWidget(_wrap(ResultScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('間違えた問題だけ復習する（2問）'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('間違えた問題だけ復習する（2問）'));
    });
    await tester.pumpAndSettle();

    expect(find.text('quiz'), findsOneWidget);

    final storage = StorageRepository();
    await storage.init();
    final current = await storage.loadCurrent();
    expect(current, isNotNull);
    expect(current!.mode, QuizMode.review);
    expect(current.questionNos, [1, 26]);
    expect(current.cursor, 0);
    expect(current.answers, isEmpty);
  });

  testWidgets('FooterCreditが下部バーに隠れない', (tester) async {
    final controller = await _buildController(
      tester,
      sessionId: 's9',
      answers: const {
        1: [3, 4],
      },
    );

    await tester.pumpWidget(_wrap(ResultScreen(controller: controller)));
    await tester.pumpAndSettle();

    // 末尾までスクロールしてフッタを可視範囲に入れてから比較する。
    // 解説カード側にも出典テキストが出るため、FooterCredit ウィジェット自体で
    // 一意に絞る。
    await tester.ensureVisible(find.byType(FooterCredit));
    await tester.pumpAndSettle();

    final footerRect = tester.getRect(find.byType(FooterCredit));
    final bottomBarRect = tester.getRect(find.text('ホームへ'));

    // フッタの下端は下部バーの上端より上にある（重ならない）。
    expect(footerRect.bottom, lessThanOrEqualTo(bottomBarRect.top + 1));
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
      sessionId: 's10',
      answers: const {
        1: [3, 4],
      },
    );

    await tester.pumpWidget(_wrap(ResultScreen(controller: controller)));
    await tester.pumpAndSettle();

    final buttonRect = tester.getRect(find.text('ホームへ'));

    // ボタンの下端がナビゲーションバーの上端より上にあること。
    expect(buttonRect.bottom, lessThanOrEqualTo(800 - navBarHeight));

    // タップが実際に届くこと（ナビゲーションバーに吸われていない）。
    await tester.tap(find.text('ホームへ'));
    await tester.pumpAndSettle();
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

    final controller = await _buildController(
      tester,
      sessionId: 's10',
      answers: const {
        1: [3, 4],
      },
    );

    await tester.pumpWidget(_wrap(ResultScreen(controller: controller)));
    await tester.pumpAndSettle();

    final button = tester.getRect(find.byType(AppButton).first);
    expect(button.bottom, lessThanOrEqualTo(800 - navBar));
    expect(button.height, lessThan(80));

    await tester.tap(find.text('ホームへ'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('間違えた問題が多いときもボタンのラベルが省略されず全文表示される', (tester) async {
    // 実機で「間違えた問題だけ復習する（60問）」が「間違えた問題だけ復」で
    // 切れていた。全問不正解にして長いラベルを再現する。画面幅を Pixel 8
    // 相当に固定し、ボタン幅がラベルより確実に狭くなる条件を作る。
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);

    final controller = await _buildController(
      tester,
      sessionId: 's_wrong_all',
      answers: {for (var i = 1; i <= 60; i++) i: <int>[]},
    );

    await tester.pumpWidget(_wrap(ResultScreen(controller: controller)));
    await tester.pumpAndSettle();

    // ラベルの Text ウィジェットが省略されず全文を保持していること。
    final labelFinder = find.text('間違えた問題だけ復習する（60問）');
    expect(labelFinder, findsOneWidget);

    // 折り返し高さが確保できない固定高さの下部バーでも文字が欠けないよう、
    // 収まらない分は縮小されている（FittedBox で 1 行に収める）こと。
    final buttonFinder = find.byType(AppButton).last;
    expect(
      find.descendant(of: buttonFinder, matching: find.byType(FittedBox)),
      findsOneWidget,
    );

    // ラベルの本来の描画幅がボタンの表示幅を超えている（＝縮小が必要な
    // 長さである）ことを前提として、実際の描画矩形がボタン内に収まって
    // クリップされていないことを確認する。
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '間違えた問題だけ復習する（60問）',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final buttonRect = tester.getRect(buttonFinder);
    expect(
      textPainter.width,
      greaterThan(buttonRect.width),
      reason: 'このテストは縮小が必要なほど長いラベルを前提にしている',
    );

    final labelRect = tester.getRect(labelFinder);
    expect(buttonRect.left, lessThanOrEqualTo(labelRect.left + 0.5));
    expect(buttonRect.right, greaterThanOrEqualTo(labelRect.right - 0.5));
  });
}
