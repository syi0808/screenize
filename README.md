<p align="center">
  <img src="Screenize/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Screenize" width="128" height="128">
</p>

<h1 align="center">Screenize</h1>

<p align="center">
  <strong>Free, open-source Screen Studio alternative for macOS</strong><br>
  Record your screen. Let auto-zoom do the rest.
</p>

<p align="center">
  <img src="docs/demo.gif" alt="Screenize demo" style="max-width: 100%; width: 520px;" />
</p>

You record a demo, a tutorial, or a quick walkthrough. Screenize watches your cursor and clicks, then automatically zooms, pans, and adds effects — no manual keyframing needed.

Unlike paid alternatives, Screenize is **completely free** and gives you **full control** over every zoom, transition, and effect through a timeline editor.

## Why Screenize?

**You don't need to pay $89+ for polished screen recordings.**

- **Auto-zoom that actually gets it right** — Two smart camera modes: one follows your cursor in real time with spring physics, the other plans zoom levels per activity (typing, clicking, scrolling, dragging). Both are deeply customizable.
- **Timeline editor, not a black box** — Don't like how a zoom turned out? Edit it. Every auto-generated keyframe is visible and adjustable on a multi-track timeline.
- **Click effects & keystroke overlays** — Ripple animations on clicks, keyboard shortcut badges (⌘C, ⇧⌘Z) on screen. Your viewers see exactly what you're doing.
- **Make it look good** — Gradient backgrounds, rounded corners, shadows, custom cursors, motion blur on fast transitions. Ship recordings that look like you spent hours on them.
- **Export your way** — MP4, MOV (ProRes), or GIF. Up to 4K, up to 240fps. sRGB, Display P3, BT.709, BT.2020. Save presets for your workflow.
- **Capture everything** — System audio + mic, screen or single window, 720p to 4K, variable frame rate for smaller files.
- **6 languages** — English, Korean, Chinese, Japanese, French, and German.

## Install

**Homebrew (recommended)**

```bash
brew install --cask thedavidweng/tap/screenize
```

**Manual download**

Grab the latest `.dmg` from [GitHub Releases](https://github.com/syi0808/screenize/releases) and drag Screenize into Applications.

> **First launch on macOS:** Since Screenize isn't notarized with Apple yet, macOS will show a warning. Right-click the app, select **Open**, and confirm. You only need to do this once.

### Permissions

On first launch, Screenize asks for four permissions:

| Permission | Why |
| --- | --- |
| Screen Recording | Capture your screen |
| Microphone | Record audio |
| Input Monitoring | Track clicks and keystrokes |
| Accessibility | Detect UI elements for smart zoom |

## How It Works

1. **Pick a screen or window** and hit record
2. **Do your thing** — Screenize tracks your cursor, clicks, and keystrokes in the background
3. **Open the editor** — auto-generated zoom and effects are already on the timeline
4. **Tweak if needed** — adjust any keyframe, add click effects, change cursor styles
5. **Export** — one click, polished result

### Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `Cmd+Shift+2` | Toggle recording (global hotkey) |
| `Cmd+N` | New recording |
| `Cmd+R` | Start/stop recording |
| `Cmd+P` | Pause/resume |
| `Cmd+E` | Export |
| `Cmd+O` | Open video |
| `Cmd+Shift+O` | Open project |
| `Cmd+Z` / `Cmd+Shift+Z` | Undo / Redo |

## Contributing

Screenize is built in the open and contributions are welcome — bug reports, feature ideas, or code. Check the [Contributing Guide](CONTRIBUTING.md) to get started.

AI-assisted contributions (Claude Code, Copilot, etc.) are welcome too, as long as they're well-tested. See [CLAUDE.md](CLAUDE.md) for AI agent guidance.

## License

Apache License 2.0 — see [LICENSE](LICENSE).

## Author

**Yein Sung** — [GitHub](https://github.com/syi0808)
