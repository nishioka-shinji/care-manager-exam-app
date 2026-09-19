import 'dart:async';

import 'package:care_manager_exam_app/app.dart';
import 'package:care_manager_exam_app/theme/app_theme.dart';
import 'package:care_manager_exam_app/widgets/app_toast.dart';
import 'package:care_manager_exam_app/widgets/confirm_sheet.dart';
import 'package:care_manager_exam_app/widgets/footer_credit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// レビュー実測条件（400x800・safe-area bottom 34）を再現する。
void _setViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 800);
  tester.view.padding = const FakeViewPadding(bottom: 34);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('ホームから演習・結果・履歴へ push でき、戻ると元の画面に戻る', (tester) async {
    await tester.pumpWidget(App(appState: AppState()));

    expect(find.text('ホーム 画面（プレースホルダ）'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );

    navigator.pushNamed(App.routeQuiz);
    await tester.pumpAndSettle();
    expect(find.text('演習 画面（プレースホルダ）'), findsOneWidget);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('ホーム 画面（プレースホルダ）'), findsOneWidget);

    navigator.pushNamed(App.routeResult, arguments: 'session-1');
    await tester.pumpAndSettle();
    expect(find.text('結果 画面（プレースホルダ）'), findsOneWidget);
    expect(find.text('sessionId: session-1'), findsOneWidget);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('ホーム 画面（プレースホルダ）'), findsOneWidget);

    navigator.pushNamed(App.routeHistory);
    await tester.pumpAndSettle();
    expect(find.text('履歴 画面（プレースホルダ）'), findsOneWidget);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('ホーム 画面（プレースホルダ）'), findsOneWidget);
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
