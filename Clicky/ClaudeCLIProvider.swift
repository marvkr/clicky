//
//  ClaudeCLIProvider.swift
//  Clicky
//
//  Claude Code CLI integration — spawns `claude --print` with streaming JSON output.
//

import Foundation

enum ClaudeCLIProvider {

    /// Builds the prompt with conversation history and @filepath image references.
    static func buildPrompt(
        images: [(data: Data, label: String)],
        tempImageURLs: [URL],
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String
    ) -> String {
        var parts: [String] = []

        for (userMessage, assistantResponse) in conversationHistory {
            parts.append("User: \(userMessage)\nAssistant: \(assistantResponse)")
        }

        for (index, image) in images.enumerated() {
            parts.append("\(image.label): @\(tempImageURLs[index].path)")
        }

        parts.append("User: \(userPrompt)")
        return parts.joined(separator: "\n\n")
    }

    /// Spawns `claude --print --output-format stream-json --verbose` as a subprocess.
    static func spawnProcess(
        binaryPath: String,
        systemPrompt: String,
        fullPrompt: String,
        model: String
    ) throws -> (process: Process, stdoutFileHandle: FileHandle, stderrFileHandle: FileHandle) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        // `--bare` is NOT used here: it disables OAuth/keychain auth and requires
        // ANTHROPIC_API_KEY in the environment. Since this fork authenticates
        // via the user's existing `claude.ai` subscription (OAuth), `--bare`
        // causes the CLI to exit with "Not logged in". Keep startup-trimming
        // flags that don't affect auth (`--no-session-persistence`).
        process.arguments = [
            "--print",
            "--output-format", "stream-json",
            "--verbose",
            "--no-session-persistence",
            "--system-prompt", systemPrompt,
            "--model", model,
            fullPrompt
        ]
        process.environment = AICLIUtils.makeProcessEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        return (
            process: process,
            stdoutFileHandle: stdoutPipe.fileHandleForReading,
            stderrFileHandle: stderrPipe.fileHandleForReading
        )
    }

    /// Parses the streaming JSON output from the Claude CLI.
    /// The standalone CLI emits:
    ///   "assistant" → message with content array
    ///   "result"    → final complete response text
    static func parseStreamingResponse(
        from stdoutFileHandle: FileHandle,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async -> String {
        var accumulatedResponseText = ""

        do {
        for try await line in stdoutFileHandle.bytes.lines {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            guard let lineData = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let eventType = event["type"] as? String else { continue }

            if eventType == "assistant",
               let message = event["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if let blockType = block["type"] as? String,
                       blockType == "text",
                       let text = block["text"] as? String {
                        accumulatedResponseText = text
                        let currentText = accumulatedResponseText
                        await MainActor.run { onTextChunk(currentText) }
                    }
                }
            } else if eventType == "result",
                      let resultText = event["result"] as? String {
                accumulatedResponseText = resultText
                let finalText = accumulatedResponseText
                await MainActor.run { onTextChunk(finalText) }
            }
        }
        } catch {
            // Stream read error — process exit status is checked by the caller
        }

        return accumulatedResponseText
    }

    /// Writes an empty MCP config so the subprocess doesn't connect to user's MCP servers.
    private static func writeEmptyMCPConfig() throws -> URL {
        let emptyMCPConfigURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clicky_mcp_config_\(UUID().uuidString).json")
        let emptyMCPConfig = Data("{\"mcpServers\":{}}".utf8)
        try emptyMCPConfig.write(to: emptyMCPConfigURL)
        return emptyMCPConfigURL
    }
}
