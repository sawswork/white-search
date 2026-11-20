import Foundation

// 強さの調整用。画面なしで戦いを何度も回し、指示の出し方ごとの勝率を出す。
// 使い方は .github/workflows/sim.yml を参照。

struct Strategy {
    let name: String
    /// （伝える時刻, 指示の文）
    let script: [(Double, String)]
}

let strategies: [Strategy] = [
    Strategy(name: "何も指示しない", script: []),
    Strategy(name: "全員前進して攻撃", script: [(0, "全員前進して攻撃")]),
    Strategy(name: "全員突撃", script: [(0, "全員突撃")]),
    Strategy(name: "全員待機", script: [(0, "全員待機して攻撃")]),
    Strategy(name: "性格に合わせる", script: [
        (0, """
        ハヤトは前進して攻撃。ゴウは前進して攻撃。レンは下がって攻撃するな。\
        ダイチは今すぐ前進して攻撃。ミオは前進して攻撃。ソラは大丈夫、前進して攻撃。\
        カイはさすが、前進して弱った敵を攻撃。ユイは集合。アキはお願い、前進して攻撃。\
        ナギは前進して敵の弓兵を攻撃
        """),
        (28, "ソラは頼りにしてる、攻撃。カイはいいぞ、弱った敵を攻撃。アキはお願い、突撃"),
        (56, "ソラは頼りにしてる、攻撃。カイはいいぞ、弱った敵を攻撃。アキはお願い、突撃")
    ]),
    Strategy(name: "性格に合わせて守る", script: [
        (0, """
        ハヤトは待機して攻撃。ゴウは絶対、待機して攻撃。レンは突撃して攻撃するな。\
        ダイチは待機して攻撃。ミオは待機して攻撃。ソラは大丈夫、待機して攻撃。\
        カイはさすが、待機して弱った敵を攻撃。ユイは集合。アキはお願い、集合して攻撃。\
        ナギは集合して攻撃
        """),
        (14, "ゴウは絶対、待機。ソラは頼りにしてる、攻撃。カイはいいぞ、弱った敵を攻撃。アキはお願い、攻撃"),
        (28, "ゴウは絶対、待機。ソラは頼りにしてる、攻撃。カイはいいぞ、弱った敵を攻撃。アキはお願い、攻撃"),
        (40, "全員突撃。レンは下がって攻撃するな。ソラは大丈夫、攻撃。アキはお願い、突撃")
    ])
]

let trials = 100

func run(_ strategy: Strategy, stage: Int, seed: UInt64, enemyBase: Double, plain: Bool) -> (Outcome, Int, Int, Double) {
    var battle = Battle(stage: stage, seed: seed, enemyBase: enemyBase, plainAllies: plain)
    var next = 0
    while battle.outcome == nil {
        while next < strategy.script.count, battle.time >= strategy.script[next].0 {
            let commands = CommandParser.parse(strategy.script[next].1, roster: Roster.allies)
            _ = battle.apply(commands)
            next += 1
        }
        battle.step(1.0 / 30.0)
    }
    return (battle.outcome!, battle.aliveCount(.ally), battle.aliveCount(.enemy), battle.time)
}

func report(_ strategy: Strategy, stage: Int, enemyBase: Double, plain: Bool) {
    var wins = 0, losses = 0, alliesLeft = 0, enemiesLeft = 0
    var seconds = 0.0
    for trial in 0..<trials {
        let result = run(strategy, stage: stage, seed: UInt64(trial * 7919 + stage), enemyBase: enemyBase, plain: plain)
        if result.0 == .win { wins += 1 }
        if result.0 == .lose { losses += 1 }
        alliesLeft += result.1
        enemiesLeft += result.2
        seconds += result.3
    }
    let n = Double(trials)
    print(String(
        format: "勝ち %3d%%  負け %3d%%  味方残 %.1f  敵残 %.1f  %3.0f秒  ",
        wins * 100 / trials, losses * 100 / trials,
        Double(alliesLeft) / n, Double(enemiesLeft) / n, seconds / n
    ) + strategy.name + (plain ? "（味方も全員忠実）" : ""))
}

// 仕組みが公平か：味方も全員忠実なら、同じ指示で五分に近いはず
print("== 公平さの確認（ステージ1、敵の倍率1.0） ==")
report(strategies[1], stage: 1, enemyBase: 1.0, plain: true)
report(strategies[2], stage: 1, enemyBase: 1.0, plain: true)

for stage in 1...6 {
    print("== ステージ \(stage) ==")
    for strategy in strategies {
        report(strategy, stage: stage, enemyBase: Battle.enemyBase, plain: false)
    }
}
