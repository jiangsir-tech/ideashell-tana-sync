# ideaShell to Tana Sync

[中文](README.md) | English

**IdeaSync** (Chinese name: 闪念同步) is a local macOS menu bar app that syncs new notes from ideaShell to a chosen Tana node.

It is designed for people who use both ideaShell and Tana. Connect your accounts, select a destination in Tana, optionally polish notes with AI, sync on demand, or enable automatic syncing—without editing `.env` files or using Terminal.

Your credentials, sync state, and logs stay on your Mac. This project does not upload note content or run a relay server.

## Features

- Reads recent new notes through the ideaShell MCP API.
- Sends only the note detail text to Tana, not the ideaShell title.
- Optionally polishes text with OpenAI, DeepSeek, OpenRouter, other OpenAI-compatible APIs, Anthropic Claude, Google Gemini, or Ollama.
- Removes trailing `#tags` from the note body.
- Records synced note IDs locally to prevent duplicate imports.
- Waits until a transcription is complete and stable across two scans, avoiding `(untitled)` or partial notes.
- Shows today's discovered, synced, pending, and failed notes in the menu bar.
- Includes a local sync-history window with all-time, monthly, and recent-30-day trends. Daily counts are kept for up to 365 days; note content is never stored in this history.
- Supports system language, Simplified Chinese, and English, with instant switching.
- After Tana confirms a write, prefixes the source ideaShell title with `～～`.
- Supports manual sync, or automatic sync every 5, 10, 15, 30, or 60 minutes, as well as once daily at a chosen time.

## Requirements

- macOS 14 or later
- An ideaShell API key for MCP
- A Tana Write API token and destination node ID
- Optional: an API key for an AI provider

Node.js is **not** required.

## Download and install

Download the latest test build from the [GitHub Releases page](https://github.com/1551255004/ideashell-tana-sync/releases).

1. Open the downloaded DMG.
2. Drag **IdeaSync** into **Applications**.
3. Open the app from Applications. Early test builds are unsigned: Control-click the app and choose **Open**, or use **Open Anyway** in **System Settings → Privacy & Security**.
4. Open IdeaSync from the menu bar and choose **Settings**.
5. Enter your ideaShell API key, Tana Write API token, and destination node ID. Use `INBOX` to send notes to the Tana Inbox.

The current test app is universal and supports both Apple Silicon and Intel Macs.

## Configuration

The app saves configuration automatically after a short pause while you type. The polish prompt has its own **Save Prompt** button. Required credentials must be valid before the app replaces an existing usable configuration.

Choose an AI provider in Settings to enable polishing. Presets are available for OpenAI, DeepSeek, OpenRouter, Anthropic, Gemini, and Ollama. You can also use any OpenAI-compatible endpoint. The **Test AI Connection** action does not read your real ideaShell notes or write to Tana.

The default prompt uses `{{text}}` as the original-note placeholder. You can edit it, save it locally, or restore the default. Your custom prompt is preserved when the app is upgraded.

Local files are stored here:

- Configuration and sync state: `~/Library/Application Support/ideashell-tana-sync/`
- Logs: `~/Library/Logs/ideashell-tana-sync/`

## First sync and automatic sync

After entering credentials, choose **Sync Now** from the menu bar. New notes are held until their title and content are unchanged for two scans and have been stable for at least four minutes. Seeing a pending note during the first sync is expected.

Enable automatic sync in **Settings**, then choose an interval or a daily time. Your Mac must be on and you must be signed in, but ideaShell, Tana, and Terminal do not need to be open. New voice notes may take 5–10 minutes to reach Tana while transcription completes.

## Publishing updates

The About window includes **Check for Updates**. It reads `update.json` from the repository root, compares the monotonically increasing build number, shows release notes, and opens the corresponding GitHub Release download page when an update is available.

For beta releases, the trailing beta number is used as the build number automatically:

```bash
./build-dmg.sh 0.1.0-beta.5
```

For a stable release or a custom build, provide an integer greater than every previously published build:

```bash
APP_BUILD=6 ./build-dmg.sh 0.1.0
```

Create the GitHub Release and confirm that its DMG can be downloaded before updating and pushing `update.json`. This prevents users from seeing an update that is not available yet.

To inspect the background job:

```bash
launchctl print gui/$(id -u)/com.ideashell-tana-sync
```

## Privacy and security

- Never commit `.env`, `.ideashell-tana-state.json`, or `logs/`.
- API keys are stored in a local user-only configuration file with `600` permissions, outside the project folder and ignored by Git.
- When AI polishing is enabled, note text is sent to the AI endpoint you configure.

## Feedback

Choose **Feedback** in the app's About window, or open the [feedback form](https://tally.so/r/2EyvKg). Remove API keys, tokens, note text, and other private information before submitting.

## License

[MIT](LICENSE)
