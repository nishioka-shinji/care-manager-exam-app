import 'package:care_manager_exam_app/app.dart';
import 'package:care_manager_exam_app/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [App] 全体（onGenerateRoute・実アセットの ExamRepository を含む）を通した
/// 画面遷移の受け入れ確認。既存の画面単体テストはコントローラ注入や
/// フェイクリポジトリで rootBundle を迂回しているが、ここでは意図的に
/// 迂回せず、本番と同じ経路（各画面が自前で生成する
/// ExamRepository/StorageRepository）で通しの遷移を検査する。
///
/// rootBundle.loadString を含む非同期ロードを testWidgets 内で待つには
/// tester.runAsync が必要だが、同一テストファイル内で複数の testWidgets に
/// 渡って使うと2件目以降でチャネル応答が解決しなくなる制約がある
/// （routing_test.dart / routing_result_test.dart の doc コメント参照）。
/// そのため、App 全体を pump する検査はこのファイルでは1つの testWidgets に
/// 統合し、その内部で runAsync を繰り返し呼ぶ（_pumpAppLoaded 実装と同じ
/// 「1テスト内で複数回」は問題なく、複数テストに分割したときにだけ壊れる）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// index.json / exam-*.json の rootBundle.loadString が終わるまで、
  /// 実時間のイベントループに載せながらスピナー消失を待つ
  /// （routing_test.dart の _pumpAppLoaded と同じ理由・同じ実装）。
  Future<void> pumpUntilLoaded(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
  }

  /// ConfirmSheet の確定ボタンなど、押した先で非同期I/Oが走る操作を
  /// 実時間で進めてから pump し直す（routing_result_test.dart の
  /// _pushAndAwaitLoad と同じ理由）。
  Future<void> tapAndAwaitIo(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await pumpUntilLoaded(tester);
  }

  /// ホーム/履歴の得点表示（'{total} / {max}' 形式）にマッチするテキストを
  /// 探す。本番通し(60問)と復習(部分出題)では max が異なるため、
  /// 固定の分母文字列ではなく正規表現で拾う。
  Finder scoreLineFinder() => find.byWidgetPredicate(
    (widget) =>
        widget is Text && RegExp(r'^\d+ / \d+$').hasMatch(widget.data ?? ''),
  );

  testWidgets('current が無い状態での /quiz 強制送還、'
      'ホーム↔演習↔結果↔履歴の全遷移経路、'
      '本番通し→復習→履歴2件までの一気通貫シナリオが動く', (tester) async {
    await tester.pumpWidget(App(appState: AppState()));
    await pumpUntilLoaded(tester);

    NavigatorState navigator() =>
        tester.state<NavigatorState>(find.byType(Navigator).first);

    // ---- current が無い状態で /quiz を開くとホームへ強制送還される ----
    navigator().pushNamed(Routes.quiz);
    await pumpUntilLoaded(tester);
    expect(find.text('本番通し60問を解く'), findsOneWidget);

    // ---- ホーム → 履歴（履歴0件の空状態、ホームへ戻るボタン） ----
    navigator().pushNamed(Routes.history);
    await tester.pumpAndSettle();
    expect(find.text('受験履歴'), findsOneWidget);
    expect(find.textContaining('まだ受験履歴がありません'), findsOneWidget);

    await tester.tap(find.text('ホームへ'));
    await tester.pumpAndSettle();
    expect(find.text('本番通し60問を解く'), findsOneWidget);

    // ---- ホーム → 演習（本番通し） ----
    await tester.tap(find.text('本番通し60問を解く'));
    await pumpUntilLoaded(tester);
    expect(find.text('本番通し'), findsWidgets);

    // 1番は selectCount=2・正解[3,4]。あえて[1,2]を選び不正解にする。
    expect(find.text('1 / 60'), findsOneWidget);
    await tester.tap(find.text('1').first);
    await tester.pump();
    await tester.tap(find.text('2').first);
    await tester.pump();

    // 2番へ進み selectCount=3・正解[1,2,3]を選んで正解させる。
    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 60'), findsOneWidget);
    await tester.tap(find.text('1').first);
    await tester.pump();
    await tester.tap(find.text('2').first);
    await tester.pump();
    await tester.tap(find.text('3').first);
    await tester.pump();

    // ---- ホーム → 演習（中断セッションからの再開） ----
    // 採点前にいったんホームへ戻り、再開カードから同じ演習へ戻れることを見る。
    navigator().popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    expect(find.text('前回の続きがあります'), findsOneWidget);
    // didPopNext による再読み込みで、直前に「次へ」で進めた cursor(2番=index1)
    // が最新の値として反映される（修正前は既存 HomeController が再読み込み
    // されず、演習開始時点の cursor=0 のまま止まっていた）。
    expect(find.textContaining('本番通し・2 / 60 問目まで進行中'), findsOneWidget);

    await tester.tap(find.textContaining('前回の続きから再開'));
    await pumpUntilLoaded(tester);
    // cursor は保存時点（2番=index1）まで戻る。
    expect(find.text('2 / 60'), findsOneWidget);
    expect(find.text('3 / 3 選択中'), findsOneWidget);

    // ---- 演習 → 結果（未回答58問を残したまま採点確定） ----
    await tester.tap(find.text('採点する'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未回答が58問あります'), findsOneWidget);
    await tapAndAwaitIo(tester, find.text('採点する').last);
    expect(find.text('採点結果'), findsOneWidget);

    // ---- 結果画面で得点を確認する ----
    // 1番不正解・2番正解・3〜60番未回答（すべて不正解扱い）で1/60のはず。
    final scoreTexts = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .where((t) => t.contains('/'));
    expect(scoreTexts, contains('1 / 60'));

    // ---- 結果 → 演習（間違えた問題だけ復習） ----
    expect(find.textContaining('間違えた問題だけ復習する'), findsOneWidget);
    await tapAndAwaitIo(tester, find.textContaining('間違えた問題だけ復習する'));
    await pumpUntilLoaded(tester);
    expect(find.text('復習モード'), findsWidgets);
    expect(find.text('1 / 59'), findsOneWidget);

    // 復習1問目（元の1番）は selectCount=2・正解[3,4]。今度は正しく選ぶ。
    await tester.tap(find.text('3').first);
    await tester.pump();
    await tester.tap(find.text('4').first);
    await tester.pump();

    // ---- 演習（復習） → 結果（採点確定） ----
    await tester.tap(find.text('採点する'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未回答が58問あります'), findsOneWidget);
    await tapAndAwaitIo(tester, find.text('採点する').last);
    expect(find.text('採点結果'), findsOneWidget);

    // ---- 結果 → ホーム ----
    // ResultScreen の「ホームへ」は popUntil(isFirst) でスタック最下段の
    // 既存 HomeScreen インスタンスへ戻るが、RouteAware の didPopNext で
    // HomeController.load() が再実行され、直近履歴が最新化される。
    await tester.tap(find.text('ホームへ'));
    await tester.pumpAndSettle();
    expect(find.text('本番通し60問を解く'), findsOneWidget);

    // 採点した誤答が cme:stats に反映され、復習ボタンの件数に出る。
    // ここを見ないと gradeAndFinish が正誤を取り違えても気づけない。
    expect(find.textContaining('間違えた問題を復習（'), findsOneWidget);
    expect(find.text('間違えた問題を復習（0問）'), findsNothing);

    // ---- ホーム → 結果（直近履歴のタップ） ----
    // 本番通し(1/60)・復習(1/59)の2件が「直近の受験履歴」に出るはず。
    expect(find.text('直近の受験履歴'), findsOneWidget);
    expect(scoreLineFinder(), findsNWidgets(2));

    await tester.ensureVisible(scoreLineFinder().first);
    await tester.pumpAndSettle();
    await tapAndAwaitIo(tester, scoreLineFinder().first);
    expect(find.text('採点結果'), findsOneWidget);
    navigator().popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();

    // ---- ホーム → 履歴（履歴に2件残っている） ----
    await tester.ensureVisible(find.text('履歴をすべて見る'));
    await tester.pumpAndSettle();
    await tapAndAwaitIo(tester, find.text('履歴をすべて見る'));
    expect(find.text('受験履歴'), findsOneWidget);
    expect(find.textContaining('まだ受験履歴がありません'), findsNothing);
    expect(scoreLineFinder(), findsNWidgets(2));

    // ---- 履歴 → 結果 ----
    await tester.ensureVisible(scoreLineFinder().first);
    await tester.pumpAndSettle();
    await tapAndAwaitIo(tester, scoreLineFinder().first);
    expect(find.text('採点結果'), findsOneWidget);
  });
}
