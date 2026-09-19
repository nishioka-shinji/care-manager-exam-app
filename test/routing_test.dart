import 'dart:async';

import 'package:care_manager_exam_app/app.dart';
import 'package:care_manager_exam_app/routes.dart';
import 'package:care_manager_exam_app/theme/app_theme.dart';
import 'package:care_manager_exam_app/widgets/app_toast.dart';
import 'package:care_manager_exam_app/widgets/confirm_sheet.dart';
import 'package:care_manager_exam_app/widgets/footer_credit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// レビュー実測条件（400x800・safe-area bottom 34）を再現する。
void _setViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 800);
  tester.view.padding = const FakeViewPadding(bottom: 34);
  addTearDown(tester.view.reset);
}

/// HomeScreen は index.json と exam-*.json を連続で rootBundle.loadString
/// する（プラットフォームチャネル経由の非同期 I/O）。fake async ゾーンのまま
/// では2件目以降が解決しないため runAsync で実時間のイベントループに載せる
/// （quiz_screen_test.dart の _buildController と同じ理由）。
///
/// この runAsync 経由の待機は同一テストファイル内で複数回使うと以降の
/// テストでチャネル応答が解決しなくなる制約があるため、ホームの実データ
/// ロード完了を要するテストは1件に統合し、ここでだけ使う。
Future<void> _pumpAppLoaded(WidgetTester tester) async {
  await tester.pumpWidget(App(appState: AppState()));
  for (var i = 0; i < 20; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pumpAndSettle();
}

/// Scaffold/Overlay の位置だけを検証するテスト向けの最小土台。
/// ホームの中身に依存しないため App を経由しないが、_AppShell が builder に
/// 本番と同じ AppShell を通すことで、シェルの回帰をここで検出できる。
/// ホームを土台にするとスピナーの無限アニメーションで pumpAndSettle が使えない。
Future<void> _pumpMinimalScaffold(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) =>
          AppShell(child: child ?? const SizedBox.shrink()),
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ホームから履歴へ push でき、戻ると元の画面に戻る。'
      'フッタの出典クレジットもスクロール末尾の通常フロー要素として表示される（F4）', (tester) async {
    await _pumpAppLoaded(tester);

    expect(find.text('本番通し60問を解く'), findsOneWidget);
    expect(find.textContaining('学校法人 藤仁館学園'), findsOneWidget);

    // 常時固定のオーバーレイではなく、ListView（本文）の中の通常フロー要素であり、
    // 本文の最終要素（「履歴をすべて見る」ボタン）よりも下（末尾）に位置する。
    expect(find.byType(FooterCredit), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FooterCredit),
        matching: find.textContaining('出典:'),
      ),
      findsOneWidget,
    );
    final footerTop = tester.getRect(find.byType(FooterCredit)).top;
    final lastButtonBottom = tester.getRect(find.text('履歴をすべて見る')).bottom;
    expect(footerTop, greaterThanOrEqualTo(lastButtonBottom));

    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );

    navigator.pushNamed(Routes.history);
    await tester.pumpAndSettle();
    expect(find.text('受験履歴'), findsOneWidget);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('本番通し60問を解く'), findsOneWidget);
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
    await _pumpMinimalScaffold(tester);

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

    await _pumpMinimalScaffold(tester);

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

    await _pumpMinimalScaffold(tester);

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
    await _pumpMinimalScaffold(tester);

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

    // シェルが Navigator を圧縮していると bottomNavigationBar 自体が
    // 画面下端(800)より上に来るため、位置も併せて検証する。
    final barRect = tester.getRect(
      find
          .ancestor(of: find.text('採点する'), matching: find.byType(SizedBox))
          .first,
    );
    expect(barRect.bottom, 800);

    await tester.tap(find.text('採点する'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
