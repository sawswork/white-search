// iOS 27 で加わった機能（画像つきの問い、Appleのクラウド）を使う部分。
// project.yml で IOS27_SDK を有効にしたときだけビルドされる。
// 書き方は Apple の公式文書（developer.apple.com/documentation/foundationmodels）に合わせてある。
#if canImport(FoundationModels) && IOS27_SDK
import Foundation
import FoundationModels
import UIKit

@available(iOS 27.0, *)
private func cgImage(from data: Data?) -> CGImage? {
    guard let data else { return nil }
    return UIImage(data: data)?.cgImage
}

@available(iOS 27.0, *)
private func generate<T: Generable>(
    _ type: T.Type,
    session: LanguageModelSession,
    prompt: String,
    imageData: Data?
) async throws -> T {
    if let image = cgImage(from: imageData) {
        let response = try await session.respond(generating: type) {
            prompt
            Attachment(image)
        }
        return response.content
    }
    let response = try await session.respond(to: prompt, generating: type)
    return response.content
}

/// 端末内AI（画像にも対応）。
@available(iOS 27.0, *)
struct VisionOnDeviceEngine: SearchEngine {
    let name = "端末内AI"
    let supportsImages = true

    func topics(_ request: SearchRequest) async throws -> TopicResult {
        let session = LanguageModelSession(instructions: Prompts.instructions)
        let result = try await generate(
            GeneratedTopics.self,
            session: session,
            prompt: Prompts.topics(request),
            imageData: request.imageData
        )
        return TopicResult(topics: result.topics, canAnswer: result.canAnswer)
    }

    func answer(_ request: SearchRequest) async throws -> AnswerResult {
        let session = LanguageModelSession(instructions: Prompts.instructions)
        let result = try await generate(
            GeneratedAnswer.self,
            session: session,
            prompt: Prompts.answer(request, detailed: false),
            imageData: request.imageData
        )
        return AnswerResult(headline: result.headline, points: result.points, answerable: result.answerable)
    }
}

/// Appleのクラウド（Private Cloud Compute）。「もっと詳しく」専用。
/// 利用には com.apple.developer.private-cloud-compute の権限が必要。
///
/// 注意（公式文書より）：
/// - 権限がないアプリでも isAvailable は true を返しうる。その状態で問いを送るとアプリが落ちる。
///   そのため、このエンジンを使うかどうかは isAvailable ではなく、
///   ビルド時の PCC_ENTITLEMENT（Engine.swift の makeDetailEngine）で決める。
/// - モデルを作った時点で Apple のサーバーへの確認が走る。
///   だから必要になるまで作らず、作るのも1つだけにして使い回す。
@available(iOS 27.0, *)
struct CloudEngine: SearchEngine {
    let name = "Appleのクラウド"
    let supportsImages = true

    /// 初めて触れたときに1度だけ作られる。
    private static let model = PrivateCloudComputeLanguageModel()

    static var isAvailable: Bool {
        model.isAvailable
    }

    func topics(_ request: SearchRequest) async throws -> TopicResult {
        let session = LanguageModelSession(
            model: Self.model,
            instructions: Prompts.instructions
        )
        let result = try await generate(
            GeneratedTopics.self,
            session: session,
            prompt: Prompts.topics(request),
            imageData: request.imageData
        )
        return TopicResult(topics: result.topics, canAnswer: result.canAnswer)
    }

    func answer(_ request: SearchRequest) async throws -> AnswerResult {
        let session = LanguageModelSession(
            model: Self.model,
            instructions: Prompts.instructions
        )
        let result = try await generate(
            GeneratedAnswer.self,
            session: session,
            prompt: Prompts.answer(request, detailed: true),
            imageData: request.imageData
        )
        return AnswerResult(headline: result.headline, points: result.points, answerable: result.answerable)
    }
}
#endif
