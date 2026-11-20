import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// AIへの1回の依頼。
struct SearchRequest {
    var question: String
    /// 問いに添えた画像（JPEG）。なければ nil。
    var imageData: Data?
    /// これまでに選んだトピック。
    var path: [String]
    /// 出し直しのとき、避けたい候補。
    var avoid: [String] = []
}

struct TopicResult {
    var topics: [String]
    /// これ以上絞らなくても答えられるなら true。
    var canAnswer: Bool
}

struct AnswerResult {
    var headline: String
    var points: [String]
    /// 手持ちの知識では答えられない問い（最新の出来事、価格、営業時間など）なら false。
    var answerable = true
}

/// AIの差し替え口。
protocol SearchEngine {
    var name: String { get }
    var supportsImages: Bool { get }
    func topics(_ request: SearchRequest) async throws -> TopicResult
    func answer(_ request: SearchRequest) async throws -> AnswerResult
}

/// ふだん使うエンジン。端末内AIが使えるならそれを、使えなければ仮データを返す。
func makeEngine() -> any SearchEngine {
    #if canImport(FoundationModels)
    #if IOS27_SDK
    if #available(iOS 27.0, *), OnDeviceEngine.isAvailable {
        return VisionOnDeviceEngine()
    }
    #endif
    if #available(iOS 26.0, *), OnDeviceEngine.isAvailable {
        return OnDeviceEngine()
    }
    #endif
    return MockEngine()
}

/// 「もっと詳しく」で使うエンジン。使えない環境では nil。
///
/// PCC_ENTITLEMENT は、Apple から Private Cloud Compute の権限が下りてから project.yml で有効にする。
/// 権限のないアプリがクラウドに問いを送ると落ちるうえ、実行時には権限の有無を確かめられないため、
/// ビルド時のこの条件で確実に切り離している。無効の間は「もっと詳しく」は画面に出ず、通信も起きない。
func makeDetailEngine() -> (any SearchEngine)? {
    #if canImport(FoundationModels) && IOS27_SDK && PCC_ENTITLEMENT
    if #available(iOS 27.0, *), CloudEngine.isAvailable {
        return CloudEngine()
    }
    #endif
    return nil
}

enum Prompts {
    static let instructions = """
    あなたは検索を絞り込む案内役です。必ず日本語で答えます。\
    余計な前置きや関連情報は出さず、聞かれたことだけに答えます。\
    相手が本当に知りたいことを見きわめ、その1つにだけ答えることが役目です。
    """

    /// 階層ごとに、何で分けるかを変える。人が相談に乗るときの順番（目的 → 状況 → 範囲）に合わせる。
    private static func stage(_ depth: Int) -> String {
        let focus: String
        switch depth {
        case 0: focus = "何のために知りたいのか（目的）"
        case 1: focus = "どんな状況や条件なのか"
        default: focus = "どの部分を、どこまで知りたいのか（範囲）"
        }
        return "今回は「\(focus)」で分けるのを基本にします。"
            + "この問いに合わなければ、答えが最も大きく変わる分かれ目を選んでください。"
    }

    static func topics(_ request: SearchRequest) -> String {
        var prompt = "問い: \(request.question)\n"
        if request.imageData != nil {
            prompt += "問いには画像が添えられています。画像の内容を踏まえてください。\n"
        }
        if !request.path.isEmpty {
            prompt += "これまでに選んだ絞り込み: \(request.path.joined(separator: " → "))\n"
        }
        // 先に答えの候補を考えさせ、そこから逆算して選択肢を作らせる
        prompt += "まず、この問いへのありうる答えを、互いに違うものとして考えてください。"
        prompt += "次に、そのどれが合うかを見分けるための選択肢を出してください。"
        prompt += "選択肢は、どれを選ぶかで答えが変わる分かれ目だけにします。話題の分類や目次にはしないでください。"
        prompt += "選択肢同士は意味が重ならず、同じ細かさにそろえてください。\n"
        prompt += stage(request.path.count)
        if !request.avoid.isEmpty {
            prompt += "\n次の候補は出さないでください: \(request.avoid.joined(separator: "、"))"
        }
        return prompt
    }

