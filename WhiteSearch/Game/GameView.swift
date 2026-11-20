import SwiftUI
import UIKit

/// ゲームの画面。見た目は仮で、遊べることの確認だけを目的にしている。
struct GameView: View {
    @StateObject private var model = GameModel()
    @State private var input = ""
    @State private var showingRoster = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            FieldView(battle: model.battle)
                .overlay { resultOverlay }
            logArea
            inputArea
        }
        .background(Color.white)
        .onChange(of: inputFocused) { _, focused in
            model.isTyping = focused
        }
        .sheet(isPresented: $showingRoster) {
            RosterView(interpreterName: model.interpreterName) {
                showingRoster = false
                model.resetAll()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("ステージ \(model.stage)")
                .font(.headline)
                .foregroundStyle(Color.black)
            Text("味方 \(model.battle.aliveCount(.ally))　敵 \(model.battle.aliveCount(.enemy))")
                .font(.subheadline)
                .foregroundStyle(Color.gray)
            Spacer()
            Button("隊員") { showingRoster = true }
                .font(.subheadline)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var resultOverlay: some View {
        if let outcome = model.battle.outcome {
            VStack(spacing: 16) {
                Text(title(for: outcome))
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Color.black)
                Button(outcome == .win ? "次のステージへ" : "もう一度") {
                    model.restart()
                }
                .frame(minHeight: 44)
            }
            .padding(32)
            .background(Color.white.opacity(0.92))
        } else if !model.started {
            Text("指示を書くと戦いが始まります\n下が味方、上が敵。「隊員」で指示の出し方を確かめられます")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.gray)
                .padding(16)
                .background(Color.white.opacity(0.92))
        } else if model.isTyping || model.isInterpreting {
            Text(model.isInterpreting ? "指示を伝えています…" : "指示を書いている間、戦いは止まります")
                .font(.footnote)
                .foregroundStyle(Color.gray)
                .padding(12)
                .background(Color.white.opacity(0.92))
        }
    }

    private func title(for outcome: Outcome) -> String {
        switch outcome {
        case .win: return "勝ち"
        case .lose: return "負け"
        case .draw: return "引き分け"
        }
    }

    /// 指示がどう伝わったかの記録。新しいものが下。
    private var logArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.log.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(line.hasPrefix("▶") ? Color.black : Color.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 84)
            .onChange(of: model.log.count) { _, count in
                if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
    }

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("指示を書く（例：全員、前進して攻撃）", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .font(.body)
                .foregroundStyle(Color.black)
                .focused($inputFocused)
                .submitLabel(.send)
                .onChange(of: input) { _, newValue in
                    // 改行キーで送る
                    if newValue.contains("\n") {
                        input = newValue.replacingOccurrences(of: "\n", with: "")
                        submit()
                    }
                }
            Button("伝える") { submit() }
                .frame(minHeight: 44)
                .disabled(model.isInterpreting || model.battle.outcome != nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func submit() {
        let text = input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        input = ""
        inputFocused = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await model.send(text) }
    }
}

/// 戦場。下が味方、上が敵。
struct FieldView: View {
    let battle: Battle

    private let allyColor = Color.indigo
    private let enemyColor = Color(red: 0.75, green: 0.2, blue: 0.2)

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / Battle.width, size.height / Battle.height)
            let offsetX = (size.width - Battle.width * scale) / 2
            let offsetY = (size.height - Battle.height * scale) / 2
            func point(_ v: Vec) -> CGPoint {
                CGPoint(x: offsetX + v.x * scale, y: offsetY + v.y * scale)
            }

            // 戦場の枠
            let frame = CGRect(x: offsetX, y: offsetY, width: Battle.width * scale, height: Battle.height * scale)
            context.stroke(Path(frame), with: .color(Color.gray.opacity(0.3)), lineWidth: 1)

            // 矢と回復の線
            for shot in battle.shots {
                var path = Path()
                path.move(to: point(shot.from))
                path.addLine(to: point(shot.to))
                context.stroke(path, with: .color(shot.heal ? Color.green.opacity(0.6) : Color.black.opacity(0.4)), lineWidth: 1)
            }

            let radius = max(9.0, 13.0 * scale)
            for unit in battle.units where unit.alive {
                let center = point(unit.pos)
                let color = unit.side == .ally ? allyColor : enemyColor
                let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: circle), with: .color(color))
                if unit.isCaptain {
                    context.stroke(Path(ellipseIn: circle.insetBy(dx: -3, dy: -3)), with: .color(color), lineWidth: 1.5)
                }
                context.draw(
                    Text(unit.role.mark).font(.system(size: radius)).foregroundColor(.white),
                    at: center
                )

                // 体力
                let barWidth = radius * 2.4
                let ratio = max(0, min(1, unit.hp / unit.maxHP))
                let barOrigin = CGPoint(x: center.x - barWidth / 2, y: center.y + radius + 3)
                context.fill(
                    Path(CGRect(x: barOrigin.x, y: barOrigin.y, width: barWidth, height: 3)),
                    with: .color(Color.gray.opacity(0.3))
                )
                context.fill(
                    Path(CGRect(x: barOrigin.x, y: barOrigin.y, width: barWidth * ratio, height: 3)),
                    with: .color(color)
                )

                // 味方は名前を出す
                if unit.side == .ally {
                    context.draw(
                        Text(unit.member.name).font(.system(size: 10)).foregroundColor(.black),
                        at: CGPoint(x: center.x, y: center.y - radius - 8)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("戦場。味方\(battle.aliveCount(.ally))人、敵\(battle.aliveCount(.enemy))人")
    }
}

/// 隊員の一覧と、指示の出し方。
struct RosterView: View {
    let interpreterName: String
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("隊員") {
                    ForEach(Array(Roster.allies.enumerated()), id: \.offset) { index, member in
                        Text("\(member.name)　\(member.role.rawValue)\(index == 0 ? "（隊長）" : "")")
                            .font(.subheadline)
                    }
                }
                Section {
                    Text("名前や役割で相手を選べます（例：ゴウは待機。弓兵は下がれ。レン以外は前進）")
                    Text("動き：前進、後退、左へ、右へ、中央へ、待機、突撃、集合")
                    Text("敵の扱い：攻撃する、反撃だけ、攻撃しない")
                    Text("狙い：近い敵、弱った敵、敵の弓兵、敵の衛生兵")
                } header: {
                    Text("指示の出し方")
                }
                .font(.footnote)
                Section("状態") {
                    LabeledContent("指示の読み取り", value: interpreterName)
                    Button("最初のステージからやり直す", role: .destructive) { onReset() }
                }
            }
            .navigationTitle("部隊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
