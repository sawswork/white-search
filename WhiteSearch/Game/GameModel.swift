import Foundation
import SwiftUI

/// 戦いの進行、指示の受け渡し、記録をまとめて持つ。
@MainActor
final class GameModel: ObservableObject {
    @Published private(set) var battle: Battle
    @Published private(set) var stage = 1
    /// 指示がどう伝わったかの記録（新しいものが後ろ）
    @Published private(set) var log: [String] = []
    /// 指示を読み取っている最中か
    @Published private(set) var isInterpreting = false
    /// 最初の指示を出すまでは戦いを始めない
    @Published private(set) var started = false
    /// 指示を書いている間は戦いを止める
    @Published var isTyping = false

    private let interpreter: any OrderInterpreter = makeInterpreter()
    private var timer: Timer?

    var interpreterName: String { interpreter.name }

    init() {
        battle = Battle(stage: 1, seed: UInt64.random(in: 0...UInt64.max))
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard started, !isTyping, !isInterpreting, battle.outcome == nil else { return }
        battle.step(1.0 / 30.0)
    }

    /// 書いた指示を読み取って、部隊に伝える。
    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isInterpreting, battle.outcome == nil else { return }
        isInterpreting = true
        let commands = await interpreter.interpret(trimmed, roster: Roster.allies)
        isInterpreting = false

        log.append("▶ " + trimmed)
        if commands.isEmpty {
            log.append("（だれにも伝わらなかった）")
        } else {
            log.append(contentsOf: battle.apply(commands))
        }
        if log.count > 60 { log.removeFirst(log.count - 60) }
        started = true
    }

    /// 同じステージをやり直す。勝っていたら次のステージへ進む。
    func restart() {
        if battle.outcome == .win { stage += 1 }
        battle = Battle(stage: stage, seed: UInt64.random(in: 0...UInt64.max))
        log = []
        started = false
    }

    /// 最初のステージからやり直す。
    func resetAll() {
        stage = 1
        battle = Battle(stage: 1, seed: UInt64.random(in: 0...UInt64.max))
        log = []
        started = false
    }
}
