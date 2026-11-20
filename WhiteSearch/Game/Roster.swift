import Foundation

/// 役割。戦い方と強さを決める。
enum Role: String, CaseIterable {
    case sword = "剣士"
    case archer = "弓兵"
    case medic = "衛生兵"
    case scout = "斥候"

    /// 画面の丸の中に出す1文字
    var mark: String {
        switch self {
        case .sword: return "剣"
        case .archer: return "弓"
        case .medic: return "衛"
        case .scout: return "斥"
        }
    }

    var maxHP: Double {
        switch self {
        case .sword: return 120
        case .archer: return 70
        case .medic: return 80
        case .scout: return 80
        }
    }

    /// 1秒に進む距離
    var speed: Double {
        switch self {
        case .sword: return 55
        case .archer: return 50
        case .medic: return 55
        case .scout: return 95
        }
    }

    /// 攻撃（衛生兵は回復）が届く距離
    var range: Double {
        switch self {
        case .sword: return 30
        case .archer: return 190
        case .medic: return 100
        case .scout: return 30
        }
    }

    /// 1回の攻撃の強さ（衛生兵は回復量）
    var damage: Double {
        switch self {
        case .sword: return 14
        case .archer: return 9
        case .medic: return 8
        case .scout: return 9
        }
    }

    /// 次の攻撃までの秒数
    var cooldown: Double {
        switch self {
        case .sword: return 0.9
        case .archer: return 1.3
        case .medic: return 1.0
        case .scout: return 0.6
        }
    }
}

/// 性格。同じ指示でも、性格によって動きが変わる。
enum Personality: String, CaseIterable {
    case loyal = "忠実"
    case reckless = "猪突猛進"
    case timid = "臆病"
    case contrary = "あまのじゃく"
    case slow = "のんびり"
    case caring = "仲間思い"
    case cautious = "慎重"
    case moody = "気分屋"
    case showy = "目立ちたがり"
    case hasty = "早とちり"

    /// 隊員の一覧に出す説明。どう指示すればよいかの手がかりになる。
    var note: String {
        switch self {
        case .loyal:
            return "言われたとおりに動く。"
        case .reckless:
            return "敵が見えると、待てと言われても突っ込む。きびしく命じたときだけ我慢する。"
        case .timid:
            return "傷つくか、敵に囲まれると逃げる。はげますと踏みとどまる。きびしく言うとすくむ。"
        case .contrary:
            return "指示と逆のことをする。ていねいに頼んだときだけ素直に動く。"
        case .slow:
            return "指示が届いてから動き出すまでが遅く、足も遅い。きびしく急かすと早くなる。"
        case .caring:
            return "傷ついた仲間がいると、指示より先に助けに行く。"
        case .cautious:
            return "敵に近づきすぎない。前進と言われても、弓が届く所で止まる。きびしく命じると従う。"
        case .moody:
            return "気が向かないと、ふらふらする。ていねいに頼むと従う。きびしく言うとへそを曲げる。"
        case .showy:
            return "敵の隊長が見えると、ほかの指示を忘れて隊長を狙う。はげますと指示に集中する。"
        case .hasty:
            return "左右を取り違える。ほかの人への指示も、自分への指示だと思い込む。"
        }
    }
}

/// 隊員1人。
struct Member {
    let name: String
    let role: Role
    let personality: Personality
}

/// 部隊の編成。
enum Roster {
    /// 味方の10人。先頭が隊長。
    /// 前で戦う剣士4、後ろから撃つ弓兵3、回復の衛生兵1、足の速い斥候2。
    static let allies: [Member] = [
        Member(name: "ハヤト", role: .sword, personality: .loyal),
        Member(name: "ゴウ", role: .sword, personality: .reckless),
        Member(name: "レン", role: .sword, personality: .contrary),
        Member(name: "ダイチ", role: .sword, personality: .slow),
        Member(name: "ミオ", role: .archer, personality: .cautious),
        Member(name: "ソラ", role: .archer, personality: .timid),
        Member(name: "カイ", role: .archer, personality: .showy),
        Member(name: "ユイ", role: .medic, personality: .caring),
        Member(name: "ナギ", role: .scout, personality: .hasty),
        Member(name: "アキ", role: .scout, personality: .moody)
    ]

    /// 敵の10人。編成は味方と同じで、全員が言われたとおりに動く。先頭が隊長。
    static let enemies: [Member] = allies.enumerated().map { index, member in
        Member(name: "敵\(index + 1)", role: member.role, personality: .loyal)
    }
}
