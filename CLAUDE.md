# CLAUDE.md

ケアマネ試験（介護支援専門員 実務研修受講試験）の過去問演習アプリ。Flutter 製。
Web 版 `~/develop/care-manager-exam` のデザインと挙動を踏襲して Dart で書き直したもので、
コードは一切共有しない（WebView ではない）。

## 検証コマンド

このリポジトリで実行する検証は以下を唯一の情報源とする。サブエージェントは自前で組み立てない。
`flutter` はグローバル版が未設定のため、必ず `mise exec --` を前置する。

| 目的 | コマンド | 合格条件 |
|---|---|---|
| 静的解析 | `mise exec -- flutter analyze` | `No issues found!` |
| フォーマット | `mise exec -- dart format --output=none --set-exit-if-changed .` | 終了コード 0 |
| テスト | `mise exec -- flutter test` | 全件 pass |
| Android ビルド | `mise exec -- flutter build apk --debug` | 成功 |
| 環境確認 | `mise exec -- flutter doctor -v` | Android toolchain が緑 |

### macOS ビルドは現在スキップする

`mise exec -- flutter build macos --debug` は Xcode 未導入（Command Line Tools のみ）のため
実行できない。macOS 対応は Android 完走後の独立タスクとして扱い、それまで合格条件に含めない。
macOS で動作確認済みと報告しないこと。

## 不変条件

移植元が意図して選んだ仕様。推測で変えない。

1. **採点に合否判定を入れない。** 得点と正答率のみ表示する。合格基準は年度ごとに補正されるため
   移植元も判定を持たない。結果画面の 70% は参考ラインの描画のみ。
2. **演習画面の選択肢タップで設問ウィジェットを作り直さない。** スクロール位置が飛ぶ。
   選択状態だけを購読する単位に `setState` の範囲を絞る。設問切替時のみ作り直して先頭へ戻す。
3. **永続化キーは `cme:` プレフィックス。** `cme:v` / `cme:sessions` / `cme:stats` / `cme:current`。

## 依存方針

依存は `shared_preferences` のみ。状態管理は `ChangeNotifier`、ルーティングは素の `Navigator` で足りる。
go_router / provider / riverpod / コード生成系は追加しない。
出典クレジットはテキスト表示のみとし、外部ブラウザ起動（url_launcher）は行わない。

## 出典

問題・解説は `assets/data/exam-*.json` に含まれる `source` / `credit` を参照。
解説文の著作権は学校法人 藤仁館学園にある。学習目的で公開しているが、
権利者からの申し出があれば速やかに公開を停止する。

## 日報

保存先は `docs/daily-reports/YYYYMM/YYYYMMDD.md`。

## 移植元

Web 版は `~/develop/care-manager-exam`（GitHub: nishioka-shinji/care-manager-exam）。
**移植元を読む前に `git fetch` して origin/main と比べること。**
ローカルが遅れたまま移植を進め、全 16 年度のデータと一問一答モードを
取りこぼした事故がある。

## テストの書き方

### 回帰を検出できることを実測で確かめる

テストが通ることと、回帰を検出できることは別。実装後に本番コードを壊して
テストが実際に落ちることを確認する。このリポジトリでは「全件 pass するが
本番を壊しても落ちない」テストが 4 回見つかっている。

テスト側に本番と同じ構造を書き写さない。本番だけが壊れたときに追随せず、
検出力が見かけだけになる（`AppShell` を公開して共有しているのはこのため）。

### rootBundle を使う非同期ロード

`testWidgets` 内で待つには `tester.runAsync` が要るが、同一ファイル内で
複数回使うと 2 件目以降でチャネル応答が解決しなくなる。リポジトリを
フェイクに差し替えて `rootBundle` を迂回する（`test/home_screen_test.dart`）。
`App` 全体を pump するテストは 1 ファイルに 1 件までにする。

### 下部固定バーのあるレイアウト

高さの上限を持たない書き方（`ConstrainedBox(minHeight:)` など）をすると、
`Scaffold` の緩い制約が `AppButton` 内の `Align` まで伝播し、ボタンが
画面全高のタップ領域になって本文が操作できなくなる。高さは必ず締める。

safe-area は `viewPadding.bottom` と `padding.bottom` の大きい方を使う。
Android 15 以降の全画面表示では 3 ボタン操作のとき前者が 0 を返すことがある。
