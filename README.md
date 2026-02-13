# Claude Sounds

A macOS menu bar app for managing sound packs in [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Plays custom audio cues for Claude Code events like session start, prompt submit, notifications, and more.

> **Want to contribute a community sound pack?** See [`community/README.md`](community/README.md) for how to create and submit your own pack. Community packs automatically appear in the app's Sound Pack Browser for all users to download.

## Features

- **Menu bar controls** - Mute/unmute, volume slider, quick pack switching
- **Sound Pack Browser** - Browse, download, install, and manage sound packs
- **Event Editor** - Drag-and-drop audio files onto individual events; preview sounds inline
- **Create Custom Packs** - Built-in wizard to scaffold a new sound pack with all event directories
- **Publish Packs** - Export any local pack as a ZIP or submit it to the community registry via GitHub PR
- **Setup Wizard** - Guided first-run setup that installs Claude Code hooks automatically
- **Hook integration** - Installs shell hooks that trigger sounds on Claude Code events
- **Audio validation** - Magic-byte verification, ZIP preflight, and post-extract sanitization at every entry point

## Supported Events

| Event | Description |
|---|---|
| Session Start | Claude Code session begins |
| Prompt Submit | User submits a prompt |
| Notification | Claude sends a notification |
| Stop | Claude stops generating |
| Session End | Claude Code session ends |
| Subagent Stop | A subagent finishes |
| Tool Failure | A tool use fails |

## Audio Formats

Supports `.wav`, `.mp3`, `.aiff`, `.m4a`, `.ogg`, and `.aac` files.

## Installation

### Build from source

```bash
# Quick build (uses build.sh)
./build.sh
open ClaudeSounds.app

# Or manually
swiftc -O -o ClaudeSounds -framework Cocoa Sources/*.swift
```

Requires macOS and Xcode Command Line Tools (`xcode-select --install`).

## Sound Pack Structure

Sound packs live in `~/.claude/sounds/<pack-id>/` with one subdirectory per event:

```
~/.claude/sounds/my-pack/
  session-start/
  prompt-submit/
  notification/
  stop/
  session-end/
  subagent-stop/
  tool-failure/
```

Drop audio files into any event directory. When multiple files exist for an event, one is played at random.

## License

MIT
