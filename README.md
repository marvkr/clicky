# Clicky — Zero-Config Fork

A fork of [farzaa/clicky](https://github.com/farzaa/clicky) that works with your existing **Claude Code** or **OpenAI Codex** subscription. No API keys, no Cloudflare Workers, no setup — just install and talk.

![Clicky — an ai buddy that lives on your mac](clicky-demo.gif)

## What's different from the original

| | [Original](https://github.com/farzaa/clicky) | This fork |
|---|---|---|
| **Auth** | Cloudflare Worker + Anthropic API key | Local CLI (your Claude Code / Codex subscription) |
| **Network** | HTTP to worker proxy → Anthropic API | No network setup — spawns local `claude` or `codex` binary |
| **Cost** | Pay per Anthropic API token | Uses your existing subscription |
| **Setup** | Deploy worker, set 3 API keys, update URLs | Just install the CLI and run |
| **AI Providers** | Claude only | Claude + Codex (switchable in UI) |
| **Models** | Sonnet / Opus | Sonnet / Opus (Claude) or GPT-5.4 / 5.4 mini / Codex (Codex) |
| **TTS** | ElevenLabs via worker proxy (needs API key) | macOS `say` command (free, always works) |
| **Speech-to-Text** | AssemblyAI via worker proxy (needs API key) | Apple Speech (free, on-device) |
| **UI** | Dark opaque panel | Frosted glass panel (Liquid Glass on macOS 26+) |

## Get started

### Prerequisites

- macOS 14.2+
- Xcode 15+
- [Claude Code](https://claude.ai/code) **or** [OpenAI Codex](https://github.com/openai/codex) installed and authenticated

### 1. Install an AI CLI

Pick one (or both):

```bash
# Claude Code
curl -fsSL https://claude.ai/install.sh | sh
claude  # follow the login prompt

# OpenAI Codex
npm install -g @openai/codex
```

### 2. Clone and run

```bash
git clone https://github.com/YOUR_USERNAME/clicky.git
cd clicky
open Clicky.xcodeproj
```

In Xcode:
1. Set your signing team under **Signing & Capabilities**
2. **Cmd+R** to build and run

The app appears in your menu bar (not the dock). Click the icon, grant permissions, and you're ready.

### 3. Use it

- **Hold Ctrl+Option** and speak — Clicky transcribes your voice, takes a screenshot, sends both to your AI, and speaks the response back
- **Switch providers** — pick Claude or Codex in the menu bar panel
- **Switch models** — Sonnet/Opus for Claude, GPT-5.4/5.4 mini/Codex for Codex

### Permissions needed

- **Microphone** — for push-to-talk voice capture
- **Accessibility** — for the global keyboard shortcut (Ctrl+Option)
- **Screen Recording** — for screenshots when you use the hotkey

## Features

### AI Provider Picker
Switch between Claude Code and OpenAI Codex directly from the menu bar panel. Each provider shows its own model list. Your choice is persisted across app restarts.

### Tutor Mode
Toggle on "Tutor mode" and Clicky becomes a proactive instructor. It watches what you're doing and guides you step by step — pointing at buttons, explaining what things do, and suggesting what to try next. Uses idle detection to trigger at natural break points.

### Cursor Pointing
Claude can point at specific UI elements on your screen. When it references a button or link, the blue cursor flies to that spot with a smooth bezier arc animation. Works across multiple monitors.

### Auto-Copy Responses
Toggle on "Copy responses" and every AI response gets automatically copied to your clipboard.

### Frosted Glass UI
The menu bar panel uses macOS material blur (frosted glass effect). On macOS 26+, it upgrades to Apple's Liquid Glass.

## Architecture

Menu bar app (no dock icon) with two `NSPanel` windows — one for the control panel dropdown, one for the full-screen transparent cursor overlay. Push-to-talk captures audio via `AVAudioEngine`, transcribes with Apple Speech, takes a screenshot via ScreenCaptureKit, spawns the AI CLI (`claude --print` or `codex exec --image`) as a subprocess, and speaks the response via the macOS `say` command. The AI can embed `[POINT:x,y:label:screenN]` tags to make the cursor fly to specific UI elements.

## Project structure

```
Clicky/                     # Swift source
  ClickyApp.swift             # Menu bar app entry point
  CompanionManager.swift      # Central state machine
  CompanionPanelView.swift    # Menu bar panel UI
  ClaudeAPI.swift             # AI CLI orchestrator
  AICLIProvider.swift         # Provider enum + binary discovery
  ClaudeCLIProvider.swift     # Claude Code CLI integration
  CodexCLIProvider.swift      # OpenAI Codex CLI integration
  ElevenLabsTTSClient.swift   # TTS via macOS say command
  OverlayWindow.swift         # Blue cursor overlay
  BuddyDictation*.swift       # Push-to-talk pipeline
  AppleSpeech*.swift           # On-device speech recognition
  DesignSystem.swift           # Design tokens + button styles
CLAUDE.md                   # Full architecture doc
```

## Contributing

PRs welcome. If you're using Claude Code, it already knows the codebase — just point it at `CLAUDE.md`.

Original project by [@farzatv](https://x.com/farzatv).
