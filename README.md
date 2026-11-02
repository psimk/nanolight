<p align="center"><img src="src/icon-256.png" alt="Nanolight's icon" width="96" height="96"></p>

<h1 align="center">Nanolight</h1>
<p align="center"><b>A ⌘Space launcher for the Mac, drawn by <a href="https://github.com/justrach/nanoui">nanoui</a>.</b><br>
Apps, math, DuckDuckGo and Grok: one keystroke away. Native Zig, no Electron, about 1 MB.</p>

<p align="center"><a href="https://github.com/justrach/nanolight/raw/refs/heads/main/docs/promo.mp4"><img src="docs/promo-preview.gif" alt="Nanolight in 31 seconds: apps, initials, typos, math, Google suggestions and results in the panel, on a MacBook Air" width="760"></a><br><sub><a href="https://github.com/justrach/nanolight/raw/refs/heads/main/docs/promo.mp4"><b>Watch the original promo with sound →</b></a> · <a href="docs/promo.md">How it was made</a></sub></p>

<p align="center"><img src="docs/images/nanolight.jpg" alt="Nanolight's panel has found Safari from &quot;saf&quot;" width="760"></p>

## What it does

- **Finds apps as you type**: whole names, starts of words, initials (`ss` is System Settings), letters in order, and typos (`chorme` is Chrome). What you open often climbs.
- **Completes inline**: the rest of the top app's name, or of DuckDuckGo's top suggestion, is drawn faintly after the caret. Tab or → takes it; Return never does.
- **Does math**: `2^10 * 3` answers 3,072 (and `0xC00`). Return copies it.
- **DuckDuckGo suggestions**: up to four, under the apps, the words you add in bold. Nothing that reads as an address (a dot, a slash, an @) is sent.
- **Search in your browser**: Return on a search or suggestion opens DuckDuckGo in your default browser and closes the panel.
- **Ask Grok**, a row away.
- **⌘1–⌘9** run a row at once; ↑ ↓ and ⌃N ⌃P move.
- Lives in the menu bar: no Dock icon, and nothing drawn while it's idle.

## Window management

Open Nanolight with your shortcut, then type a command and press Return. The command acts on the window you used before opening Nanolight.

- **Left Half**, **Right Half**, **Top Half**, **Bottom Half**.
- **Top Left Quarter**, **Top Right Quarter**, **Bottom Left Quarter**, **Bottom Right Quarter**.
- **Maximize** fills the display without covering the Dock or menu bar. **Center** keeps the window's size.
- **Restore** returns the window to its position before its first arrangement in this Nanolight session.
- **Next Display** and **Previous Display** move the window between displays and keep its relative size and position.

You can also type `window left half` or `quarter`. Window commands stay local and do not request web suggestions.

macOS requires Accessibility access to move other apps' windows. The first window command requests access if it is missing and shows an **Open Settings** button.
Allow Nanolight in **System Settings → Privacy & Security → Accessibility**, then retry the command.
For a development build, allow the executable or terminal that macOS lists. Packaged builds appear as Nanolight.

Some apps limit window movement or resizing. Leave full screen before arranging a window.

## Sync across Macs (optional)

Off until you turn it on: choose **Sign In with Codegraff to Sync Across Macs…** in the menu bar icon's menu. Your browser opens codegraff.com to approve the sign-in, and from then on every Mac signed in to the same account shares:

- the key that opens Nanolight,
- whether DuckDuckGo suggestions are on,
- how often you open each app, so an empty panel suggests the same apps everywhere.

Two Macs merge rather than overwrite: the key and the suggestions setting follow whichever Mac changed them last, and each app keeps its higher count. Nothing else is sent: no queries, no history, no files. The sign-in key is kept in your Keychain, and **Sign Out of Codegraff** revokes it.

Syncing goes through your Codegraff account, so [Codegraff's terms](https://codegraff.com/terms) and [privacy policy](https://codegraff.com/privacy) apply to it. New accounts made by signing in from Nanolight get $2 of Codegraff credit.

## Install

Download `nanolight-macos-arm64.dmg` from the [latest release](https://github.com/justrach/nanolight/releases/latest), open it and drag Nanolight to Applications. macOS 14 or later, Apple silicon.

On first run a short welcome picks the key that opens it (⌘Space, ⌥Space, ⌃Space, ⌥⌘Space or ⌘D) and says who else holds it: Spotlight gives up ⌘Space in System Settings → Keyboard → Keyboard Shortcuts → Spotlight. To change the shortcut later, choose **Welcome…** from the menu bar icon's menu. Signed releases update themselves from this repository's releases; the menu bar icon offers the restart.

## Build

You need Zig 0.17.0 and Xcode or the Command Line Tools.

```sh
zig build test      # search, math, suggestions and the panel, through nanoui's Tester
zig build run       # build and open it
zig build app       # zig-out/Nanolight.app, for /Applications
VERSION=0.1.0 sh macos/package.sh   # the release: signed app, disk image, update zip, manifest.json
```

`macos/package.sh` signs with `$CODESIGN_IDENTITY` and notarizes when notary credentials are set (see the script); otherwise it signs ad hoc. Pushing a `v*` tag runs `.github/workflows/release.yml`, which builds, signs and attaches the release.

## How it's made

| File | What |
| --- | --- |
| `src/main.zig` | The app: the window, the hot key, the menu bar icon, updates |
| `src/view.zig` | The panel: query, rows, footer, keys |
| `src/results.zig` | What a query lists, in order |
| `src/search.zig` | Fuzzy matching and ranking, allocation-free |
| `src/calc.zig` | The calculator |
| `src/window_layout.zig`, `src/window_control.zig` | Window commands, display geometry, and macOS Accessibility control |
| `src/suggest.zig` | DuckDuckGo's completions: the privacy guard, decoding, the cache (after [browse](https://github.com/justrach/browse)) |
| `src/onboard.zig`, `src/shortcut.zig` | The welcome, and which key is free |
| `src/film.zig`, `src/stage.zig`, `tools/film.sh` | The walkthrough, rendered offscreen |
| `src/promo.zig`, `src/promo_cards.zig`, `tools/promo.sh`, `tools/promo/` | The promo: nanoui's shots, Blender's laptop ([docs/promo.md](docs/promo.md)) |

The icon is drawn by `tools/icon.py`. `src/backdrop.jpg` (the film's cover art) was made with OpenAI's image model.

## License

MIT
