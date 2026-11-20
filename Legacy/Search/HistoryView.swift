import SwiftUI

/// 履歴。調べた流れを、線で結んだ木として見せる。
struct HistoryView: View {
    @EnvironmentObject private var model: SearchModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.trees) { tree in
                    Section {
                        if let image = model.image(for: tree) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 80)
                                .listRowSeparator(.hidden)
                                .accessibilityLabel("問いに添えた画像")
                        }
                        TreeView(tree: tree) { nodeID in
                            Task { await model.resume(treeID: tree.id, nodeID: nodeID) }
                            dismiss()
                        }
                        .listRowSeparator(.hidden)
                    } header: {
                        HStack {
                            Text(tree.date.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Button("削除", role: .destructive) { model.delete(treeID: tree.id) }
                                .font(.footnote)
                        }
                    }
                }
                if !model.unlocked {
                    Text("無料版では新しい\(SearchModel.freeHistoryLimit)件まで保存されます")
                        .font(.footnote)
                        .foregroundStyle(Color.gray)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .overlay {
                if model.trees.isEmpty {
                    Text("まだ履歴はありません")
                        .foregroundStyle(Color.gray)
                }
            }
            .navigationTitle("履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("設定") { showingSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(model)
            }
        }
    }
}

/// 1本の木。たどった道は濃く、選ばなかった枝は薄く描く。
struct TreeView: View {
    let tree: SearchTree
    let onSelect: (UUID) -> Void

    private let indent: CGFloat = 20
    private let rowHeight: CGFloat = 40

    var body: some View {
        let rows = tree.flattened()
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.node.id) { _, row in
                Button {
                    onSelect(row.node.id)
                } label: {
                    HStack(spacing: 8) {
                        // 親の階層ぶんの縦線
                        ForEach(0..<row.depth, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.gray.opacity(0.4))
                                .frame(width: 1, height: rowHeight)
                                .frame(width: indent - 8)
                        }
                        Circle()
                            .fill(color(for: row.node))
                            .frame(width: 8, height: 8)
                        Text(row.node.text)
                            .font(row.node.chosen ? .subheadline.weight(.semibold) : .subheadline)
                            .foregroundStyle(color(for: row.node))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: rowHeight)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func color(for node: Node) -> Color {
        if node.kind == .answer { return Color.indigo }
        return node.chosen ? Color.black : Color.gray
    }
}
