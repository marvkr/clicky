//
//  ClaudeAPI.swift
//  Clicky
//
//  Orchestrates AI CLI calls by delegating to the appropriate provider
//  (Claude Code or OpenAI Codex). CompanionManager owns an instance of
//  this class and calls analyzeImageStreaming for each voice interaction.
//

import Foundation

class ClaudeAPI {
    var model: String
    /// Set by CompanionManager when the user switches providers in the UI.
    var preferredProvider: AICLIProvider = .claude

    private var resolvedProvider: AICLIProvider?
    private var resolvedBinaryPath: String?

    // proxyURL kept for call-site compatibility but is unused.
    init(proxyURL: String = "", model: String = "claude-sonnet-4-6") {
        self.model = model
    }

    // MARK: - Provider Resolution

    private func resolveProviderAndBinary() throws -> (AICLIProvider, String) {
        if let provider = resolvedProvider, let path = resolvedBinaryPath,
           provider == preferredProvider {
            return (provider, path)
        }

        let providersToTry: [AICLIProvider] = preferredProvider == .codex
            ? [.codex, .claude]
            : [.claude, .codex]

        for provider in providersToTry {
            if let path = AICLIUtils.findBinaryPath(for: provider) {
                resolvedProvider = provider
                resolvedBinaryPath = path
                return (provider, path)
            }
        }

        throw NSError(
            domain: "ClaudeAPI",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "No AI CLI found. Install Claude Code (claude.ai/code) or OpenAI Codex (github.com/openai/codex)."]
        )
    }

    // MARK: - Public API

    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()
        let (provider, binaryPath) = try resolveProviderAndBinary()

        var tempImageURLs: [URL] = []
        defer {
            for url in tempImageURLs { try? FileManager.default.removeItem(at: url) }
        }
        for (index, image) in images.enumerated() {
            let tempURL = try AICLIUtils.writeImageToTempFile(imageData: image.data, index: index)
            tempImageURLs.append(tempURL)
        }

        let prepTime = Date().timeIntervalSince(startTime)
        let imageSizeKB = images.reduce(0) { $0 + $1.data.count } / 1024
        print("🤖 AI CLI provider: \(provider.rawValue), binary: \(binaryPath)")
        print("⏱️ [1/5] Prep (write \(images.count) image, \(imageSizeKB)KB): \(String(format: "%.0f", prepTime * 1000))ms")

        let responseText: String

        switch provider {
        case .claude:
            let promptBuildStart = Date()
            let fullPrompt = ClaudeCLIProvider.buildPrompt(
                images: images,
                tempImageURLs: tempImageURLs,
                conversationHistory: conversationHistory,
                userPrompt: userPrompt
            )
            let promptBuildTime = Date().timeIntervalSince(promptBuildStart)
            print("⏱️ [2/5] Build prompt (\(conversationHistory.count) history turns): \(String(format: "%.0f", promptBuildTime * 1000))ms")

            let spawnStart = Date()
            let (process, stdoutHandle) = try ClaudeCLIProvider.spawnProcess(
                binaryPath: binaryPath,
                systemPrompt: systemPrompt,
                fullPrompt: fullPrompt,
                model: model
            )
            let spawnTime = Date().timeIntervalSince(spawnStart)
            print("⏱️ [3/5] Spawn CLI process: \(String(format: "%.0f", spawnTime * 1000))ms")

            let streamStart = Date()
            responseText = await ClaudeCLIProvider.parseStreamingResponse(
                from: stdoutHandle,
                onTextChunk: onTextChunk
            )
            let streamTime = Date().timeIntervalSince(streamStart)
            print("⏱️ [4/5] CLI stream + API response: \(String(format: "%.1f", streamTime))s")

            process.waitUntilExit()
            print("⏱️ [5/5] Process exit (status \(process.terminationStatus))")

            if process.terminationStatus != 0 {
                throw NSError(
                    domain: "ClaudeAPI",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Claude CLI exited with status \(process.terminationStatus)"]
                )
            }

        case .codex:
            let promptBuildStart = Date()
            let fullPrompt = CodexCLIProvider.buildPrompt(
                conversationHistory: conversationHistory,
                userPrompt: userPrompt
            )
            print("⏱️ [2/5] Build prompt: \(String(format: "%.0f", Date().timeIntervalSince(promptBuildStart) * 1000))ms")

            let spawnStart = Date()
            let (process, stdoutHandle) = try CodexCLIProvider.spawnProcess(
                binaryPath: binaryPath,
                systemPrompt: systemPrompt,
                fullPrompt: fullPrompt,
                imageFilePaths: tempImageURLs.map(\.path)
            )
            print("⏱️ [3/5] Spawn CLI process: \(String(format: "%.0f", Date().timeIntervalSince(spawnStart) * 1000))ms")

            let streamStart = Date()
            responseText = await CodexCLIProvider.readPlainTextResponse(
                from: stdoutHandle,
                onTextChunk: onTextChunk
            )
            print("⏱️ [4/5] CLI stream + API response: \(String(format: "%.1f", Date().timeIntervalSince(streamStart)))s")

            process.waitUntilExit()
            print("⏱️ [5/5] Process exit (status \(process.terminationStatus))")

            if process.terminationStatus != 0 {
                throw NSError(
                    domain: "ClaudeAPI",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Codex CLI exited with status \(process.terminationStatus)"]
                )
            }
        }

        let totalTime = Date().timeIntervalSince(startTime)
        print("⏱️ Total AI round-trip: \(String(format: "%.1f", totalTime))s (\(responseText.count) chars)")
        return (text: responseText, duration: totalTime)
    }

    func analyzeImage(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String
    ) async throws -> (text: String, duration: TimeInterval) {
        return try await analyzeImageStreaming(
            images: images,
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            userPrompt: userPrompt,
            onTextChunk: { _ in }
        )
    }
}
