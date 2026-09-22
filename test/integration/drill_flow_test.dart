import 'package:care_manager_exam_app/app.dart';
import 'package:care_manager_exam_app/data/storage_repository.dart';
import 'package:care_manager_exam_app/features/quiz/widgets/choice_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [App] 全体を通した一問一答（drill）モードの画面をまたぐ通し確認。
/// full_flow_test.dart と同じ理由でフェイクリポジトリを使わず本番と同じ
/// 経路（rootBundle 経由の実アセット）で検証する（CLAUDE.md: テスト側に
/// 本番のルーティング構造を書き写さない）。App 全体を pump するテストは
/// 1ファイルに1件までのため full_flow_test.dart とは別ファイルにする。
///
/// exam-28.json 1番は selectCount=2・answers=[3,4]、2番は selectCount=3・
/// answers=[1,2,3]。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// index.json / exam-*.json の rootBundle.loadString が終わるまで待つ
  /// （full_flow_test.dart の同名関数と同じ実装）。
  Future<void> pumpUntilLoaded(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  /// 押した先で非同期I/Oが走る操作を実時間で進めてから pump し直す
  /// （full_flow_test.dart の同名関数と同じ実装）。
  Future<void> tapAndAwaitIo(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }

  /// 選択肢番号 [no] の [ChoiceTile] をタップする。既定のテスト画面
  /// (800x600) では選択肢が下部固定バーの裏に隠れて座標が画面外になる
  /// ことがあるため、ensureVisible でスクロールしてからタップする。
  /// 問番号グリッドの数字とも衝突しないよう ChoiceTile 自体で絞り込む。
  Future<void> tapChoice(WidgetTester tester, int no) async {
    final finder = find.byWidgetPredicate(
      (widget) => widget is ChoiceTile && widget.no == no,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('ホーム→一問一答で2問答え合わせ→結果(部分採点)→ホームの復習件数に反映される', (tester) async {
    await tester.pumpWidget(App(appState: AppState()));
    await pumpUntilLoaded(tester);

    // ---- ホーム → 一問一答で解く ----
    await tester.tap(find.text('一問一答で解く'));
    await pumpUntilLoaded(tester);
    expect(find.text('1 / 60'), findsOneWidget);

    // ---- 1問目: 答え合わせ（正解を選ぶ） ----
    await tapChoice(tester, 3);
    await tapChoice(tester, 4);
    await tester.tap(find.text('答え合わせ'));
    await tester.pump();

    expect(find.textContaining('正解は 3・4'), findsOneWidget);

    // ---- 次の問題へ ----
    await tester.tap(find.text('次の問題へ'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 60'), findsOneWidget);

    // ---- 2問目: 答え合わせ（不正解を選ぶ。正解は[1,2,3]） ----
    await tapChoice(tester, 1);
    await tapChoice(tester, 2);
    await tapChoice(tester, 4);
    await tester.tap(find.text('答え合わせ'));
    await tester.pump();

    expect(find.textContaining('正解は 1・2・3'), findsOneWidget);

    // ---- 回答状況シートから「ここまでの結果を見る」 ----
    await tester.ensureVisible(find.text('回答状況'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回答状況'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ここまでの結果を見る'));
    await tester.pumpAndSettle();
    await tapAndAwaitIo(tester, find.text('ここまでの結果を見る'));

    // ---- 結果画面: モードラベルが一問一答、母数は答え合わせ件数(2) ----
    expect(find.text('採点結果'), findsOneWidget);
    expect(find.text('一問一答'), findsOneWidget);

    final scoreTexts = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .where((t) => t.contains('/'));
    expect(scoreTexts, contains('1 / 2'));

    // 不変条件1: 得点と正答率のみで、合否判定のラベルは出さない。
    expect(find.text('総合得点（合否判定は行いません）'), findsOneWidget);
    expect(find.textContaining('ここでは合否判定を行いません'), findsOneWidget);

    // ---- 結果 → ホーム ----
    // RouteAware の didPopNext で HomeController.load() が再実行され、
    // 復習件数が最新化される（full_flow_test.dart と同じ経路）。
    await tester.tap(find.text('ホームへ'));
    await tester.pumpAndSettle();
    expect(find.text('本番通し60問を解く'), findsOneWidget);

    // 二重計上しないこと: 答え合わせ時の記録(2問目の不正解1件)だけが
    // 反映され、finishDrill の再送信では増えない。
    expect(find.text('間違えた問題を復習（1問）'), findsOneWidget);

    // 二重計上しないこと（cme:stats）: 答え合わせのたびに1回だけ記録され、
    // finishDrill の再送信（applyStats: false）では増えない。
    final storage = StorageRepository();
    await storage.init();
    final stats = storage.loadStats('28');
    expect(stats['1']?.attempts, 1);
    expect(stats['2']?.attempts, 1);
  });
}
