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
    余計な前置きや関連情報は出さず、聞かれたことだけに答えます。
    """

    static func topics(_ request: SearchRequest) -> String {
        var prompt = "問い: \(request.question)\n"
        if request.imageData != nil {
            prompt += "問いには画像が添えられています。画像の内容を踏まえてください。\n"
        }
        if !request.path.isEmpty {
            prompt += "これまでに選んだ絞り込み: \(request.path.joined(separator: " → "))\n"
        }
        prompt += "この問いに的確に答えるために、次に選ぶべき観点を出してください。"
        prompt += "観点同士は意味が重ならず、同じ細かさにそろえてください。"
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

@available(iOS 26.0, *)
@Generable
struct GeneratedTopics {
    @Guide(description: "問いをさらに絞り込むための観点。互いに意味が重ならない、15文字以内の短い日本語。", .count(3...5))
    var topics: [String]

    @Guide(description: "これ以上絞り込まなくても具体的に答えられるなら true。")
    var canAnswer: Bool
}

@available(iOS 26.0, *)
@Generable
struct GeneratedAnswer {
    @Guide(description: "結論を1文で。日本語。")
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
        return AnswerResult(headline: response.content.headline, points: response.content.points)
    }
}

#endif
