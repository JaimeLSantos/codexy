# Status

## Done (0.1.0, unreleased)
- SwiftPM package `CodexyCore` / `CodexyUsage` / `CodexyCoreTests`, copied from Claudy's provider-neutral code.
- Codex reader (`Usage.swift`): `codex app-server` → `account/rateLimits/read`; fallback to the last `token_count` event of the newest rollout file (plain or `.zst`). Tests with anonymised fixtures (28 tests green).
- Panel: 5h hero + bar, reset time, pace, week row, plan in the footer, 24h / week chart. Menu bar: two mini bars 5h / W.
- Mascots: `Pet.swift` + `pets/*.txt` (theo, bit, owl, book), picker with live preview in Settings → Look, `--pets DIR` renders every mood. Clawd only with `CODEXY_PET=clawd` (dev).
- Own bundle id, data folder, log and defaults domain (`dev.julio.codexy`, `Application Support/Codexy`, `Logs/Codexy.log`).
- Details: turns and sessions, projects (click for models and busiest hours), models and the "When you use it" heatmap, 24 h or 7 days. `RolloutScanner` (`Projects.swift`) reads `~/.codex/sessions` and `archived_sessions` (`.jsonl` from where it stopped, `.jsonl.zst` once with `zstd`) and parses only `session_meta`, `turn_context` and `token_count` lines, picked by their first bytes. Tokens are the growth of the running totals; a fork's copy of its parent is skipped (same totals, same turn ids, its first seconds, its first count). Weight = fresh input + 0.1 × cached + 8 × output, × 0.2 for mini and 0.04 for nano models: an estimate, OpenAI does not say how each model counts against the plan. Scanned when Details opens, then every 15 min while it stays open. Export writes `codexy-projects.csv` again.
- OpenAI status (`Status.swift`): `status.openai.com/proxy/status.openai.com` (the incident.io JSON the page itself loads, has the groups), fallback `/api/v2/summary.json` (Statuspage shape, seen 2026-10-22 with only part of the components and no incidents). Only the "Codex" group (Codex Web, Codex API, CLI, VS Code extension) plus any component named "Codex" set the level. Every 2 minutes. The proxy URL is not a documented API: if it breaks, the fallback still gives the overall indicator.
- Credits (`CodexCredits`, `ResetCredits` in `Usage.swift`): shape from codex-rs `app-server-protocol` v2 (`GetAccountRateLimitsResponse`). Shown under the week row only when there is something (reset credits > 0, balance > 0 or unlimited). Session files carry `credits` but not reset credits.

## Hidden or stubbed (the provider data is not wired yet)
- Running sessions: `AppModel.sessions` stays empty, the row is hidden. The git reader (`Git.info`) is ready; Codex keeps `session_index.jsonl` and `state_5.sqlite`, not looked at yet.
- Usage profile (context size, skills, MCP) and the token stats window: Claude-only reports, no Codex counterpart. A tokens-per-day window could be built from the same rollout scan.
- CLI version/update row: removed (Claudy read `claude --version` and ran `claude update`). Status is back, from OpenAI.
- Settings: the Claude Code settings editor tab is gone. The Fable toggle is gone (status is back); "Running sessions" and "Plan and account" toggles stay.
- `Strings.swift` still holds Claudy keys for the removed features; prune when each one is decided.

## Next
- Theo (the owner's blue heeler) is drawn from his photos (photos stay out of the repo). He walks in side view and sits when idle or waiting (`[walk1] [walk2] [sit]` in the pet file, optional per pet).
- Accessories (skins) are hidden: they are anchored to Clawd's head. Give each pet file a head anchor, then show them again.
- Bit, Coruja and Livrinho have no side poses yet: they walk facing forward.
- App icon (`Resources/AppIcon.icns`), README pictures.
- Decide how often to start `codex app-server` (now once a minute, a fresh process each time) or keep one running.
- Codex sessions list (from `session_index.jsonl` or the app-server's thread APIs).
- Check the project weights against a real week: whether the mini/nano factors and the 8x output weight match how fast the 5h bar moves.
- Release script, Homebrew cask.
