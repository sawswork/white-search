import Foundation
import SwiftUI
import UIKit

/// 検索の進行、履歴、設定、利用回数をまとめて持つ。
@MainActor
final class SearchModel: ObservableObject {
    // MARK: 決めごと（推奨値。あとで変えられる）
    /// 無料版で1日に調べられる回数
    static let freeDailyLimit = 5
    /// 無料版で保存できる履歴の件数
    static let freeHistoryLimit = 20
    /// これ以上は絞らず、必ず答えを出す階層数
    static let maxDepth = 4
    /// 手持ちの知識では答えられない問いに出す文言
    static let unanswerableText = "端末内では答えられません"

    @Published private(set) var trees: [SearchTree] = []
    @Published private(set) var currentTreeID: UUID?
    @Published private(set) var currentNodeID: UUID?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// 無料版の上限に当たったときの案内文
    @Published var limitMessage: String?

    // MARK: 設定
    /// 「もっと詳しく」（Appleのクラウド）を使うか
    @Published var cloudEnabled: Bool { didSet { defaults.set(cloudEnabled, forKey: "cloudEnabled") } }
    /// 「Webで確認する」を出すか（標準はオフ）
    @Published var webEnabled: Bool { didSet { defaults.set(webEnabled, forKey: "webEnabled") } }
    /// 履歴を開くときに本人確認を求めるか
    @Published var lockHistory: Bool { didSet { defaults.set(lockHistory, forKey: "lockHistory") } }
    /// 有料版かどうか。課金の実装前なので、いまは設定画面の試験用スイッチで切り替える。
    @Published var unlocked: Bool { didSet { defaults.set(unlocked, forKey: "unlocked") } }

    private let defaults = UserDefaults.standard
    private let engine: any SearchEngine = makeEngine()
    private let detailEngine: (any SearchEngine)? = makeDetailEngine()

    var engineName: String { engine.name }
    var detailAvailable: Bool { detailEngine != nil }
    var imagesAvailable: Bool { engine.supportsImages }

    init() {
        let stored = UserDefaults.standard
        cloudEnabled = stored.object(forKey: "cloudEnabled") as? Bool ?? true
        webEnabled = stored.bool(forKey: "webEnabled")
        lockHistory = stored.bool(forKey: "lockHistory")
        unlocked = stored.bool(forKey: "unlocked")
        trees = Storage.load()
    }

    // MARK: 画面から読む値

    var currentTree: SearchTree? {
        trees.first { $0.id == currentTreeID }
    }

    var currentNode: Node? {
        guard let id = currentNodeID else { return nil }
        return currentTree?.nodes[id]
    }

    /// 問いと、これまで選んだトピック。
    var currentPath: [Node] {
        guard let tree = currentTree, let id = currentNodeID else { return [] }
        return tree.path(to: id).filter { $0.kind != .answer }
    }

    /// いま選べるトピック。
    var currentTopics: [Node] {
        guard let tree = currentTree, let node = currentNode, node.kind != .answer else { return [] }
        return tree.children(of: node.id, kind: .topic)
    }

    var currentAnswer: Node? {
        currentNode?.kind == .answer ? currentNode : nil
    }

    var canGoBack: Bool {
        currentNode?.parent != nil
    }

    /// 「もっと詳しく」を出してよいか。
    var canDetail: Bool {
        cloudEnabled && detailEngine != nil && currentAnswer != nil && currentAnswer?.detailed != true
    }

    /// 今日あと何回調べられるか（有料版は nil）。
    var remainingToday: Int? {
        unlocked ? nil : max(0, Self.freeDailyLimit - usedToday)
    }

    /// 「Webで確認する」で開く検索の言葉。
    var webQuery: String {
        currentPath.map(\.text).joined(separator: " ")
    }

    // MARK: 操作

    /// 新しい問いで検索を始める。
    func start(question: String, image: UIImage? = nil) async {
        var text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLoading, !text.isEmpty || image != nil else { return }

        if image != nil && !unlocked {
            limitMessage = "画像からの検索は有料版で使えます"
            return
        }
        if image != nil && !engine.supportsImages {
            errorMessage = "この端末では画像からの検索を使えません"
            return
        }
        if !unlocked && usedToday >= Self.freeDailyLimit {
            limitMessage = "今日の無料分は使い切りました"
            return
        }
        countUp()

        if text.isEmpty { text = "この画像について" }
        var root = Node(kind: .question, text: text, chosen: true)
        if let image, let data = Storage.jpegData(from: image) {
            root.imageFile = Storage.saveImage(data)
        }
        let tree = SearchTree(root: root.id, nodes: [root.id: root])
        trees.insert(tree, at: 0)
        currentTreeID = tree.id
        currentNodeID = root.id
        save()
        await expand()
    }

