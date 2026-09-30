# Tempo

A private, local-only time tracker and pomodoro timer that lives in the macOS menu bar.

- Records the frontmost app every 5s (and the website domain in Safari/Chrome/Arc/Brave/Edge/Vivaldi/Opera).
- Stops counting after a few minutes of no keyboard/mouse input, and on sleep or screen lock.
- Categories + rules (app name/bundle ID or domain) → productive / neutral / distracting → a 0–100 score.
- Pomodoro sessions are scored by what you actually did during them.
- Data: `~/Library/Application Support/Tempo/` (plain JSON, one activity file per day).

## Build & install

    ./scripts/build-app.sh --install

Run tests with `swift test`. Render UI snapshots with sample data:

    TEMPO_SNAPSHOT_DIR=/some/dir swift test --filter SnapshotTests
