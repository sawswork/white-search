import SwiftUI

/// 設定。外に出る機能は、ここでオフにするとボタンごと画面から消える。
struct SettingsView: View {
    @EnvironmentObject private var model: SearchModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDeleteAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("「もっと詳しく」を使う", isOn: $model.cloudEnabled)
                    Toggle("「Webで確認する」を使う", isOn: $model.webEnabled)
                } header: {
                    Text("外に送る機能")
                } footer: {
                    Text("どちらも、ボタンを押したその1回だけ問いが端末の外に送られます。オフにするとボタン自体が消え、アプリは一切通信しません。"
                         + (model.detailAvailable ? "" : "\nこの環境では「もっと詳しく」は使えません。"))
                }

                Section("履歴") {
                    Toggle("開くときに本人確認をする", isOn: $model.lockHistory)
                    Button("すべての履歴を削除", role: .destructive) { confirmingDeleteAll = true }
                        .disabled(model.trees.isEmpty)
                }

                Section {
                    Toggle("有料版として動かす", isOn: $model.unlocked)
                } header: {
                    Text("試験用")
                } footer: {
                    Text("課金の実装前の仮スイッチです。オフのときは1日\(SearchModel.freeDailyLimit)回まで、履歴は\(SearchModel.freeHistoryLimit)件まで、画像検索は使えません。")
                }

                Section("状態") {
                    LabeledContent("AI", value: model.engineName)
                    LabeledContent("画像からの検索", value: model.imagesAvailable ? "使える" : "使えない")
                    LabeledContent("もっと詳しく", value: model.detailAvailable ? "使える" : "使えない")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .confirmationDialog("すべての履歴を削除しますか？", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
                Button("削除する", role: .destructive) { model.deleteAll() }
            }
        }
    }
}
