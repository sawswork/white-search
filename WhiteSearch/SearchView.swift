import SwiftUI
import PhotosUI
import LocalAuthentication
import UIKit

/// 検索の画面。見た目は仮で、機能の確認だけを目的にしている。
struct SearchView: View {
    @EnvironmentObject private var model: SearchModel
    @Environment(\.openURL) private var openURL

    @State private var input = ""
    @State private var attachedImage: UIImage?
    @State private var clipboardHasImage = false

    @State private var showingHistory = false
    @State private var showingMenu = false
    @State private var showingCamera = false
    @State private var showingPhotos = false
    @State private var photoItem: PhotosPickerItem?

    /// 初回だけ出すヒントの管理
    @AppStorage("hasTyped") private var hasTyped = false
    @AppStorage("hasSent") private var hasSent = false

    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = model.limitMessage {
                limitArea(message)
            } else if model.currentTree == nil {
                inputArea
            } else {
                pathArea
                Spacer(minLength: 16)
                answerArea
                Spacer(minLength: 16)
                bottomArea
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .contentShape(Rectangle())
        // 入力中は下スワイプで送信する
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard value.translation.height > 60, model.currentTree == nil, model.limitMessage == nil else { return }
                submit()
            }
        )
        // 画面の長押しで、画像入力のメニューを出す
        .onLongPressGesture {
            guard model.currentTree == nil, model.limitMessage == nil else { return }
            showingMenu = true
        }
        .confirmationDialog("", isPresented: $showingMenu) {
            Button("ペースト") { paste() }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("写真を撮る") { showingCamera = true }
            }
            Button("写真から選ぶ") { showingPhotos = true }
        }
        .photosPicker(isPresented: $showingPhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    attachedImage = image
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in attachedImage = image }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView()
                .environmentObject(model)
        }
        .onAppear {
            inputFocused = true
            clipboardHasImage = UIPasteboard.general.hasImages
        }
    }

    // MARK: 入力（何もない画面）

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let attachedImage {
                Image(uiImage: attachedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .onTapGesture { self.attachedImage = nil }
                    .accessibilityLabel("添えた画像。タップで外す")
            }
            TextField("", text: $input, axis: .vertical)
                .font(.title2)
                .foregroundStyle(Color.black)
                .tint(.clear) // カーソルを見せない
                .focused($inputFocused)
                .submitLabel(.search)
                .onChange(of: input) { _, newValue in
                    if !newValue.isEmpty { hasTyped = true }
                    // 改行キーでも送信できるようにする
                    if newValue.contains("\n") {
                        input = newValue.replacingOccurrences(of: "\n", with: "")
                        submit()
                    }
                }

            Spacer()

            // 初回だけ：何をすればいいかを薄く示す
            if !hasTyped && input.isEmpty && attachedImage == nil {
                Text("問いを書く")
                    .font(.title3)
                    .foregroundStyle(Color.black.opacity(0.25))
                    .frame(maxWidth: .infinity)
            }

            Spacer()

            if let message = model.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }

            // 初めて送るまで：送り方を一度だけ示す
            if !hasSent && (!input.isEmpty || attachedImage != nil) {
                Text("↓ 下に引いて送る")
                    .font(.footnote)
                    .foregroundStyle(Color.black.opacity(0.35))
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 20) {
                if clipboardHasImage && attachedImage == nil {
                    Button("画像を貼る") { paste() }
                }
                Spacer()
                if let remaining = model.remainingToday {
                    Text("今日あと\(remaining)回")
                }
                Button("履歴") { openHistory() }
            }
            .font(.footnote)
            .foregroundStyle(Color.gray)
            .frame(minHeight: 44)
        }
    }

    private func submit() {
        let question = input
        let image = attachedImage
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil else { return }
        input = ""
        attachedImage = nil
        hasSent = true
        inputFocused = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await model.start(question: question, image: image) }
    }

    private func paste() {
        let pasteboard = UIPasteboard.general
        if let image = pasteboard.image {
            attachedImage = image
            clipboardHasImage = false
        } else if let text = pasteboard.string {
            input += text
        }
    }

    // MARK: 無料版の上限に当たったとき

    private func limitArea(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(message)
                .font(.title3)
                .foregroundStyle(Color.black)
            Text("有料版は、回数無制限・画像検索・履歴の無制限保存")
                .font(.footnote)
                .foregroundStyle(Color.gray)
            Text("購入はまだ用意できていません")
                .font(.footnote)
                .foregroundStyle(Color.gray)
            Spacer()
            Button("閉じる") {
                model.limitMessage = nil
                inputFocused = true
            }
            .font(.footnote)
            .foregroundStyle(Color.gray)
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: 上：問いと、選んできたトピック

    private var pathArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let tree = model.currentTree, let image = model.image(for: tree) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 100)
                    .accessibilityLabel("問いに添えた画像")
            }
            ForEach(Array(model.currentPath.enumerated()), id: \.element.id) { index, node in
                Text(node.text)
                    .font(index == 0 ? .headline : .subheadline)
                    .foregroundStyle(index == 0 ? Color.black : Color.gray)
            }
        }
    }

    // MARK: 中央：答え

    @ViewBuilder
    private var answerArea: some View {
        if let answer = model.currentAnswer {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(answer.text)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.black)
                    ForEach(answer.points, id: \.self) { point in
                        Text("・" + point)
                            .font(.body)
                            .foregroundStyle(Color.black)
                    }
                    Text("\(answer.source ?? model.engineName)で生成")
                        .font(.footnote)
                        .foregroundStyle(Color.gray)

                    if model.isLoading {
                        ProgressView()
                    }
                    if let message = model.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color.red)
                    }

                    if model.canDetail {
                        VStack(alignment: .leading, spacing: 2) {
                            Button("もっと詳しく") { Task { await model.detail() } }
                                .frame(minHeight: 44)
                            Text("押したときだけ、問いがAppleのクラウドに送られます")
                                .font(.caption)
                                .foregroundStyle(Color.gray)
                        }
                        .disabled(model.isLoading)
                    }
                    if model.webEnabled {
                        Button("Webで確認する（外部へ送信）") { openWebSearch() }
                            .frame(minHeight: 44)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if let message = model.errorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.red)
        }
    }

    /// ブラウザに検索を渡す。端末で設定されている検索エンジンが使われる。
    private func openWebSearch() {
        let query = model.webQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let primary = URL(string: "x-web-search://?\(query)"),
              let fallback = URL(string: "https://duckduckgo.com/?q=\(query)") else { return }
        openURL(primary) { accepted in
            if !accepted { openURL(fallback) }
        }
    }

    // MARK: 下：選択肢と操作

    private var bottomArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.currentTopics) { topic in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await model.choose(topic.id) }
                } label: {
                    Text(topic.text)
                        .font(.title3)
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                }
                .disabled(model.isLoading)
                Divider()
            }
            HStack(spacing: 20) {
                if model.canGoBack {
                    Button("戻る") { model.goBack() }
                }
                if model.currentAnswer == nil {
                    Button("別の候補") { Task { await model.regenerate() } }
                    Button("答えを見る") { Task { await model.answerNow() } }
                }
                Spacer()
                Button("履歴") { openHistory() }
                Button("新しく調べる") {
                    model.reset()
                    inputFocused = true
                    clipboardHasImage = UIPasteboard.general.hasImages
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.gray)
            .frame(minHeight: 44)
            .disabled(model.isLoading)
        }
    }

    // MARK: 履歴を開く（設定によっては本人確認をはさむ）

    private func openHistory() {
        guard model.lockHistory else {
            showingHistory = true
            return
        }
        Task {
            let context = LAContext()
            let ok = (try? await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "履歴を開きます"
            )) ?? false
            if ok { showingHistory = true }
        }
    }
}

/// カメラで1枚撮る。
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
