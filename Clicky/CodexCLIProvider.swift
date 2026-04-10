//
//  CodexCLIProvider.swift
//  Clicky
//
//  OpenAI Codex CLI integration — spawns `codex exec` with image support.
//  Uses plain text output because --json hangs with --image (known bug).
//

import Foundation

enum CodexCLIProvider {

    /// Builds the prompt with conversation history.
    static func buildPrompt(
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String
    ) -> String {
        var parts: [String] = []

        for (userMessage, assistantResponse) in conversationHistory {
            parts.append("User: \(userMessage)\nAssistant: \(assistantResponse)")
        }

        parts.append(userPrompt)
        return parts.joined(separator: "\n\n")
    }

    /// Spawns `codex exec --image <paths> "prompt"` as a subprocess.
    static func spawnProcess(
        binaryPath: String,
        systemPrompt: String,
        fullPrompt: String,
        imageFilePaths: [String]
    ) throws -> (process: Process, stdoutFileHandle: FileHandle) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)

        var arguments = ["exec"]
        for imagePath in imageFilePaths {
            arguments.append(contentsOf: ["--image", imagePath])
        }
        arguments.append(contentsOf: ["--system-prompt", systemPrompt])
        arguments.append(fullPrompt)
        process.arguments = arguments
        process.environment = AICLIUtils.makeProcessEnvironment()

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        try process.run()
        return (process: process, stdoutFileHandle: stdoutPipe.fileHandleForReading)
    }

    /// Reads plain text output line by line from the Codex CLI.
    static func readPlainTextResponse(
        from stdoutFileHandle: FileHandle,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async -> String {
        var accumulatedResponseText = ""

        do {
            for try await line in stdoutFileHandle.bytes.lines {
                accumulatedResponseText += line + "\n"
                let currentText = accumulatedResponseText
                await MainActor.run { onTextChunk(currentText) }
            }
        } catch {
            // Stream read error — process exit status is checked by the caller
        }

        return accumulatedResponseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
