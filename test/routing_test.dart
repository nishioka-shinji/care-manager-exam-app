import 'dart:async';

import 'package:care_manager_exam_app/app.dart';
import 'package:care_manager_exam_app/core/models/session.dart';
import 'package:care_manager_exam_app/data/storage_repository.dart';
import 'package:care_manager_exam_app/routes.dart';
import 'package:care_manager_exam_app/theme/app_theme.dart';
import 'package:care_manager_exam_app/widgets/app_toast.dart';
import 'package:care_manager_exam_app/widgets/confirm_sheet.dart';
import 'package:care_manager_exam_app/widgets/footer_credit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// exam-28.json 1番（careセクション）は answers=[3,4]（正解）。
// /result への arguments 結線テストで実在セッションとして使う。
const _examId = '28';

// ResultScreen は initState から ResultController.load()（rootBundle.loadString
// を含む）を自前で呼ぶため、pump だけでは完了を待てない。実時間の delay を
// 挟んで IO を進めてから pump し直す。
Future<void> _pushAndAwaitLoad(
  WidgetTester tester,
  NavigatorState navigator,
  String routeName, {
  Object? arguments,
}) async {
  await tester.runAsync(() async {
    navigator.pushNamed(routeName, arguments: arguments);
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  });
}

Future<void> _saveSession(WidgetTester tester, String sessionId) async {
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
        answers: const {
          1: [3, 4],
        },
        score: const Score(total: 0, max: 0, bySection: {}),
      ),
    );
  });
}

