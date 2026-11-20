# TASKS

## 済んだこと

- 試作コード（ShiroiKensaku.swiftpm）を `WhiteSearch/` に配置し、名前を WhiteSearch に変更
- XcodeGen（`project.yml`）、`Info.plist`、`PrivacyInfo.xcprivacy`、仮アイコン（白地に輪、1024px）を用意
- `EngineIOS27.swift` を Apple の公式文書と照合
  - 画像つきの問い（`Attachment`）と `PrivateCloudComputeLanguageModel` の書き方は文書と一致
  - 権限なしで Appleのクラウド を呼ぶと落ちるため、`PCC_ENTITLEMENT` で切り離した
- `build.yml` / `testflight.yml` を作成

## やること

- [x] `build.yml` を成功させる（1回目で成功。約1分。Xcode 27.2 / iOS 27 SDK）
- [x] 設計書（第3版）を `docs/design.md` に置き、コードと照合
- [ ] Apple 側の設定（持ち主の作業。1つずつ案内する）
  - [x] Apple Developer Program の登録状況の確認（登録済み、個人）
  - [x] Bundle ID の登録（`com.sawswork.whitesearch`）
  - [x] App Store Connect でアプリ「White Search」を作る（名前は White Search のまま通った）
  - [x] App Store Connect API キーの発行
  - [x] GitHub の Secrets への登録
  - [ ] TestFlight の内部テスターの設定
  - [ ] Private Cloud Compute の権限の申請
- [x] `testflight.yml` を成功させ、TestFlight にビルドを届ける（1回目で成功。約4分。バージョン 0.2、ビルド 1）
- [ ] iPad の TestFlight からインストールして起動を確かめる
- [ ] 設定画面の「AI」が「端末内AI」と表示されるのを確かめる

## 止まっていること

- **実機での確認**：内部テスターの設定と、iPad へのインストール待ち（持ち主の作業）

## あとで決めること

- Private Cloud Compute の権限が下りたあと：
  - モデルを作るだけで Apple のサーバーへ確認が走る。いまの作りでは起動時に作られるので、
    「標準状態で通信しない」を守るには「もっと詳しく」を押すまで作らない形に変える必要がある
  - 利用上限（1日の回数）に達したときの見せ方

## 設計書 第4版で入れたもの（実機での確認待ち）

持ち主の指示「要件から変えてよい。答えを導き出すために必要な機能を実装する」による。

- トピックを「答えが変わる分かれ目」にする指示文。階層ごとの分け方（目的 → 状況 → 範囲）
- 先にありうる答えを考えさせ、逆算して選択肢を作る生成の型
- 答えが1つに決まる問いは、最初から答える
- 「言葉を足す」（絞り込みの途中でも、答えを見たあとでも）
- 「端末内では答えられません」
- 結論に絞り込みの前提を織り込む

実機で確かめる観点は `docs/design.md` の 11章 ④〜⑦。

## 設計書とコードの食い違い

- **仮データで動いているときの知らせ（4.1）**：「正式版では起動時に伝える」とあり、いまは設定画面の「AI」表示だけ

## 持ち主の判断待ち

- **Web の情報を答えに使うか**：端末内AIは最新の出来事や価格に答えられない。
  答えの質を大きく上げるには、問いを外部（検索サービスや Wikipedia など）に送って裏づけを取る方法がある。
  ただし問いが端末の外に出るので、どのサービスに送るかは持ち主が決める
