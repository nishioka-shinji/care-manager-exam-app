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
解説文の著作権は学校法人 藤仁館学園にあり、個人利用の範囲に留める。
