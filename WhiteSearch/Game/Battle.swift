import Foundation

/// 戦場の上の位置や向き。
struct Vec: Equatable {
    var x: Double
    var y: Double

    static let zero = Vec(x: 0, y: 0)

    static func + (a: Vec, b: Vec) -> Vec { Vec(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Vec, b: Vec) -> Vec { Vec(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Vec, k: Double) -> Vec { Vec(x: a.x * k, y: a.y * k) }

    var length: Double { (x * x + y * y).squareRoot() }

    /// 同じ向きで長さ1。長さ0ならそのまま。
    var unit: Vec {
        let l = length
        return l > 0.0001 ? Vec(x: x / l, y: y / l) : .zero
    }

    func distance(to other: Vec) -> Double { (self - other).length }
}

/// 同じ種からは同じ並びが出る乱数。戦いを再現して強さを調整するために使う。
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Side {
    case ally
    case enemy
}

enum Outcome {
    case win
    case lose
    case draw
}

/// 戦場にいる1人。
struct Unit: Identifiable {
    let id: Int
    let member: Member
    let side: Side
    let isCaptain: Bool
    let maxHP: Double
    /// 攻撃の強さにかける倍率
    let power: Double

    var pos: Vec
    var hp: Double
    var order = Order()
    var cooldown = 0.0

    /// まだ動き出していない指示（のんびり用）
    var pendingOrder: Order?
    var pendingAt = 0.0

    /// 最後にかけられた言い方と、それが効いている時刻の終わり
    var tone: Tone = .neutral
    var toneUntil = 0.0
    /// すくんで動けない時刻の終わり（臆病用）
    var freezeUntil = 0.0

    /// 気分屋が、いま指示に従う気があるか
    var moodObeys = true
    var moodNextRoll = 0.0
    var wanderGoal = Vec.zero

    /// 最後に自分を攻撃した相手と、その時刻
    var lastAttacker: Int?
    var lastHitAt = -100.0

    var alive: Bool { hp > 0 }
    var role: Role { member.role }
}

/// 画面に一瞬だけ描く線（矢、回復）。
struct Shot {
    var from: Vec
    var to: Vec
    var born: Double
    var heal: Bool
}

/// 戦い全体。画面とは切り離してあり、これだけで最後まで進められる。
struct Battle {
    static let width = 600.0
    static let height = 900.0
    /// これを過ぎたら、残った体力で勝ち負けを決める
    static let timeLimit = 180.0

    // 強さの調整値。Tools/sim で勝率を確かめながら決める。
    /// 敵の体力と攻撃にかける倍率（ステージ1）
    static let enemyBase = 0.95
    /// ステージが1つ進むごとに敵に足す倍率
    static let enemyPerStage = 0.02

    let stage: Int
    private(set) var units: [Unit] = []
    private(set) var time = 0.0
    private(set) var shots: [Shot] = []
    private(set) var outcome: Outcome?
    private var rng: SeededRandom
    private var enemyStep = 0

    /// enemyBase と plainAllies は強さの調整（Tools/sim）のためのもの。
    /// plainAllies を true にすると、味方も全員が言われたとおりに動く。
    init(stage: Int, seed: UInt64, enemyBase: Double = Battle.enemyBase, plainAllies: Bool = false) {
        self.stage = stage
        rng = SeededRandom(seed: seed)

        // 並び：前に剣士4、その後ろに弓兵3、最後尾に衛生兵、両脇に斥候
        let spots: [Vec] = [
            Vec(x: 260, y: 700), Vec(x: 180, y: 700), Vec(x: 340, y: 700), Vec(x: 420, y: 700),
            Vec(x: 300, y: 770), Vec(x: 200, y: 770), Vec(x: 400, y: 770),
            Vec(x: 300, y: 830),
            Vec(x: 80, y: 740), Vec(x: 520, y: 740)
        ]
        let enemyScale = enemyBase + Battle.enemyPerStage * Double(stage - 1)

        for (index, original) in Roster.allies.enumerated() {
            let member = plainAllies
                ? Member(name: original.name, role: original.role, personality: .loyal)
                : original
            let captain = index == 0
            let hp = member.role.maxHP * (captain ? 1.3 : 1)
            units.append(Unit(
                id: index, member: member, side: .ally, isCaptain: captain,
                maxHP: hp, power: 1, pos: spots[index], hp: hp
            ))
        }
        for (index, member) in Roster.enemies.enumerated() {
            let captain = index == 0
            let hp = member.role.maxHP * (captain ? 1.3 : 1) * enemyScale
            let spot = Vec(x: spots[index].x, y: Battle.height - spots[index].y)
            units.append(Unit(
                id: Roster.allies.count + index, member: member, side: .enemy, isCaptain: captain,
                maxHP: hp, power: enemyScale, pos: spot, hp: hp
            ))
        }
    }

    var allies: [Unit] { units.filter { $0.side == .ally } }
    var enemies: [Unit] { units.filter { $0.side == .enemy } }

    func aliveCount(_ side: Side) -> Int {
        units.filter { $0.side == side && $0.alive }.count
    }

    // MARK: - 指示を受け取る

    /// 味方に指示を伝える。隊員がどう受け取ったかを、記録用の文で返す。
    mutating func apply(_ commands: [Command]) -> [String] {
        var lines: [String] = []
        for command in commands {
            var plain: [String] = []
            for index in units.indices where units[index].side == .ally && units[index].alive {
                let targeted = command.targets.contains(units[index].id)
                // 早とちりは、ほかの人への指示も自分のことだと思い込む
                let overheard = !targeted && units[index].member.personality == .hasty
                guard targeted || overheard else { continue }
                if let reaction = receive(index, command, overheard: overheard) {
                    lines.append(reaction)
                } else {
                    plain.append(units[index].member.name)
                }
            }
            if !plain.isEmpty {
                let names = plain.count == Roster.allies.count ? "全員" : plain.joined(separator: "、")
                lines.append("\(names)：\(command.summary)")
            }
        }
        return lines
    }

    /// 1人が指示を受け取る。性格による変わった受け取り方をしたら、その説明を返す。
    private mutating func receive(_ index: Int, _ command: Command, overheard: Bool) -> String? {
        let name = units[index].member.name
        var move = command.move
        var engage = command.engage
        var reaction: String?

        if command.tone != .neutral {
            units[index].tone = command.tone
            units[index].toneUntil = time + 30
        }

        switch units[index].member.personality {
        case .contrary:
            if command.tone == .polite {
                reaction = "\(name)：\(command.summary)…素直にうなずいた"
            } else {
                move = move.map { Battle.opposite($0) }
                engage = engage.map { Battle.opposite($0) }
                reaction = "\(name)：わざと逆のことを始めた"
            }
        case .hasty:
            if move == .left {
                move = .right
                reaction = "\(name)：左と右を取り違えた"
            } else if move == .right {
                move = .left
                reaction = "\(name)：左と右を取り違えた"
            }
            if overheard {
                reaction = "\(name)：自分への指示だと思い込んだ"
            }
        case .timid:
            if command.tone == .strict {
                units[index].freezeUntil = time + 3
                reaction = "\(name)：きつく言われてすくんでしまった"
            } else if command.tone == .encourage {
                reaction = "\(name)：\(command.summary)…勇気が出た"
            }
        case .moody:
            if command.tone == .strict {
                units[index].moodObeys = false
                units[index].moodNextRoll = time + 8
                units[index].wanderGoal = randomSpot()
                reaction = "\(name)：へそを曲げてしまった"
            } else if command.tone == .polite {
                units[index].moodObeys = true
                units[index].moodNextRoll = time + 30
                reaction = "\(name)：\(command.summary)…機嫌よく引き受けた"
            }
        case .slow:
            var next = units[index].pendingOrder ?? units[index].order
            if let move { next.move = move }
            if let engage { next.engage = engage }
            if let target = command.target { next.target = target }
            units[index].pendingOrder = next
            if command.tone == .strict {
                units[index].pendingAt = time + 1
                return "\(name)：\(command.summary)…急かされてあわてて動く"
            }
            units[index].pendingAt = time + 4
            return "\(name)：\(command.summary)…「いま行くよ」と言ったまま動かない"
        default:
            break
        }

        if let move { units[index].order.move = move }
        if let engage { units[index].order.engage = engage }
        if let target = command.target { units[index].order.target = target }
        return reaction
    }

    private static func opposite(_ move: Move) -> Move {
        switch move {
        case .forward: return .back
        case .back: return .forward
        case .left: return .right
        case .right: return .left
        case .hold: return .forward
        case .charge: return .back
        case .center: return .hold
        case .gather: return .hold
        }
    }

    private static func opposite(_ engage: Engage) -> Engage {
        switch engage {
        case .free: return .never
        case .never: return .free
        case .returnFire: return .returnFire
        }
    }

    private mutating func randomSpot() -> Vec {
        Vec(
            x: Double.random(in: 60...(Battle.width - 60), using: &rng),
            y: Double.random(in: 350...(Battle.height - 60), using: &rng)
        )
    }

    // MARK: - 時間を進める

    /// 性格を踏まえた、その瞬間の実際の動き方。
    private struct Plan {
        var order: Order
        /// 指示とは別に向かう先（助けに行く、ふらふらする）
        var goal: Vec?
        /// 必ず狙う相手（目立ちたがりが狙う隊長）
        var fixedTarget: Int?
    }

    mutating func step(_ dt: Double) {
        guard outcome == nil else { return }
        time += dt
        runEnemyScript()

        // 遅れて動き出す指示、気分の変わり目
        for index in units.indices where units[index].alive {
            if let pending = units[index].pendingOrder, time >= units[index].pendingAt {
                units[index].order = pending
                units[index].pendingOrder = nil
            }
            if units[index].member.personality == .moody, time >= units[index].moodNextRoll {
                units[index].moodObeys = Double.random(in: 0..<1, using: &rng) < 0.55
                units[index].moodNextRoll = time + 6
                units[index].wanderGoal = randomSpot()
            }
        }

        for index in units.indices where units[index].alive {
            act(index, dt)
        }
        separate()
        shots.removeAll { time - $0.born > 0.25 }
        judge()
    }

    private func livingIndices(_ side: Side) -> [Int] {
        units.indices.filter { units[$0].side == side && units[$0].alive }
    }

    private func nearest(of candidates: [Int], to pos: Vec) -> Int? {
        candidates.min { units[$0].pos.distance(to: pos) < units[$1].pos.distance(to: pos) }
    }

    private func plan(for index: Int, foes: [Int], friends: [Int]) -> Plan {
        let unit = units[index]
        var plan = Plan(order: unit.order)
        let tone: Tone = time < unit.toneUntil ? unit.tone : .neutral
        let nearestFoe = nearest(of: foes, to: unit.pos)
        let nearestDistance = nearestFoe.map { units[$0].pos.distance(to: unit.pos) } ?? .infinity

        switch unit.member.personality {
        case .reckless:
            if tone != .strict {
                plan.order.engage = .free
                if nearestDistance < 260 { plan.order.move = .charge }
            }
        case .timid:
            if tone != .encourage {
                let foesNear = foes.filter { units[$0].pos.distance(to: unit.pos) < 150 }.count
                let friendsNear = friends.filter { units[$0].pos.distance(to: unit.pos) < 150 }.count
                if unit.hp < unit.maxHP * 0.5 || foesNear > friendsNear {
                    plan.order.move = .back
                    plan.order.engage = .returnFire
                }
            }
        case .caring:
            let hurt = friends.filter { $0 != index && units[$0].hp < units[$0].maxHP * 0.45 }
            if let target = nearest(of: hurt, to: unit.pos),
               units[target].pos.distance(to: unit.pos) > unit.role.range * 0.8 {
                plan.goal = units[target].pos
            }
        case .cautious:
            if tone != .strict {
                if nearestDistance < unit.role.range * 0.7 {
                    plan.order.move = .back
                } else if nearestDistance < unit.role.range,
                          plan.order.move == .forward || plan.order.move == .charge {
                    plan.order.move = .hold
                }
            }
        case .moody:
            if !unit.moodObeys {
                plan.goal = unit.wanderGoal
                plan.order.engage = .returnFire
            }
        case .showy:
            if tone != .encourage,
               let captain = foes.first(where: { units[$0].isCaptain }),
               units[captain].pos.distance(to: unit.pos) < 380 {
                plan.fixedTarget = captain
                plan.order.move = .charge
                plan.order.engage = .free
            }
        default:
            break
        }

        if time < unit.freezeUntil {
            plan.order.move = .hold
            plan.order.engage = .never
            plan.goal = nil
        }
        return plan
    }

    /// 向かっていく相手を、狙い方の指示に沿って選ぶ。
    private func preferredTarget(for index: Int, plan: Plan, foes: [Int]) -> Int? {
        if let fixed = plan.fixedTarget { return fixed }
        let pos = units[index].pos
        switch plan.order.target {
        case .nearest:
            return nearest(of: foes, to: pos)
        case .weakest:
            let close = foes.filter { units[$0].pos.distance(to: pos) < 300 }
            return close.min { units[$0].hp < units[$1].hp } ?? nearest(of: foes, to: pos)
        case .archer:
            return nearest(of: foes.filter { units[$0].role == .archer }, to: pos) ?? nearest(of: foes, to: pos)
        case .medic:
            return nearest(of: foes.filter { units[$0].role == .medic }, to: pos) ?? nearest(of: foes, to: pos)
        }
    }

    private mutating func act(_ index: Int, _ dt: Double) {
        let unit = units[index]
        let foes = livingIndices(unit.side == .ally ? .enemy : .ally)
        let friends = livingIndices(unit.side)
        let plan = self.plan(for: index, foes: foes, friends: friends)
        let range = unit.role.range
        units[index].cooldown = max(0, unit.cooldown - dt)

        // 衛生兵は攻撃せず、届く範囲でいちばん傷の深い仲間を治す
        if unit.role == .medic {
            if units[index].cooldown <= 0 {
                let inReach = friends.filter {
                    $0 != index && units[$0].hp < units[$0].maxHP && units[$0].pos.distance(to: unit.pos) <= range
                }
                if let patient = inReach.min(by: { units[$0].hp / units[$0].maxHP < units[$1].hp / units[$1].maxHP }) {
                    units[patient].hp = min(units[patient].maxHP, units[patient].hp + unit.role.damage * unit.power)
                    units[index].cooldown = unit.role.cooldown
                    shots.append(Shot(from: unit.pos, to: units[patient].pos, born: time, heal: true))
                }
            }
            move(index, plan: plan, chase: nil, fighting: false, dt: dt)
            return
        }

        // 攻撃してよいか
        var mayAttack = plan.order.engage == .free
        var preferred = preferredTarget(for: index, plan: plan, foes: foes)
        if plan.order.engage == .returnFire, time - unit.lastHitAt < 4,
           let attacker = unit.lastAttacker, units[attacker].alive {
            mayAttack = true
            preferred = attacker
        }

        // 実際に攻撃する相手：狙いたい相手が届かなければ、届く中でいちばん近い敵
        var victim: Int?
        if mayAttack {
            if let preferred, units[preferred].pos.distance(to: unit.pos) <= range {
                victim = preferred
            } else {
                victim = nearest(of: foes.filter { units[$0].pos.distance(to: unit.pos) <= range }, to: unit.pos)
            }
        }
        if let victim, units[index].cooldown <= 0 {
            let amount = unit.role.damage * unit.power * Double.random(in: 0.85...1.15, using: &rng)
            units[victim].hp -= amount
            units[victim].lastAttacker = index
            units[victim].lastHitAt = time
            units[index].cooldown = unit.role.cooldown
            if unit.role == .archer {
                shots.append(Shot(from: unit.pos, to: units[victim].pos, born: time, heal: false))
            }
        }

        move(index, plan: plan, chase: mayAttack ? preferred : nil, fighting: victim != nil, dt: dt)
    }

    /// 動く。chase は向かっていく相手、fighting はいま攻撃が届く相手がいるか。
    private mutating func move(_ index: Int, plan: Plan, chase: Int?, fighting: Bool, dt: Double) {
        let unit = units[index]
        let range = unit.role.range
        let forward: Double = unit.side == .ally ? -1 : 1
        let homeY = unit.side == .ally ? Battle.height - 50 : 50
        var destination: Vec?
        var stopWithin = 4.0

        if let goal = plan.goal {
            destination = goal
            // 助けに行くときは、回復が届く所で止まる
            stopWithin = unit.role == .medic ? unit.role.range * 0.7 : 30
        } else {
            switch plan.order.move {
            case .hold:
                break
            case .forward:
                if fighting {
                    break
                }
                // 近くに敵が来たら、そちらへ向かって戦う
                if let chase, units[chase].pos.distance(to: unit.pos) < max(range, 120) {
                    destination = units[chase].pos
                    stopWithin = range * 0.9
                } else {
                    // まだ前に敵がいる間はまっすぐ進む。前にいなくなったら、残った敵を探しに行く
                    let foes = livingIndices(unit.side == .ally ? .enemy : .ally)
                    let anyAhead = foes.contains { (units[$0].pos.y - unit.pos.y) * forward > 10 }
                    if anyAhead || chase == nil {
                        destination = Vec(x: unit.pos.x, y: unit.side == .ally ? 50 : Battle.height - 50)
                    } else if let chase {
                        destination = units[chase].pos
                        stopWithin = range * 0.9
                    }
                }
            case .charge:
                if fighting {
                    break
                }
                let foes = livingIndices(unit.side == .ally ? .enemy : .ally)
                if let target = chase ?? nearest(of: foes, to: unit.pos) {
                    destination = units[target].pos
                    stopWithin = chase == nil ? 80 : range * 0.9
                }
            case .back:
                destination = Vec(x: unit.pos.x, y: homeY)
            case .left:
                destination = Vec(x: 50, y: unit.pos.y)
            case .right:
                destination = Vec(x: Battle.width - 50, y: unit.pos.y)
            case .center:
                destination = Vec(x: Battle.width / 2, y: Battle.height / 2)
                stopWithin = 30
            case .gather:
                if let captain = units.firstIndex(where: { $0.side == unit.side && $0.isCaptain && $0.alive }),
                   captain != index {
                    destination = units[captain].pos + Vec(x: 0, y: -forward * 50)
                    stopWithin = 30
                }
            }
        }

        guard let destination else { return }
        let offset = destination - unit.pos
        if offset.length <= stopWithin { return }
        let speed = unit.role.speed * (unit.member.personality == .slow ? 0.75 : 1)
        let stride = min(speed * dt, offset.length - stopWithin)
        var next = unit.pos + offset.unit * stride
        next.x = min(max(next.x, 20), Battle.width - 20)
        next.y = min(max(next.y, 20), Battle.height - 20)
        units[index].pos = next
    }

    /// 重なった人どうしを少し押し離す。
    private mutating func separate() {
        let minimum = 20.0
        for a in units.indices where units[a].alive {
            for b in units.indices where b > a && units[b].alive {
                let offset = units[b].pos - units[a].pos
                let distance = offset.length
                if distance < minimum {
                    let push = distance > 0.01 ? offset.unit : Vec(x: 1, y: 0)
                    let amount = (minimum - distance) / 2
                    units[a].pos = units[a].pos - push * amount
                    units[b].pos = units[b].pos + push * amount
                }
            }
        }
    }

    private mutating func judge() {
        let alliesLeft = aliveCount(.ally)
        let enemiesLeft = aliveCount(.enemy)
        if enemiesLeft == 0 && alliesLeft == 0 {
            outcome = .draw
        } else if enemiesLeft == 0 {
            outcome = .win
        } else if alliesLeft == 0 {
            outcome = .lose
        } else if time >= Battle.timeLimit {
            // 時間切れ：残った体力の割合で決める
            let allyShare = allies.reduce(0) { $0 + max(0, $1.hp) } / allies.reduce(0) { $0 + $1.maxHP }
            let enemyShare = enemies.reduce(0) { $0 + max(0, $1.hp) } / enemies.reduce(0) { $0 + $1.maxHP }
            outcome = allyShare > enemyShare ? .win : (allyShare < enemyShare ? .lose : .draw)
        }
    }

    // MARK: - 敵の動き

    /// 敵は全員が指示どおりに動く。ステージごとに作戦を変える。
    private mutating func runEnemyScript() {
        func set(_ roles: [Role], _ move: Move, _ engage: Engage = .free, _ target: TargetPref = .nearest) {
            for index in units.indices where units[index].side == .enemy && roles.contains(units[index].role) {
                units[index].order = Order(move: move, engage: engage, target: target)
            }
        }
        switch (stage - 1) % 3 {
        case 0:
            // 正面から押す
            if enemyStep == 0, time >= 3 {
                set([.sword, .scout, .archer], .forward)
                set([.medic], .gather)
                enemyStep = 1
            }
        case 1:
            // 守って引きつけ、弱った相手から倒す。しびれを切らしたら攻める
            if enemyStep == 0 {
                set([.sword, .scout, .archer], .hold, .free, .weakest)
                set([.medic], .gather)
                enemyStep = 1
            } else if enemyStep == 1, time >= 30 {
                set([.sword, .scout, .archer], .charge, .free, .weakest)
                enemyStep = 2
            }
        default:
            // 斥候が弓兵を襲い、そのあと本隊が来る
            if enemyStep == 0, time >= 2 {
                set([.scout], .charge, .free, .archer)
                set([.medic], .gather)
                enemyStep = 1
            } else if enemyStep == 1, time >= 6 {
                set([.sword, .archer], .forward)
                enemyStep = 2
            }
        }
    }
}
