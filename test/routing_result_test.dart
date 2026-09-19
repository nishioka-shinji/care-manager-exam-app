import 'package:care_manager_exam_app/app.dart';
import 'package:care_manager_exam_app/core/models/session.dart';
import 'package:care_manager_exam_app/data/storage_repository.dart';
import 'package:care_manager_exam_app/routes.dart';
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

/// HomeScreen は index.json と exam-*.json を連続で rootBundle.loadString
/// する（プラットフォームチャネル経由の非同期 I/O）。fake async ゾーンのまま
/// では2件目以降が解決しないため runAsync で実時間のイベントループに載せる
/// （quiz_screen_test.dart の _buildController と同じ理由）。
///
/// この runAsync 経由の待機は同一テストファイル内で複数回使うと以降の
/// テストでチャネル応答が解決しなくなる制約があるため、このファイルでは
/// /result 関連の検査意図をすべて1テストに統合し、1回だけ使う
/// （routing_test.dart の同名関数と同じ制約。詳細はそちらの doc コメント）。
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('存在しない sessionId で結果画面を開くとホームへ戻り、'
      '実在する sessionId は結果画面に渡り、'
      'ホーム→履歴→結果から「ホームへ」を押すと端末バック相当でホームに留まる（F2）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _saveSession(tester, 'session-real');
    await _saveSession(tester, 'session-f2');
    await _pumpAppLoaded(tester);

    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );

    // 存在しない sessionId で結果画面を開くとホームへ戻る。
    await tester.runAsync(() async {
      navigator.pushNamed(Routes.result, arguments: 'session-1');
      await tester.pumpAndSettle();
    });
    await tester.pumpAndSettle();
    expect(find.text('本番通し60問を解く'), findsOneWidget);

    // /result に渡した arguments（sessionId）が正しく結線され、そのセッション
    // 由来の画面が出ることを確認する（F3: 常に null を渡す退行があれば
    // notFound 経路に落ちてホームへ戻ってしまい、ここが落ちる）。
    await _pushAndAwaitLoad(
      tester,
      navigator,
      Routes.result,
      arguments: 'session-real',
    );
    await tester.pumpAndSettle();
    expect(find.text('採点結果'), findsOneWidget);
    expect(find.text('本番通し60問を解く'), findsNothing);

    navigator.popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();

    // F2: ホーム→履歴→結果と push した状態で「ホームへ」を押すと、結果画面
    // だけが置換されバックスタックに履歴が残る退行があった。popUntil で
    // ホームまで一括して畳み、端末バック相当（pop）でアプリが終了する
    // （= ホームに留まる）ことを確認する。
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

    expect(find.text('本番通し60問を解く'), findsOneWidget);
    expect(navigator.canPop(), isFalse);
  });
}
