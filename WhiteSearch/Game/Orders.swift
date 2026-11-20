import Foundation

/// どこへ動くか。
enum Move: String, CaseIterable {
    case forward = "前進"
    case back = "後退"
    case left = "左へ"
    case right = "右へ"
    case center = "中央へ"
    case hold = "待機"
    case charge = "突撃"
    case gather = "集合"
}

/// 敵をどう扱うか。
enum Engage: String, CaseIterable {
    case free = "攻撃する"
    case returnFire = "反撃だけ"
    case never = "攻撃しない"
}

/// どの敵を狙うか。
enum TargetPref: String, CaseIterable {
    case nearest = "近い敵"
    case weakest = "弱った敵"
    case archer = "敵の弓兵"
    case medic = "敵の衛生兵"
}

/// 言い方。性格によって効き方が違う。
enum Tone: String, CaseIterable {
    case neutral = "ふつう"
    case polite = "ていねい"
    case strict = "きびしい"
    case encourage = "はげまし"
}

/// 隊員が受け取っている指示。
struct Order: Equatable {
    var move: Move = .hold
    var engage: Engage = .free
    var target: TargetPref = .nearest
}

/// 1つの指示。書かれていない項目は nil で、いまの指示をそのまま続ける。
struct Command {
    /// 対象の隊員の番号。
    var targets: Set<Int>
    var move: Move?
    var engage: Engage?
    var target: TargetPref?
    var tone: Tone = .neutral

    var hasAction: Bool { move != nil || engage != nil || target != nil }

    /// 記録に出す短い説明
    var summary: String {
        var parts: [String] = []
        if let move { parts.append(move.rawValue) }
        if let engage { parts.append(engage.rawValue) }
        if let target { parts.append(target.rawValue) }
        if tone != .neutral { parts.append("（\(tone.rawValue)）") }
        return parts.joined(separator: "・")
    }
}

/// 言葉の中の決まった語を拾って指示に直す。端末内AIが使えないときの代わり。
enum CommandParser {
    static func parse(_ text: String, roster: [Member]) -> [Command] {
        var commands: [Command] = []
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: "。\n"))
        for sentence in sentences {
            // 「ソラは大丈夫、前進」のように、対象や言い方が先に来て動きが後に来ることがある。
            // 動きのない区切りの対象と言い方は、次の区切りへ持ち越す。
            var pendingTargets: Set<Int>?
            var pendingTone: Tone = .neutral
            for clause in sentence.components(separatedBy: CharacterSet(charactersIn: "、,")) {
                let trimmed = clause.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                let targets = self.targets(in: trimmed, roster: roster)
                var tone = self.tone(in: trimmed)
                if tone == .neutral { tone = pendingTone }
                var command = Command(
                    targets: targets ?? pendingTargets ?? Set(roster.indices),
                    move: move(in: trimmed),
                    engage: engage(in: trimmed),
                    target: targetPref(in: trimmed),
                    tone: tone
                )
                if command.hasAction {
                    if command.targets.isEmpty { command.targets = Set(roster.indices) }
                    commands.append(command)
                    if targets != nil { pendingTargets = targets }
                } else {
                    if targets != nil { pendingTargets = targets }
                    pendingTone = tone
                }
            }
        }
        return commands
    }

    private static func containsAny(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    /// 対象の隊員。書かれていなければ nil。
    static func targets(in text: String, roster: [Member]) -> Set<Int>? {
        if containsAny(text, ["全員", "みんな", "全軍", "総員"]) && !text.contains("以外") {
            return Set(roster.indices)
        }
        var found = Set<Int>()
        for (index, member) in roster.enumerated() where text.contains(member.name) {
            found.insert(index)
        }
        for role in Role.allCases {
            var words = [role.rawValue]
            if role == .archer { words.append("弓") }
            if role == .sword { words.append("剣") }
            if role == .medic { words.append("衛生") }
            for word in words where text.contains(word) {
                // 「敵の弓兵を狙え」は狙う相手の話で、味方の弓兵のことではない
                let asEnemy = containsAny(text, ["敵の\(word)", "\(word)を", "\(word)兵を", "\(word)から"])
                if !asEnemy {
                    for (index, member) in roster.enumerated() where member.role == role {
                        found.insert(index)
                    }
                }
            }
        }
        if found.isEmpty { return nil }
        if text.contains("以外") {
            return Set(roster.indices).subtracting(found)
        }
        return found
    }

    static func move(in text: String) -> Move? {
        if containsAny(text, ["待機", "止ま", "待て", "待って", "動くな", "動かない", "その場", "とどま"]) { return .hold }
        if containsAny(text, ["下が", "退", "後ろ", "引け", "引いて", "逃げ", "戻"]) { return .back }
        if containsAny(text, ["集ま", "集合", "固ま", "隊長のもと", "隊長のそば"]) { return .gather }
        if containsAny(text, ["突撃", "突っ込", "攻め込", "敵に向か", "追え", "追って", "追撃"]) { return .charge }
        if text.contains("左") { return .left }
        if text.contains("右") { return .right }
        if containsAny(text, ["中央", "真ん中"]) { return .center }
        if containsAny(text, ["前進", "進め", "進ん", "進む", "前へ", "前に", "まっすぐ"]) { return .forward }
        return nil
    }

    static func engage(in text: String) -> Engage? {
        if containsAny(text, ["攻撃するな", "攻撃しない", "攻撃せず", "戦うな", "戦わず", "戦わない", "手を出すな", "撃つな", "避け"]) {
            return .never
        }
        if containsAny(text, ["反撃", "攻撃されたら", "撃たれたら", "やられたら"]) { return .returnFire }
        if containsAny(text, ["攻撃", "倒せ", "倒して", "戦え", "戦って", "撃て", "撃って", "討て", "やっつけ", "狙"]) { return .free }
        return nil
    }

    static func targetPref(in text: String) -> TargetPref? {
        if containsAny(text, ["敵の弓", "弓兵を", "弓を", "弓兵から", "弓から"]) { return .archer }
        if containsAny(text, ["敵の衛生", "衛生兵を", "衛生兵から", "回復役"]) { return .medic }
        if containsAny(text, ["弱", "瀕死", "手負い", "傷ついた敵"]) { return .weakest }
        if containsAny(text, ["近い敵", "近くの敵", "目の前の敵"]) { return .nearest }
        return nil
    }

    static func tone(in text: String) -> Tone {
        if containsAny(text, ["大丈夫", "信じ", "頼りに", "できる", "がんばれ", "頑張", "いいぞ", "さすが", "期待"]) {
            return .encourage
        }
        if containsAny(text, ["お願い", "ください", "頼む", "頼んだ", "頼みます", "してほしい", "よろしく"]) {
            return .polite
        }
        if containsAny(text, ["急げ", "今すぐ", "命令", "絶対", "必ず", "！！", "!!", "いいから"]) {
            return .strict
        }
        return .neutral
    }
}
