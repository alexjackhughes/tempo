# Instructions for AI assistants

This file tells an AI coding assistant (Claude Code, Cursor, Codex, etc.) how to install, update, troubleshoot and modify **Tempo** for a user. Human-oriented docs are in [README.md](README.md).

Tempo is a macOS menu bar app (Swift Package, SwiftUI) that tracks app and website usage locally and includes a focus timer. It has **no server, no account and no network access**.

---

## Installing Tempo for a user

Run each step and check its result before moving on.

### 1. Check prerequisites

```bash
sw_vers -productVersion   # must be 14.0 or higher
swift --version           # must be Swift 5.9 or higher
xcode-select -p           # must print a path (Xcode or Command Line Tools)
```

- If macOS is older than 14, stop: Tempo can't run there. Tell the user.
- If `swift`/`xcode-select` is missing, ask the user to run `xcode-select --install` (it opens a system dialog they have to approve), then retry.

### 2. Get the code

```bash
git clone https://github.com/alexjackhughes/tempo.git
cd tempo
```

### 3. Build and install

```bash
./scripts/build-app.sh --install
```

Expected final line: `Installed to /Applications/Tempo.app`. Then verify:

```bash
pgrep -x Tempo && echo "Tempo is running"
ls ~/Library/Application\ Support/Tempo/config.json   # created on first launch
```

If the build fails, read the compiler error. The usual cause is a Swift toolchain older than 5.9. `swift test` requires full Xcode; building does not.

### 4. Hand over to the user (things only they can do)

Tell the user:
- The Tempo icon (a clock with a "T") is now in the menu bar. Click it, type a task, and press Return to start a 20-minute focus session.
- macOS will ask to allow **notifications**, and the first time they use each browser it will ask whether **Tempo can control** it. Both should be allowed (browser access lets Tempo record the website domain).
- Optional: **Dashboard → Settings → Launch at login**, so tracking always runs.

Don't try to approve permission dialogs, change System Settings or enable launch at login on the user's behalf unless they ask you to.

### 5. Coming from Timing?

There is no importer. Explain that Tempo ships with default categories and rules (Development, Work & Docs, Communication, Social Media, Entertainment, Shopping, Utilities), and that they can add or rename categories in **Dashboard → Categories**. If they list the categories and sites they used in Timing, you can add rules for them in the app's UI (*New category*, then *Add rule*). Alternatively, quit Tempo first (popover `…` → Quit Tempo) and edit `~/Library/Application Support/Tempo/config.json` (schema below), then relaunch with `open /Applications/Tempo.app`. Tempo would overwrite edits made while it's running.

---

## Updating

```bash
cd tempo && git pull && ./scripts/build-app.sh --install
```

The installer sends SIGTERM, which Tempo handles by saving activity and the running timer before exiting, so updating loses nothing.

## Uninstalling

Quit via the popover (`…` → **Quit Tempo**; ⌘Q deliberately does *not* quit), or `pkill -TERM -x Tempo`. Then:

```bash
rm -rf /Applications/Tempo.app
```

Only delete `~/Library/Application Support/Tempo` if the user explicitly wants their data gone, because it can't be recovered.

---

## Troubleshooting checklist

| Symptom | Check / fix |
|---|---|
| "The icon isn't in the menu bar" | `pgrep -x Tempo`. If it's running, the icon is probably hidden behind the MacBook notch: tell the user to ⌘-drag it right or quit other menu bar apps. `open /Applications/Tempo.app` while running opens the dashboard. |
| Websites aren't recorded | Automation permission was denied. User: System Settings → Privacy & Security → Automation → Tempo → enable the browser. Firefox is unsupported. |
| Permission prompts reappear after each rebuild | Expected with ad-hoc signing. Optionally `tccutil reset AppleEvents <bundle-id>` and re-approve. |
| No data being recorded | Tracking may be paused (popover `…` menu), the user may be idle (default threshold 3 min), or the screen is locked. |
| Quit doesn't quit | By design. Use popover `…` → Quit Tempo. |

---

## Data model (for scripts and migrations)

Directory: `~/Library/Application Support/Tempo/`

- `activity/YYYY-MM-DD.json`: `[{"start": <unix>, "end": <unix>, "app": "Safari", "bundleID": "com.apple.Safari", "domain": "github.com"}]`. `domain` is optional.
- `sessions.json`: `[{"id", "start", "end", "plannedMinutes", "task", "completed"}]`
- `config.json`:
  - `categories`: `[{"id": UUID, "name", "colorHex", "productivity": "productive"|"neutral"|"distracting"}]`
  - `rules`: `[{"id": UUID, "kind": "app"|"domain", "pattern": "lowercased name, bundle id or domain", "categoryID": UUID}]`
  - `ignored`: `[{"kind", "value"}]` for apps/domains that are never recorded
  - `focusMinutes`, `breakMinutes`, `dailyPomodoroGoal`, `idleThreshold` (seconds), `trackBrowserURLs`
- `active-session.json`: the current timer state (`phase`: focus / breakReady / rest), if any.

Rules are applied when data is read, so editing rules changes all history. Unknown keys are ignored and missing settings fall back to defaults.

---

## Working on the code

```bash
swift build && swift test
TEMPO_SNAPSHOT_DIR=/tmp/tempo-shots swift test --filter SnapshotTests   # renders every screen with fake data
./scripts/build-app.sh --install                                        # try it for real
```

- **Map:** see the "Development" section of README.md.
- **Design system:** `Sources/Tempo/Views/Theme.swift` holds colour tokens (`T.*`, light and dark), fonts (`.geist()`, `.mono()`), `Panel`, `MetricStrip`, `TempoButtonStyle`, `Segmented`, `TField`, and so on. Reuse these rather than adding ad-hoc styling.
- **Invariants to keep:**
  - No network calls, and no data leaves the Mac.
  - Only the domain of a URL is stored, never the full URL.
  - Rules are evaluated when data is read (`Categorizer`), not baked into stored segments.
  - The menu bar label must stay compact. Long labels get hidden behind the notch on crowded menu bars.
  - Quit from the Dock or ⌘Q must not stop tracking; only `AppDelegate.quit()` does.
- Verify UI changes with the snapshot test, and add a logic test in `Tests/TempoTests/TempoTests.swift` for behaviour changes.
