# White Search

iPhone / iPad アプリ「White Search」。いまの中身は、10人の部隊に自然な言葉で指示を出して敵を倒すゲーム。
隊員は性格がばらばらで、同じ指示でもそのとおりには動かない。

元は検索アプリだった。持ち主の指示でその機能はいったん置いてあり、
コードは `Legacy/Search/`（ビルド対象外）、設計書は `docs/search-design.md` に残してある。消さない。

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
| `WhiteSearch/Game/Roster.swift` | 役割、性格、隊員の編成 |
| `WhiteSearch/Game/Orders.swift` | 指示の形と、決まった語を拾う読み取り（`CommandParser`） |
| `WhiteSearch/Game/Battle.swift` | 戦いの進行。性格による動きの違いと、強さの調整値もここ |
| `WhiteSearch/Game/Interpreter.swift` | 端末内AIによる指示の読み取り |
| `WhiteSearch/Game/GameModel.swift` / `GameView.swift` | 進行と画面 |
| `Tools/sim/main.swift` | 戦いを画面なしで回して勝率を出す（強さの調整用） |
| `.github/workflows/sim.yml` | 上を Linux ランナーで実行する（mac の無料枠を使わない） |
| `Legacy/Search/` | 置いてある検索アプリのコード（ビルド対象外） |
| `.github/workflows/build.yml` | 署名なしのコンパイル確認 |
| `.github/workflows/testflight.yml` | アーカイブ → 署名 → TestFlight へアップロード |
| `docs/design.md` | 設計書（ゲーム版） |
| `TASKS.md` | やること、済んだこと、止まっていること |

- Bundle ID：`com.sawswork.whitesearch`（Apple Developer に登録済み。変更不可）
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

## 強さの調整

- `Roster.swift` `Orders.swift` `Battle.swift` は Foundation だけで書き、Linux でもコンパイルできる状態を保つ
  （SwiftUI や UIKit を持ち込まない）。こうしておくと sim で安く確かめられる。
- 性格や強さを変えたら、Actions の `sim` を回して勝率を確かめる。ねらいは `docs/design.md` の5章。
- sim はロジックのコンパイル確認にもなる。mac の `build` を回す前に sim を通す。

## コンパイル条件（検索アプリ用。いまは使っていない）

- `IOS27_SDK`：`project.yml` で有効のまま。`Legacy/Search/` のコードが使う。
- `PCC_ENTITLEMENT`：無効。Private Cloud Compute の権限なしで有効にするとアプリが落ちる。

## 守るべきルール

- 仕様は設計書（`docs/design.md`）どおり。変えるときは設計書も直す。
- 見た目は仮のまま。デザインは後で別に設計する。
- **アプリは通信しない。** 分析ツール、広告、外部 SDK、自前サーバーを入れない。
- 端末内AIが使えない端末でも遊べるように、`KeywordInterpreter`（かんたん読み取り）を残す。
- コード内のコメントと画面の文言は日本語。
- Foundation Models の API は記憶で書かず、公式文書で確かめる。
  JSON で読める：`https://developer.apple.com/tutorials/data/documentation/foundationmodels.json`
  （個別のページは `.../documentation/foundationmodels/<名前>.json`）
- 持ち主にしか決められないことは、作業を止めて聞く。
- 変更したらこまめにコミットして push する。
