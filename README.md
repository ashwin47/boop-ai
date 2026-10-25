<div align="center">
  <img src="Boop/boop.png" width="120" alt="Boop">
  <h1>Boop</h1>
  <p><strong>Select text anywhere on your Mac, press a hot key, get better writing.</strong></p>
  <p>
    <img src="https://img.shields.io/badge/macOS-15%2B-black" alt="macOS 15+">
    <img src="https://img.shields.io/badge/license-MIT-black" alt="MIT">
  </p>
</div>

Boop is a tiny menu-bar app that improves your writing in place. Select text in
any app, press **Hyper + A**, pick an edit — Improve writing, Fix spelling and
grammar, and so on — from the menu that appears next to the selection, and the
rewritten text replaces the original.

It was built to replace a feature that used to be free with your own API key.
Boop is free, open source, and **bring your own key** — the only thing between
you and the model is your own Cloudflare account.

## Why Cloudflare AI Gateway

Rather than storing a separate API key for every provider, Boop talks to **your**
[Cloudflare AI Gateway](https://developers.cloudflare.com/ai-gateway/). You store
your OpenAI / Anthropic / Google keys there once, and Boop holds a single gateway
token — kept in the macOS Keychain, never in a plist.

That means provider keys never touch this app, you get one dashboard with usage,
logs, caching and rate limiting across all three providers, and switching models
is a dropdown rather than a re-auth.

## Features

- **Anchored popover.** Reads the selection's on-screen rectangle via the
  Accessibility API, including Chromium/Electron text-marker ranges. Briefly
  retries while accessibility initializes, and places the popover above or below
  the full highlight with a small gap. When bounds are unavailable, an optional
  on-device screen recognition fallback locates the text in the source window.
  Otherwise, Boop uses the focused control or a stable position in the source
  window. The pointer is used only when no usable window bounds are available.
- **Action menu.** Choose an edit with the mouse, <kbd>↑</kbd>/<kbd>↓</kbd> and
  <kbd>↩</kbd>, or <kbd>1</kbd>–<kbd>9</kbd>. The result is pasted straight over
  the selection; <kbd>esc</kbd> cancels.
- **Quiet completion sound.** Cuelume's Success chime plays when a rewrite
  finishes successfully. Enabled by default; turn it off with **Settings →
  General → Play sounds on complete**. Cancelled, failed, and empty responses
  stay silent.
- **Eight models** across three providers, switchable in Settings.
- **Reasoning effort** control for models that support it.
- **Custom actions** — four built in; add, reorder and edit your own name, icon
  and system prompt under **Settings → Actions**.
- **Rebindable hot key**, defaulting to Hyper + A (⌃ ⌥ ⇧ ⌘ A).
- **Stays out of the way.** No Dock icon, and Boop never activates — focus
  goes straight back to your app for the paste.

## Install

```bash
brew install --cask fayazara/tap/boop
```

Or download the latest `Boop.dmg` from
[Releases](https://github.com/fayazara/boop/releases) and drag it to
Applications. Boop updates itself from there on via Sparkle.

## Setup

### 1. Grant Accessibility permission

Boop needs it to read the selected text and to paste the result back. macOS will
prompt on first launch, or add it manually under **System Settings → Privacy &
Security → Accessibility**.

> Rebuilding from source changes the app's signature, which silently revokes this
> grant. If the hot key stops responding, remove and re-add Boop there.

### 2. Set up a Cloudflare AI Gateway

1. In the [Cloudflare dashboard](https://dash.cloudflare.com/?to=/:account/ai/ai-gateway),
   create a gateway (name it `boop`).
2. Add your provider API keys under the gateway's provider settings.
3. Create a **gateway authentication token**.
4. Grab your **account ID** from the dashboard URL or `wrangler whoami`.

### 3. Enter it in Boop

Open **Settings → Gateway** and fill in the account ID, gateway name, and token.
The token is stored in the Keychain.

### 4. Optional: precise placement in apps without text bounds

In **Settings → General → Popover Placement**, enable **Find selected text on
screen**, then click **Allow Screen Recording…** and grant macOS permission.
Restart Boop if macOS asks. This option defaults to off.

When accessibility cannot locate a selection, Boop captures only the source
window and uses Apple Vision to match the selected text locally. The image is
never saved or sent to the AI provider. Recognition adds some delay and accepts
  only a confident, unique match; very short text, duplicate occurrences, or text
outside the visible window may still use the window fallback.

## Models

| Provider  | Models |
|-----------|--------|
| OpenAI    | `gpt-5.6-luna` (default), `gpt-5.6-sol`, `gpt-5.6-terra` |
| Anthropic | `claude-opus-5`, `claude-sonnet-5`, `claude-fable-5` |
| Google    | `gemini-3.8-flash`, `gemini-3.5-flash-lite` |

Requests go to the gateway's OpenAI-compatible endpoint
(`/compat/chat/completions`), which takes `provider/model` slugs and streams
standard SSE deltas.

## Building from source

Requires Xcode 26. Runs on macOS 15 (Sequoia) and later.

```bash
git clone https://github.com/fayazara/boop.git
cd boop
open Boop.xcodeproj
```

Sparkle is pulled in via Swift Package Manager and resolves on first build. The
updater is compiled out in Debug builds.

Run `zsh scripts/check-popup-placement.sh` for selection geometry checks and
`zsh scripts/check-screen-recognition.sh` for text matching checks. The latter
also accepts a screenshot path and selected text as two arguments for a local
OCR integration check. To
diagnose an app that still falls back, filter Console for Boop's `Selection`
category; it records the anchor method without
logging selected text. Verify Chrome/Electron placement with both mouse and
keyboard selections, multiline text, and windows on different displays.

## How it works

| Piece | What it does |
|---|---|
| `Capture/TextCapture.swift` | Reads `AXSelectedText` and the selection's bounds, falling back to a ⌘C round-trip for apps that don't expose them. Enables Chromium's full AX tree via `AXManualAccessibility`. |
| `Capture/ScreenSelectionLocator.swift` | Optional window-only ScreenCaptureKit capture and on-device Vision text recognition. |
| `Capture/ScreenTextMatcher.swift` | Finds a confident unique match, including wrapped text and small OCR errors. |
| `Capture/Synthetic.swift` | Posts ⌘C / ⌘V, waiting for the Hyper chord to be released first — posted keystrokes otherwise inherit held modifiers. |
| `Support/HotKeyManager.swift` | Carbon `RegisterEventHotKey` for the trigger chord, because Carbon *consumes* the keystroke where an event monitor only observes it. |
| `AI/GatewayClient.swift` | Streaming SSE client for the AI Gateway. |
| `UI/PopupPlacement.swift` | Turns an accessibility rectangle into somewhere sensible to anchor the popover. |

## Releasing

Maintainers only — see [`.agents/skills/release-boop`](.agents/skills/release-boop/SKILL.md).

```bash
go run ./cmd/boop-release -build -yes \
  -set-version 0.1.1 -set-build 2 \
  -notes "What changed"
```

## License

MIT — see [LICENSE](LICENSE).

The Success sound is adapted from Cuelume by Daniel Belyi (MIT). Its license is
included in [Boop/Resources/Cuelume-LICENSE.txt](Boop/Resources/Cuelume-LICENSE.txt).
Regenerate the bundled sound with `python3 scripts/render-success-sound.py`.
