> **🚧 Beta:** This project is under active development. Expect breaking changes between versions.

<p align="center">
  <img src="Screenize/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Screenize" width="128" height="128">
</p>

<h1 align="center">Screenize</h1>

<p align="center">
  <img src="docs/demo.gif" alt="Screenize demo" style="max-width: 100%; width: 520px;" />
</p>

Open-source macOS screen recording app with auto-zoom, cursor effects, and timeline editing — Screen Studio alternative.

Screenize uses a two-pass processing model: first capture raw video alongside mouse and click data, then apply intelligent zoom, click effects, and background styling through a timeline-based editor. The result is polished screen recordings without manual keyframing.

## Features

- **Screen & Window Capture** — Record entire displays or individual windows via ScreenCaptureKit with configurable resolution (720p–4K), frame rate (24–240 fps), and quality presets
- **Audio Recording** — Capture system audio and microphone simultaneously with independent volume controls and device selection
- **Smart Camera** — Two auto-zoom modes: **Continuous Camera** (spring physics with dead zones and intent-based responsiveness) and **Segment-based Camera** (shot planning with per-activity zoom levels for typing, clicking, navigating, dragging, scrolling, and idle states)
- **Timeline Editor** — Edit camera, cursor, click effect, and keystroke segments on a multi-track timeline with spring easing, undo/redo, copy/paste, and multi-selection
- **Click Effects** — Ripple animations with configurable scale, duration, and spring easing on mouse clicks
- **Keystroke Overlays** — Display keyboard shortcuts (e.g. ⌘C, ⇧⌘Z) or all keystrokes with configurable duration, fade, and position
- **Custom Cursors** — 7 cursor styles (Arrow, Pointer, I-Beam, Crosshair, Open Hand, Closed Hand, Context Menu) with adjustable scale
- **Window Styling** — Backgrounds (solid color, gradient presets, custom image), rounded corners, shadow, and padding around the recording
- **Motion Blur** — Configurable blur on fast zoom/pan transitions with intensity presets (Subtle, Strong)
- **Export** — MP4 (H.264/H.265), MOV (ProRes 422/4444), and GIF with configurable resolution, frame rate, color space (sRGB, Display P3, BT.709, BT.2020), and quality settings
- **Export Presets** — Save and manage reusable render settings
- **VFR Recording** — Variable frame rate capture with frame deduplication for smaller file sizes
- **Auto-Update** — Built-in update checking via Sparkle

### Planned Features

- Import Screen Studio projects

## Getting Started

### Requirements

- macOS 13.0 or later

### Download

Download the latest version from [GitHub Releases](https://github.com/syi0808/screenize/releases).

Open the `.dmg` file and drag Screenize into the Applications folder.

**Homebrew**

```bash
brew install --cask thedavidweng/tap/screenize
```

> **macOS Gatekeeper warning:** Screenize is not notarized with Apple, so macOS may display a warning when you first open the app. To open it:
>
> 1. Right-click (or Control-click) the Screenize app in the Applications folder
> 2. Select **Open** from the context menu
> 3. Click **Open** in the dialog that appears
>
> Alternatively, go to **System Settings > Privacy & Security**, scroll down, and click **Open Anyway** next to the Screenize message.
>
> You only need to do this once — macOS will remember your choice for future launches.

### Setup

On first launch, Screenize will request the following permissions:

1. **Screen Recording** — Required to capture your screen
2. **Microphone** — Required for audio recording
3. **Input Monitoring** — Required for click and keystroke tracking
4. **Accessibility** — Required for UI element detection and smart zoom

Grant each permission when prompted, or enable them manually under **System Settings > Privacy & Security**.

## Usage

1. Launch Screenize and select a screen or window to record
2. Start recording — mouse movements and clicks are tracked automatically
3. Stop the recording — it opens in the timeline editor
4. Review auto-generated zoom and keystroke keyframes, or add click effects and cursor styles manually
5. Export the final video with all effects applied

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

Contributions are welcome. Please read the [Contributing Guide](CONTRIBUTING.md) before submitting a pull request.

AI-assisted contributions (Claude Code, GitHub Copilot, etc.) are welcome, but must be well-tested before submission. See [CLAUDE.md](CLAUDE.md) for AI agent guidance.

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.

## Author

**Yein Sung** — [GitHub](https://github.com/syi0808)
