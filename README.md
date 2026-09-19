# ケアマネ過去問（Flutter版）

介護支援専門員（ケアマネージャー）実務研修受講試験に向けた、**個人用の過去問演習アプリ**。
Web 版 `care-manager-exam`（素の HTML/CSS/JavaScript）のデザインと挙動を踏襲し、
Flutter（Dart）で作り直したもの。**コードは Web 版と一切共有していない**
（WebView でラップしたものではない）。

令和7年度（第28回）全60問を対象に、本番通し演習・完全一致方式の採点・分野別得点表示・
間違えた問題だけの復習・受験履歴の記録ができる。

## セットアップ

Flutter のバージョン管理に [mise](https://mise.jdx.dev/) を使う（`mise.toml` で pin 済み）。

```sh
mise install
mise exec -- flutter pub get
```

## 検証コマンド

このリポジトリで実行する検証コマンドとその合格条件は
[`CLAUDE.md`](CLAUDE.md) の表を唯一の情報源とする（ここでは二重管理しない）。

## 対応プラットフォーム

- **Android**: 対応。`mise exec -- flutter build apk --debug` で確認済み。
- **macOS**: プロジェクト構成（`macos/` ディレクトリ）はあるが、開発機に Xcode が
  未導入（Command Line Tools のみ）のため**未検証**。`CLAUDE.md` の合格条件にも
  含めていない。動作確認済みと案内しないこと。
- iOS: 未対応（プロジェクト構成なし）。

## 出典・権利表記

問題・解説データは `assets/data/exam-*.json` に含まれる `source` / `credit` を参照。

- 出典: [ケアマネージャー試験過去問題集](https://www.care-news.jp/kakomon/28/all_test.html)
- 解答・解説: 学校法人 藤仁館学園

試験問題そのものは公的試験の問題だが、**解説文は学校法人 藤仁館学園の著作物**である。
このアプリは個人利用の範囲に留め、第三者への配布・公開は行わない。

## Web 版との関係

- デザイン・画面構成・挙動は Web 版を踏襲するが、**コードは共有していない**
  （Dart で書き直した独立した実装）。
- **Web 版の localStorage に保存された受験履歴は引き継がない。** このアプリは
  `shared_preferences` による独自の永続化を持ち、初回起動時点では履歴は空になる。

## 既知の制限

- macOS は Xcode 未導入のため未検証（上記「対応プラットフォーム」参照）。
- Web 版の履歴データからの移行手段は用意していない。