    static func answer(_ request: SearchRequest, detailed: Bool) -> String {
        var prompt = "問い: \(request.question)\n"
        if request.imageData != nil {
            prompt += "問いには画像が添えられています。画像の内容を踏まえてください。\n"
        }
        if !request.path.isEmpty {
            prompt += "絞り込み: \(request.path.joined(separator: " → "))\n"
        }
        prompt += "この絞り込みに沿って、問いに答えてください。確かでないことは書かないでください。"
        prompt += "結論は、絞り込みの内容を前提として織り込んだ、この相手のための1文にしてください。"
        prompt += "要点は結論を支えるものだけにし、結論と関係のない情報は足さないでください。"
        prompt += "最新の出来事、いまの価格、営業時間など、現在の情報がないと答えられない問いなら、答えられないと判断してください。"
        if detailed {
            prompt += "要点は理由や具体的な数値も含めて、詳しく書いてください。"
        }
        return prompt
    }
}

// MARK: - 仮データ（端末内AIが使えない環境で流れを確かめるためのもの）

struct MockEngine: SearchEngine {
    let name = "仮データ"
    let supportsImages = true

    func topics(_ request: SearchRequest) async throws -> TopicResult {
        try await Task.sleep(nanoseconds: 400_000_000)
        let base = request.path.last ?? request.question
        let round = request.avoid.isEmpty ? "" : "・別案"
        let topics = [
            "\(base)の基本\(round)",
            "\(base)の具体例\(round)",
            "\(base)の注意点\(round)",
            "\(base)の比較\(round)"
        ]
        return TopicResult(topics: topics, canAnswer: request.path.count >= 2)
    }

    func answer(_ request: SearchRequest) async throws -> AnswerResult {
        try await Task.sleep(nanoseconds: 400_000_000)
        return AnswerResult(
            headline: "（仮の答え）\(request.path.last ?? request.question)",
            points: [
                "これは仮データです。",
                "問い: \(request.question)" + (request.imageData == nil ? "" : "（画像つき）"),
                "たどった道: \(request.path.joined(separator: " → "))"
            ]
        )
    }
}

// MARK: - 端末内AI（Apple Foundation Models、文字のみ）

#if canImport(FoundationModels)

// 項目は上から順に生成される。先に考えさせたいものを上に置いている。

@available(iOS 26.0, *)
@Generable
struct GeneratedTopics {
    @Guide(description: "この問いへのありうる答え。互いに違うものを、それぞれ20文字以内の日本語で。答えが1つに決まるなら1つだけ。", .count(1...5))
    var answers: [String]

    @Guide(description: "ありうる答えのどれが合うかを見分けるための選択肢。どれを選ぶかで答えが変わる分かれ目だけ。互いに意味が重ならない、15文字以内の短い日本語。", .count(3...5))
    var topics: [String]

    @Guide(description: "誰が聞いても答えが1つに決まるなら true。選択肢によって答えが変わるなら false。")
    var canAnswer: Bool
}

@available(iOS 26.0, *)
@Generable
struct GeneratedAnswer {
    @Guide(description: "手持ちの知識で確かに答えられるなら true。最新の出来事、いまの価格、営業時間など、現在の情報が必要なら false。")
    var answerable: Bool

    @Guide(description: "結論を1文で。絞り込みの内容を前提として織り込む。日本語。")
    var headline: String

    @Guide(description: "結論を支える要点。それぞれ1文の日本語。", .count(3...5))
    var points: [String]
}

@available(iOS 26.0, *)
struct OnDeviceEngine: SearchEngine {
    let name = "端末内AI"
    let supportsImages = false

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    func topics(_ request: SearchRequest) async throws -> TopicResult {
        // 階層ごとに新しいセッションを作り、渡す情報を最小限にする
        let session = LanguageModelSession(instructions: Prompts.instructions)
        let response = try await session.respond(
            to: Prompts.topics(request),
            generating: GeneratedTopics.self
        )
        return TopicResult(topics: response.content.topics, canAnswer: response.content.canAnswer)
    }

    func answer(_ request: SearchRequest) async throws -> AnswerResult {
        let session = LanguageModelSession(instructions: Prompts.instructions)
        let response = try await session.respond(
            to: Prompts.answer(request, detailed: false),
            generating: GeneratedAnswer.self
        )
        return AnswerResult(
            headline: response.content.headline,
            points: response.content.points,
            answerable: response.content.answerable
        )
    }
}

#endif
