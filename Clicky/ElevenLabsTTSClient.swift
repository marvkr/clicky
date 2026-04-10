//
//  ElevenLabsTTSClient.swift
//  Clicky
//
//  Text-to-speech via the macOS `say` command — reliable, no API key needed.
//

import Foundation

@MainActor
final class ElevenLabsTTSClient {
    private var currentProcess: Process?

    // proxyURL kept for call-site compatibility but ignored
    init(proxyURL: String = "") {}

    /// Speaks `text` using the macOS `say` command. Waits until speech finishes.
    func speakText(_ text: String) async throws {
        try Task.checkCancellation()

        stopPlayback()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [text]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        currentProcess = process

        print("🔊 TTS: speaking \(text.count) characters via say")

        try process.run()

        // Wait for speech to finish on a background thread to avoid blocking MainActor
        let runningProcess = process
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                runningProcess.waitUntilExit()
                continuation.resume()
            }
        }
    }

    /// Whether TTS audio is currently playing.
    var isPlaying: Bool {
        currentProcess?.isRunning ?? false
    }

    /// Stops any in-progress playback immediately.
    func stopPlayback() {
        if let process = currentProcess, process.isRunning {
            process.terminate()
        }
        currentProcess = nil
    }
}
