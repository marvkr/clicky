//
//  AICLIProvider.swift
//  Clicky
//
//  Shared types and utilities for AI CLI providers (Claude Code, OpenAI Codex).
//

import Foundation

/// Which AI CLI to use for vision requests.
enum AICLIProvider: String {
    case claude = "claude"
    case codex = "codex"
}

/// Shared utilities for finding CLI binaries and writing temp files.
enum AICLIUtils {

    /// The real user home directory, bypassing App Sandbox containers.
    /// NSHomeDirectory() and $HOME both return the sandbox container path
    /// when the app is sandboxed. The POSIX getpwuid call always returns
    /// the actual home directory.
    static let realHomeDirectory: String = {
        if let pw = getpwuid(getuid()), let homeDir = pw.pointee.pw_dir {
            return String(cString: homeDir)
        }
        return NSHomeDirectory()
    }()

    /// Searches well-known install paths for a specific provider's CLI binary.
    static func findBinaryPath(for provider: AICLIProvider) -> String? {
        let home = realHomeDirectory
        let binaryName = provider.rawValue

        let searchPaths: [String]
        switch provider {
        case .claude:
            searchPaths = [
                "\(home)/.local/bin/claude",
                "/usr/local/bin/claude",
                "/opt/homebrew/bin/claude",
                "\(home)/.nvm/versions/node",
            ]
        case .codex:
            searchPaths = [
                "\(home)/.local/bin/codex",
                "/usr/local/bin/codex",
                "/opt/homebrew/bin/codex",
                "\(home)/.nvm/versions/node",
            ]
        }

        for path in searchPaths {
            // For nvm: scan all installed node versions for the binary
            if path.hasSuffix("/node") && FileManager.default.fileExists(atPath: path) {
                if let versions = try? FileManager.default.contentsOfDirectory(atPath: path) {
                    for version in versions.sorted().reversed() {
                        let nvmBinaryPath = "\(path)/\(version)/bin/\(binaryName)"
                        if FileManager.default.fileExists(atPath: nvmBinaryPath) {
                            return nvmBinaryPath
                        }
                    }
                }
                continue
            }

            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// Writes image data to a uniquely-named temp file for CLI @filepath references.
    static func writeImageToTempFile(imageData: Data, index: Int) throws -> URL {
        let tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clicky_screen_\(index)_\(UUID().uuidString).jpg")
        try imageData.write(to: tempFileURL)
        return tempFileURL
    }

    /// Creates a process environment with the real home directory.
    /// Optionally adds the binary's parent directory to PATH so that
    /// nvm-installed scripts can find `node` in the same directory.
    static func makeProcessEnvironment(binaryPath: String? = nil) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = realHomeDirectory

        if let binaryPath = binaryPath {
            let binaryDirectory = (binaryPath as NSString).deletingLastPathComponent
            let currentPath = environment["PATH"] ?? "/usr/bin:/bin"
            environment["PATH"] = "\(binaryDirectory):\(currentPath)"
        }

        return environment
    }
}
