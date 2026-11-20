import Foundation

/// 木の1つの節。問い・トピック・答えのいずれか。
struct Node: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case question
        case topic
        case answer
    }

    var id = UUID()
    var kind: Kind
    var text: String
    /// 答えの要点（kind が answer のときだけ使う）
    var points: [String] = []
    var parent: UUID?
    var children: [UUID] = []
    /// たどった道なら true。選ばなかった枝は false。
    var chosen = false
    /// 問いに添えた画像のファイル名（問いの節だけ）
    var imageFile: String?
    /// 答えを作った場所（「端末内AI」「Appleのクラウド」など）
    var source: String?
    /// 「もっと詳しく」で作り直した答えなら true
    var detailed: Bool?
}

/// 1回の検索 = 1本の木。
struct SearchTree: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var root: UUID
    var nodes: [UUID: Node]

    var question: String { nodes[root]?.text ?? "" }
    var imageFile: String? { nodes[root]?.imageFile }

    /// 根から指定の節までの道（根を含む）。
    func path(to nodeID: UUID) -> [Node] {
        var result: [Node] = []
        var current = nodes[nodeID]
        while let node = current {
            result.insert(node, at: 0)
            current = node.parent.flatMap { nodes[$0] }
        }
        return result
    }

    func children(of nodeID: UUID, kind: Node.Kind? = nil) -> [Node] {
        guard let node = nodes[nodeID] else { return [] }
        let all = node.children.compactMap { nodes[$0] }
        guard let kind else { return all }
        return all.filter { $0.kind == kind }
    }

    /// 履歴表示用に、木を深さつきの一列に並べる。
    func flattened() -> [(node: Node, depth: Int)] {
        var result: [(Node, Int)] = []
        func visit(_ id: UUID, _ depth: Int) {
            guard let node = nodes[id] else { return }
            result.append((node, depth))
            // 選ばなかった枝を先に、たどった道を最後に並べる
            let kids = node.children.compactMap { nodes[$0] }
            for child in kids.filter({ !$0.chosen }) { visit(child.id, depth + 1) }
            for child in kids.filter({ $0.chosen }) { visit(child.id, depth + 1) }
        }
        visit(root, 0)
        return result
    }

    mutating func removeSubtree(_ nodeID: UUID) {
        guard let node = nodes[nodeID] else { return }
        for child in node.children { removeSubtree(child) }
        if let parent = node.parent {
            nodes[parent]?.children.removeAll { $0 == nodeID }
        }
        nodes[nodeID] = nil
    }
}