    /// トピックを選んで次の階層へ進む。
    func choose(_ nodeID: UUID) async {
        guard !isLoading else { return }
        updateTree { $0.nodes[nodeID]?.chosen = true }
        currentNodeID = nodeID
        save()
        if currentTopics.isEmpty {
            await expand()
        }
    }

    /// 1つ前の階層に戻る。
    func goBack() {
        guard !isLoading, let parent = currentNode?.parent else { return }
        currentNodeID = parent
    }

    /// いまの階層のトピックを捨てて、別の候補を出し直す。
    func regenerate() async {
        guard !isLoading, let node = currentNode, node.kind != .answer else { return }
        let old = currentTopics
        updateTree { tree in
            for topic in old { tree.removeSubtree(topic.id) }
        }
        save()
        await expand(avoid: old.map(\.text), forceTopics: true)
    }

    /// 言葉を足して絞り直す。選択肢に合うものがないときや、出た答えがずれていたときに使う。
    /// 足した言葉は、自分で選んだトピックとして同じ木に残る。
    func addWords(_ words: String) async {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLoading, !text.isEmpty, let node = currentNode else { return }

        // 答えを見たあとなら、その答えは「選ばなかった枝」にして、1つ手前から続ける
        let fromAnswer = node.kind == .answer
        guard let baseID = fromAnswer ? node.parent : node.id else { return }

        let added = Node(kind: .topic, text: text, parent: baseID, chosen: true)
        updateTree { tree in
            if fromAnswer { tree.nodes[node.id]?.chosen = false }
            tree.nodes[added.id] = added
            tree.nodes[baseID]?.children.append(added.id)
        }
        currentNodeID = added.id
        save()

        if fromAnswer {
            // 一度答えを見ているので、足した言葉を踏まえた答えをすぐ出す
            await makeAnswer()
        } else {
            await expand()
        }
    }

    /// 絞り込みをやめて、いまの位置で答えを出す。
    func answerNow() async {
        guard !isLoading, let node = currentNode, node.kind != .answer else { return }
        await makeAnswer()
    }

