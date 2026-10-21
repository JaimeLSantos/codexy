# Codexy (macOS)

Menu bar app that shows OpenAI Codex plan limits (5h and weekly). Built from [Claudy Usage](https://github.com/juliobianco/claudy-usage-mac)
(`../claudy-usage-mac`), itself a port of [Enhed/clawd-usage-winwidget](https://github.com/Enhed/clawd-usage-winwidget). Both MIT.

**Claudy is a separate project: read and copy from `../claudy-usage-mac`, never write, build or run git there.**

Status and backlog: `docs/STATUS.md`. Keep it and `CHANGELOG.md` (*Unreleased*) current with every change.

## Layout
- `Sources/CodexyCore`: no UI, testable. `Usage.swift` (Codex reader: app-server + session-file fallback, `CodexLimits`), `Sessions.swift` (git reader + neutral `AgentSession`), `History.swift` (5h/week samples), `Pace`, `Alerts`, `Export`, `Format`, `ChartMarks`, `Sky`, `Mascot` + `Clawd` (placeholder mascot engine).
- `Sources/CodexyUsage`: SwiftUI, same files as Claudy. `Model.swift` polls `CodexCLI.fetchUsage()` once a minute.
- Data: `~/Library/Application Support/Codexy`, log `~/Library/Logs/Codexy.log`, bundle id `dev.julio.codexy`. Never share files or defaults with Claudy.

## Where the numbers come from
1. `codex app-server` over stdio (JSON-RPC lines): `initialize` (clientInfo name `codexy`), `initialized`, `account/rateLimits/read`.
   Answer: `result.rateLimits.{primary,secondary}.{usedPercent, windowDurationMins, resetsAt}` + `planType`. No model call.
2. Fallback: the newest `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` (older ones are `.jsonl.zst`, read with `zstd -dc` if installed),
   last `event_msg` of type `token_count`: `payload.rate_limits.{primary,secondary}.{used_percent, window_minutes, resets_at}` + `plan_type`.
   The panel says "from a session file" then. A reset already past means that window started over: 0%.
- Windows are picked by length (≤ 1 day = 5h bar, longer = week), not by primary/secondary order.
- Never print or store prompts, conversation content, `auth.json`, emails or account ids.

## Commands
```
S=$HOME/Library/Caches/codexy-build
swift build --scratch-path $S
swift test  --scratch-path $S
$S/debug/CodexyUsage --snapshot DIR     # panel.png + bar.png with live data (CODEXY_DETAILS=1 opens the chart, CODEXY_NO_FLOAT=1)
./scripts/bundle.sh                     # builds and signs ~/Applications/Codexy.app
```
Other dev modes and env vars are the same as Claudy's, with `CODEXY_` instead of `CLAUDY_`.

## Gotchas (from Claudy)
- **Build outside `~/Documents`** (`--scratch-path`): its file provider adds xattrs and `codesign` fails.
- Snapshots must not write to real files (`AppModel.persist = false`).
- `MenuBarExtra` drops custom shapes: the mini bars are an `ImageRenderer` bitmap.
- SwiftPM resources: `bundle.sh` copies `CodexyUsage_CodexyUsage.bundle` into `Contents/Resources`.
- A menu bar app from Finder has a bare PATH: `CodexCLI` looks in `~/.local/bin`, Homebrew and `/usr/local/bin`.

## Text
Never hard-code a user-facing string: add it to `Strings.swift` in en and pt (`L.t("key")`).

## Routine
Git identity is not configured on this Mac: commit with `git -c user.name="Julio Bianco" -c user.email=julio.bellon@gmail.com` and the Co-Authored-By line. No remote yet.
