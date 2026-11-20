import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 書かれた言葉を、隊員への指示に直す係。
protocol OrderInterpreter {
    var name: String { get }
    func interpret(_ text: String, roster: [Member]) async -> [Command]
}

/// 使える中でいちばん賢い読み取り方を選ぶ。端末内AIが使えなければ、決まった語を拾う方式にする。
func makeInterpreter() -> any OrderInterpreter {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
        return OnDeviceInterpreter()
    }
    #endif
    return KeywordInterpreter()
}

/// 決まった語を拾う読み取り。端末内AIが使えない端末でも遊べるようにするためのもの。
struct KeywordInterpreter: OrderInterpreter {
    let name = "かんたん読み取り"

    func interpret(_ text: String, roster: [Member]) async -> [Command] {
        CommandParser.parse(text, roster: roster)
    }
}

#if canImport(FoundationModels)

@available(iOS 26.0, *)
@Generable
struct GeneratedCommand {
    @Guide(description: "この指示の対象。隊員の名前か、役割（剣士、弓兵、衛生兵、斥候）。全員なら「全員」だけを入れる。「〜以外」と書かれていたら、残りの隊員の名前をすべて書き出す。", .count(1...10))
    var targets: [String]

    @Guide(description: "動き。動きについて書かれていなければ「そのまま」。", .anyOf(["そのまま"] + Move.allCases.map(\.rawValue)))
    var move: String

    @Guide(description: "敵の扱い。書かれていなければ「そのまま」。", .anyOf(["そのまま"] + Engage.allCases.map(\.rawValue)))
    var engage: String

    @Guide(description: "狙う敵。書かれていなければ「そのまま」。", .anyOf(["そのまま"] + TargetPref.allCases.map(\.rawValue)))
    var target: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedCommands {
    @Guide(description: "指示を、対象ごとに分けたもの。書かれた順に並べる。", .count(1...10))
    var commands: [GeneratedCommand]
}

/// 端末内AI（Apple Foundation Models）による読み取り。通信はしない。
@available(iOS 26.0, *)
struct OnDeviceInterpreter: OrderInterpreter {
    let name = "端末内AI"

    private static let instructions = """
    あなたは、隊長が部隊に出した指示を読み取り、決まった形に直す係です。\
    書かれていないことは足しません。指示の良し悪しは判断せず、書かれたとおりに直します。
    """

    func interpret(_ text: String, roster: [Member]) async -> [Command] {
        let members = roster.map { "\($0.name)（\($0.role.rawValue)）" }.joined(separator: "、")
        let prompt = """
        隊員: \(members)
        隊長の指示: \(text)

        この指示を、対象ごとに分けて直してください。\
        動きの意味は次のとおりです。前進＝敵のほうへまっすぐ進む。後退＝自陣へ下がる。\
        突撃＝敵を追いかける。集合＝隊長のそばへ行く。待機＝その場から動かない。
        """
        do {
            // 指示ごとに新しいセッションを作り、前の指示を引きずらない
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(to: prompt, generating: GeneratedCommands.self)
            let commands = response.content.commands.compactMap { convert($0, roster: roster) }
            if !commands.isEmpty { return commands }
        } catch {
            // 読み取れなかったときは、下の決まった語を拾う方式に任せる
        }
        return CommandParser.parse(text, roster: roster)
    }

    private func convert(_ generated: GeneratedCommand, roster: [Member]) -> Command? {
        var targets = Set<Int>()
        for word in generated.targets {
            if word.contains("全員") {
                targets = Set(roster.indices)
                break
            }
            for (index, member) in roster.enumerated()
            where word.contains(member.name) || word.contains(member.role.rawValue) {
                targets.insert(index)
            }
        }
        if targets.isEmpty { targets = Set(roster.indices) }
        let command = Command(
            targets: targets,
            move: Move(rawValue: generated.move),
            engage: Engage(rawValue: generated.engage),
            target: TargetPref(rawValue: generated.target)
        )
        return command.hasAction ? command : nil
    }
}

#endif