    /// Appleのクラウドで、いまの答えを詳しく作り直す。
    func detail() async {
        guard !isLoading, canDetail,
              let detailEngine, let tree = currentTree,
              let answer = currentAnswer, let parent = answer.parent else { return }
        let request = makeRequest(tree: tree, nodeID: parent)

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await detailEngine.answer(request)
            guard result.answerable else {
                // クラウドでも答えられない問いは、端末内の答えをそのまま残す
                errorMessage = "詳しい答えを作れませんでした"
                return
            }
            updateTree { tree in
                tree.nodes[answer.id]?.text = result.headline
                tree.nodes[answer.id]?.points = result.points
                tree.nodes[answer.id]?.source = detailEngine.name
                tree.nodes[answer.id]?.detailed = true
            }
            save()
        } catch {
            // 上限や通信の失敗では、端末内の答えをそのまま残す
            errorMessage = "詳しい答えを作れませんでした: \(error.localizedDescription)"
        }
    }

    /// 検索を終えて、白い画面に戻る。
    func reset() {
        guard !isLoading else { return }
        currentTreeID = nil
        currentNodeID = nil
        errorMessage = nil
    }

    /// 履歴の節から調べ直す。
    func resume(treeID: UUID, nodeID: UUID) async {
        guard !isLoading else { return }
        currentTreeID = treeID
        updateTree { $0.nodes[nodeID]?.chosen = true }
        currentNodeID = nodeID
        save()
        if let node = currentNode, node.kind != .answer, node.children.isEmpty {
            await expand()
        }
    }

    func delete(treeID: UUID) {
        if let tree = trees.first(where: { $0.id == treeID }) {
            Storage.deleteImage(tree.imageFile)
        }
        trees.removeAll { $0.id == treeID }
        if currentTreeID == treeID { reset() }
        save()
    }

    func deleteAll() {
        for tree in trees { Storage.deleteImage(tree.imageFile) }
        trees.removeAll()
        reset()
        save()
    }

    func image(for tree: SearchTree) -> UIImage? {
        Storage.loadImage(tree.imageFile)
    }

    // MARK: 中身

    private func makeRequest(tree: SearchTree, nodeID: UUID, avoid: [String] = []) -> SearchRequest {
        let path = tree.path(to: nodeID).dropFirst().map(\.text)
        return SearchRequest(
            question: tree.question,
            imageData: Storage.loadImageData(tree.imageFile),
            path: Array(path),
            avoid: avoid
        )
    }

    private func expand(avoid: [String] = [], forceTopics: Bool = false) async {
        guard let tree = currentTree, let nodeID = currentNodeID else { return }
        let request = makeRequest(tree: tree, nodeID: nodeID, avoid: avoid)

        if request.path.count >= Self.maxDepth && !forceTopics {
            await makeAnswer()
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await engine.topics(request)
            // 答えが1つに決まる問いは、絞り込みをはさまずに答える
            if result.canAnswer && !forceTopics {
                isLoading = false
                await makeAnswer()
                return
            }
            updateTree { tree in
                for text in result.topics {
                    let child = Node(kind: .topic, text: text, parent: nodeID)
                    tree.nodes[child.id] = child
                    tree.nodes[nodeID]?.children.append(child.id)
                }
            }
            save()
        } catch {
            errorMessage = "トピックを出せませんでした: \(error.localizedDescription)"
        }
    }

    private func makeAnswer() async {
        guard let tree = currentTree, let nodeID = currentNodeID else { return }
        let request = makeRequest(tree: tree, nodeID: nodeID)

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await engine.answer(request)
            // 答えられない問いには、無理に答えず正直にそう出す
            var answer = Node(
                kind: .answer,
                text: result.answerable ? result.headline : Self.unanswerableText,
                points: result.answerable ? result.points : [],
                parent: nodeID,
                chosen: true
            )
            answer.source = engine.name
            let finished = answer
            updateTree { tree in
                tree.nodes[finished.id] = finished
                tree.nodes[nodeID]?.children.append(finished.id)
            }
            currentNodeID = finished.id
            save()
        } catch {
            errorMessage = "答えを出せませんでした: \(error.localizedDescription)"
        }
    }

    private func updateTree(_ change: (inout SearchTree) -> Void) {
        guard let index = trees.firstIndex(where: { $0.id == currentTreeID }) else { return }
        change(&trees[index])
    }

    private func save() {
        // 無料版は新しいものから一定件数だけ残す
        if !unlocked {
            while trees.count > Self.freeHistoryLimit, let last = trees.last, last.id != currentTreeID {
                Storage.deleteImage(last.imageFile)
                trees.removeLast()
            }
        }
        Storage.save(trees)
    }

    // MARK: 1日の利用回数（端末内で数える）

    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private var usedToday: Int {
        defaults.string(forKey: "countDate") == todayKey ? defaults.integer(forKey: "count") : 0
    }

    private func countUp() {
        let next = usedToday + 1
        defaults.set(todayKey, forKey: "countDate")
        defaults.set(next, forKey: "count")
        objectWillChange.send()
    }
}

/// 履歴と画像の保存。端末内だけに置き、バックアップの対象から外す。
enum Storage {
    private static var folder: URL {
        var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhiteSearch", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    private static var historyURL: URL { folder.appendingPathComponent("history.json") }

    static func load() -> [SearchTree] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return (try? JSONDecoder().decode([SearchTree].self, from: data)) ?? []
    }

    static func save(_ trees: [SearchTree]) {
        guard let data = try? JSONEncoder().encode(trees) else { return }
        try? data.write(to: historyURL, options: [.atomic, .completeFileProtection])
    }

    /// 向きを正し、長辺1024pxまで縮めたJPEGにする。
    static func jpegData(from image: UIImage) -> Data? {
        let longSide = max(image.size.width, image.size.height)
        guard longSide > 0 else { return nil }
        let scale = min(1, 1024 / longSide)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    static func saveImage(_ data: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            return name
        } catch {
            return nil
        }
    }

    static func loadImageData(_ name: String?) -> Data? {
        guard let name else { return nil }
        return try? Data(contentsOf: folder.appendingPathComponent(name))
    }

    static func loadImage(_ name: String?) -> UIImage? {
        loadImageData(name).flatMap { UIImage(data: $0) }
    }

    static func deleteImage(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }
}