/// レビュー実測条件（400x800・safe-area bottom 34）を再現する。
void _setViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 800);
  tester.view.padding = const FakeViewPadding(bottom: 34);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('ホームから履歴へ push でき、戻ると元の画面に戻る', (tester) async {
    await tester.pumpWidget(App(appState: AppState()));

    expect(find.text('ホーム 画面（プレースホルダ）'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );

    navigator.pushNamed(Routes.history);
    await tester.pumpAndSettle();
    expect(find.text('履歴 画面（プレースホルダ）'), findsOneWidget);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('ホーム 画面（プレースホルダ）'), findsOneWidget);
  });

  // /result は T8 で本実装済み（ResultScreen）。存在しない sessionId で開くと
  // ホームへ pushReplacement することを routing の結線として確認する
  // （画面内部の詳細な振る舞いは test/result_screen_test.dart が持つ）。
  testWidgets('存在しない sessionId で結果画面を開くとホームへ戻る', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(App(appState: AppState()));

    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );

    await tester.runAsync(() async {
      navigator.pushNamed(Routes.result, arguments: 'session-1');
      await tester.pumpAndSettle();
    });
    await tester.pumpAndSettle();

    expect(find.text('ホーム 画面（プレースホルダ）'), findsOneWidget);
  });

  // /result に渡した arguments（sessionId）が正しく結線され、そのセッション
  // 由来の画面が出ることを確認する（F3: 常に null を渡す退行があれば
  // notFound 経路に落ちてホームへ戻ってしまい、このテストが落ちる）。
  testWidgets('実在する sessionId が arguments として結果画面に渡る', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _saveSession(tester, 'session-real');
    await tester.pumpWidget(App(appState: AppState()));

    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );

    await _pushAndAwaitLoad(
      tester,
      navigator,
      Routes.result,
      arguments: 'session-real',
    );
    await tester.pumpAndSettle();

    expect(find.text('採点結果'), findsOneWidget);
    expect(find.text('ホーム 画面（プレースホルダ）'), findsNothing);
  });

  // F2: ホーム→履歴→結果と push した状態で「ホームへ」を押すと、結果画面
  // だけが置換されバックスタックに履歴が残る退行があった。popUntil で
  // ホームまで一括して畳み、端末バック相当（pop）でアプリが終了する
  // （= ホームに留まる）ことを確認する。
  testWidgets('ホーム→履歴→結果から「ホームへ」を押すと端末バック相当でホームに留まる（F2）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _saveSession(tester, 'session-f2');
    await tester.pumpWidget(App(appState: AppState()));

    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );

    navigator.pushNamed(Routes.history);
    await tester.pumpAndSettle();

    await _pushAndAwaitLoad(
      tester,
      navigator,
      Routes.result,
      arguments: 'session-f2',
    );
    await tester.pumpAndSettle();

    expect(find.text('採点結果'), findsOneWidget);

    await tester.tap(find.text('ホームへ'));
    await tester.pumpAndSettle();

    expect(find.text('ホーム 画面（プレースホルダ）'), findsOneWidget);
    expect(navigator.canPop(), isFalse);
  });

  testWidgets('フッタの出典クレジットがスクロール末尾の通常フロー要素として表示される（F4）', (tester) async {
    await tester.pumpWidget(App(appState: AppState()));

    expect(find.textContaining('出典:'), findsOneWidget);
    expect(find.textContaining('学校法人 藤仁館学園'), findsOneWidget);

    // 常時固定のオーバーレイではなく、ListView（本文）の中の通常フロー要素であり、
    // 本文の他の要素（「演習へ」ボタン）より下（末尾）に位置する。
    expect(find.byType(FooterCredit), findsOneWidget);
    final footerTop = tester.getRect(find.byType(FooterCredit)).top;
    final buttonTop = tester.getRect(find.text('演習へ')).top;
    expect(footerTop, greaterThan(buttonTop));
  });

  testWidgets('ConfirmSheet は確定を押すと true を返す', (tester) async {
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await ConfirmSheet.show(
                  context,
                  title: '確認',
                  message: '実行しますか？',
                );
              },
              child: const Text('開く'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();

    expect(find.text('確認'), findsOneWidget);
    expect(find.text('実行しますか？'), findsOneWidget);

    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.text('確認'), findsNothing);
  });

  testWidgets('ConfirmSheet はキャンセルを押すと false を返す', (tester) async {
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await ConfirmSheet.show(
                  context,
                  title: '確認',
                  message: '実行しますか？',
                );
              },
              child: const Text('開く'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.text('確認'), findsNothing);
  });

  testWidgets('Scaffold 配下の MediaQuery.size が画面実寸(400x800)と一致する（F1）', (
    tester,
  ) async {
    _setViewport(tester);
    await tester.pumpWidget(App(appState: AppState()));

    final scaffoldContext = tester.element(find.byType(Scaffold).first);
    final mediaQuerySize = MediaQuery.of(scaffoldContext).size;
    final scaffoldRect = tester.getRect(find.byType(Scaffold).first);

    expect(mediaQuerySize, const Size(400, 800));
    expect(scaffoldRect, const Rect.fromLTRB(0, 0, 400, 800));
    // safe-area bottom はここでのみ計上され、フッタ側で二重に加算されない。
    expect(MediaQuery.of(scaffoldContext).padding.bottom, 34);
  });

  testWidgets('ConfirmSheet のバックドロップとパネルが画面下端(800)まで届く（F2）', (tester) async {
    _setViewport(tester);

    await tester.pumpWidget(App(appState: AppState()));

    unawaited(
      ConfirmSheet.show(
        tester.element(find.byType(Scaffold).first),
        title: '確認',
        message: '実行しますか？',
      ),
    );
    await tester.pumpAndSettle();

    final backdropFinder = find
        .descendant(
          of: find.byType(GestureDetector),
          matching: find.byType(Container),
        )
        .first;
    final backdropRect = tester.getRect(backdropFinder);
    expect(backdropRect.bottom, 800);
    expect(backdropRect.top, 0);

    final panelRect = tester.getRect(
      find.ancestor(of: find.text('確認'), matching: find.byType(Container)).last,
    );
    expect(panelRect.bottom, 800);
  });

  testWidgets('AppToast が画面下端から bar-h(64)+16+safe-area の位置に出る（F2）', (
    tester,
  ) async {
    _setViewport(tester);

    await tester.pumpWidget(App(appState: AppState()));

    AppToast.show(tester.element(find.byType(Scaffold).first), 'メッセージ');
    await tester.pump();

    final toastRect = tester.getRect(find.text('メッセージ'));
    // Positioned の上端は画面下端(800) - (bar-h 64 + 16 + safe-area 34) = 686。
    // テキスト下端はコンテナの縦 padding(10) 分だけ内側に来るので 676 が期待値。
    expect(toastRect.bottom, 676);

    // AppToast 内部の Future.delayed のタイマーを消化してから終える。
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('シェルの下でも下部固定バー（bar-h 64）のボタンがタップできる（F4）', (tester) async {
    _setViewport(tester);

    var tapped = false;
    await tester.pumpWidget(App(appState: AppState()));

    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    // 後続タスクが実装する quiz/result の bottom-bar（bar-h 64）を模す。
    navigator.push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: const SizedBox.shrink(),
          bottomNavigationBar: SizedBox(
            height: 64,
            child: ElevatedButton(
              onPressed: () => tapped = true,
              child: const Text('採点する'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('採点する'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
