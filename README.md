# Codexy

Your OpenAI Codex plan limits in the Mac menu bar: two mini bars (5h and week), a panel with the reset times, a pace forecast and a 24h / week chart.

It reads the limits from your local Codex install (`codex app-server`, falling back to the last session file in `~/.codex/sessions`). No login of its own, no tokens spent, nothing leaves the Mac.

Early work: see [docs/STATUS.md](docs/STATUS.md).

## Build
```
S=$HOME/Library/Caches/codexy-build
swift build --scratch-path $S && swift test --scratch-path $S
./scripts/bundle.sh        # ~/Applications/Codexy.app
```
Needs macOS 14 and the `codex` CLI logged in.

## Credits
Built on [Claudy Usage](https://github.com/juliobianco/claudy-usage-mac), a Swift port of [Enhed/clawd-usage-winwidget](https://github.com/Enhed/clawd-usage-winwidget) (both MIT).
The pixel mascot is a placeholder from Claudy (Clawd is Anthropic's); Codexy will get its own. Not affiliated with OpenAI.
