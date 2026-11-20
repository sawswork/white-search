# White Search

iPhone / iPad アプリ「White Search」。問いを書くと、端末内AIがトピックを出して絞り込み、答えを出す。

## 前提

- 持ち主の手元にあるのは iPad だけ。Mac も Xcode もない。
- ビルドと配信はすべて GitHub Actions の mac ランナーで行う。
- この開発環境（Linux）では Swift をコンパイルできない。「push → Actions のログを読む → 直す」で進める。
- 非公開リポジトリの mac ランナー無料枠は月 290 分ほど。**ワークフローは手動実行（workflow_dispatch）だけ**。
  無駄に走らせない。push で自動実行する設定を足さない。
- 仕様は `docs/design.md`（設計書）に従う。判断に迷ったら設計書。

## 構成

| 場所 | 中身 |
| --- | --- |
| `project.yml` | XcodeGen の設定。ここから `WhiteSearch.xcodeproj` を生成する（xcodeproj はコミットしない） |
| `WhiteSearch/` | アプリのソース、`Info.plist`、`PrivacyInfo.xcprivacy`、`Assets.xcassets` |
| `WhiteSearch/Engine.swift` | AI の差し替え口（`SearchEngine`）、仮データの `MockEngine`、端末内AI（文字のみ） |
| `WhiteSearch/EngineIOS27.swift` | iOS 27 の機能：画像つきの問い、Appleのクラウド（Private Cloud Compute） |
| `WhiteSearch/SearchModel.swift` | 検索の進行・履歴・設定・利用回数、保存（`Storage`） |
| `.github/workflows/build.yml` | 署名なしのコンパイル確認 |
| `.github/workflows/testflight.yml` | アーカイブ → 署名 → TestFlight へアップロード |
| `docs/design.md` | 設計書 |
| `TASKS.md` | やること、済んだこと、止まっていること |

- Bundle ID：`com.sawswork.whitesearch`（仮。持ち主の確認待ち）
- ホーム画面の名前：White Search ／ プロジェクト名・保存フォルダ名：WhiteSearch
- 最低対応 OS：iOS 27 ／ Swift の言語モード：5

## ビルド方法

- ランナーは `xcode-27`（GitHub のプレビュー版イメージ。macOS 27 + Xcode 27.x）。Xcode 27.2 を選んでいる。
- `build`：GitHub の Actions タブ → build → Run workflow。署名なしでコンパイルだけ確かめる。
- `testflight`：同じく手動実行。ビルド番号は実行回数（`github.run_number`）で自動的に増える。
- 署名は App Store Connect API キーによる自動署名。アーカイブは署名なしで作り、
  書き出し（exportArchive）のときに配布用として署名する（開発用の署名は登録済み端末が要るため）。

### 必要な Secrets（リポジトリの Settings → Secrets and variables → Actions）

| 名前 | 入れるもの |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect API キーの「キー ID」（英数字 10 文字） |
| `ASC_ISSUER_ID` | 同じ画面の上にある「Issuer ID」（ハイフン入りの長い ID） |
| `ASC_PRIVATE_KEY` | ダウンロードした `AuthKey_XXXXXXXXXX.p8` の中身全部（`-----BEGIN PRIVATE KEY-----` から `-----END PRIVATE KEY-----` まで） |
| `APPLE_TEAM_ID` | Apple Developer の「チーム ID」（英数字 10 文字） |

## コンパイル条件

- `IOS27_SDK`：有効。画像検索と Appleのクラウド のコードをビルドに含める。
- `PCC_ENTITLEMENT`：**無効**。Apple から Private Cloud Compute の権限が下りるまで有効にしない。

### Private Cloud Compute の権限が下りたらやること

1. `WhiteSearch/WhiteSearch.entitlements` を作り `com.apple.developer.private-cloud-compute` = true を入れる
2. `project.yml` に `CODE_SIGN_ENTITLEMENTS` を足し、`SWIFT_ACTIVE_COMPILATION_CONDITIONS` に `PCC_ENTITLEMENT` を足す
3. 署名なしアーカイブでは権限が入らないので、`testflight.yml` の署名のしかたを見直す

## 守るべきルール

- 機能と仕様は設計書どおり。勝手に機能を足したり削ったりしない。
- 見た目は仮のまま。デザインは後で別に設計する。
- `MockEngine` を残す（端末内AIが使えない端末でも落ちないように）。
- **標準状態でアプリは通信しない。** 分析ツール、広告、外部 SDK、自前サーバーを入れない。
- 権限（entitlement）なしで Private Cloud Compute を呼ばない。公式文書によると、権限がなくても
  `isAvailable` は true になりえて、問いを送った瞬間にアプリが落ちる。だから実行時の判定ではなく
  `PCC_ENTITLEMENT` で切り離している。権限がない間は「もっと詳しく」が画面に出ない作りを保つ。
- `PrivateCloudComputeLanguageModel()` は作っただけで Apple のサーバーへ確認が走る。必要になるまで作らない。
- コード内のコメントと画面の文言は日本語。
- 課金（StoreKit）はまだ実装しない。設定画面の試験用スイッチ（「有料版として動かす」）を残す。
- Foundation Models の API は記憶で書かず、公式文書で確かめる。
  JSON で読める：`https://developer.apple.com/tutorials/data/documentation/foundationmodels.json`
  （個別のページは `.../documentation/foundationmodels/<名前>.json`）
- 持ち主にしか決められないことは、作業を止めて聞く。
- 変更したらこまめにコミットして push する。
