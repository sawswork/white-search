# TASKS

## 済んだこと

- 試作コード（ShiroiKensaku.swiftpm）を `WhiteSearch/` に配置し、名前を WhiteSearch に変更
- XcodeGen（`project.yml`）、`Info.plist`、`PrivacyInfo.xcprivacy`、仮アイコン（白地に輪、1024px）を用意
- `EngineIOS27.swift` を Apple の公式文書と照合
  - 画像つきの問い（`Attachment`）と `PrivateCloudComputeLanguageModel` の書き方は文書と一致
  - 権限なしで Appleのクラウド を呼ぶと落ちるため、`PCC_ENTITLEMENT` で切り離した
- `build.yml` / `testflight.yml` を作成

## やること

- [ ] `build.yml` を成功させる
- [ ] 設計書を `docs/design.md` に置く
- [ ] Apple 側の設定（持ち主の作業。1つずつ案内する）
  - [ ] Apple Developer Program の登録状況の確認
  - [ ] Bundle ID の登録（案：`com.sawswork.whitesearch`）
  - [ ] App Store Connect でアプリ「White Search」を作る
  - [ ] App Store Connect API キーの発行
  - [ ] GitHub の Secrets への登録
  - [ ] TestFlight の内部テスターの設定
  - [ ] Private Cloud Compute の権限の申請
- [ ] `testflight.yml` を成功させ、TestFlight にビルドを届ける
- [ ] iPad の TestFlight からインストールして起動を確かめる
- [ ] 設定画面の「AI」が「端末内AI」と表示されるのを確かめる

## 止まっていること

- **設計書が届いていない**：添付は zip だけだった。本文を貼ってもらえば `docs/design.md` に置き、コードと照合する
- **TestFlight への配信**：Apple 側の設定と Secrets の登録待ち

## あとで決めること

- Private Cloud Compute の権限が下りたあと：
  - モデルを作るだけで Apple のサーバーへ確認が走る。いまの作りでは起動時に作られるので、
    「標準状態で通信しない」を守るには「もっと詳しく」を押すまで作らない形に変える必要がある
  - 利用上限（1日の回数）に達したときの見せ方
