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
  - [ ] App Store Connect API キーの発行
  - [ ] GitHub の Secrets への登録
  - [ ] TestFlight の内部テスターの設定
  - [ ] Private Cloud Compute の権限の申請
- [ ] `testflight.yml` を成功させ、TestFlight にビルドを届ける
- [ ] iPad の TestFlight からインストールして起動を確かめる
- [ ] 設定画面の「AI」が「端末内AI」と表示されるのを確かめる

## 止まっていること

- **TestFlight への配信**：Apple 側の設定と Secrets の登録待ち

## あとで決めること

- Private Cloud Compute の権限が下りたあと：
  - モデルを作るだけで Apple のサーバーへ確認が走る。いまの作りでは起動時に作られるので、
    「標準状態で通信しない」を守るには「もっと詳しく」を押すまで作らない形に変える必要がある
  - 利用上限（1日の回数）に達したときの見せ方

## 設計書とコードの食い違い（持ち主の判断待ち。勝手には直さない）

設計書の第3版と照らした結果。ここに挙げたもの以外は、設計書どおりに実装されている。

1. **「言葉を足す」（3.2）**：合うトピックがないとき、「別の候補」はあるが、言葉を足す手段が画面にない
2. **「端末内では答えられません」（3.3）**：最新の出来事・価格・営業時間などでそう出す仕組みがない。
   指示文は 4.2 のとおり「確かでないことは書かないでください」だけ
3. **仮データで動いているときの知らせ（4.1）**：「正式版では起動時に伝える」とあり、いまは設定画面の「AI」表示だけ

見た目の方針（6章。罫線なし、ダークモードなど）は「後から設計する」とあるので、食い違いには数えていない。
