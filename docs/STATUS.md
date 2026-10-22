# Status

## Done (0.1.0, unreleased)
- SwiftPM package `CodexyCore` / `CodexyUsage` / `CodexyCoreTests`, copied from Claudy's provider-neutral code.
- Codex reader (`Usage.swift`): `codex app-server` → `account/rateLimits/read`; fallback to the last `token_count` event of the newest rollout file (plain or `.zst`). Tests with anonymised fixtures (28 tests green).
- Panel: 5h hero + bar, reset time, pace, week row, plan in the footer, 24h / week chart. Menu bar: two mini bars 5h / W.
- Own bundle id, data folder, log and defaults domain (`dev.julio.codexy`, `Application Support/Codexy`, `Logs/Codexy.log`).
- Details: turns and sessions, projects (click for models and busiest hours), models and the "When you use it" heatmap, 24 h or 7 days. `RolloutScanner` (`Projects.swift`) reads `~/.codex/sessions` and `archived_sessions` (`.jsonl` from where it stopped, `.jsonl.zst` once with `zstd`) and parses only `session_meta`, `turn_context` and `token_count` lines, picked by their first bytes. Tokens are the growth of the running totals; a fork's copy of its parent is skipped (same totals, same turn ids, its first seconds, its first count). Weight = fresh input + 0.1 × cached + 8 × output, × 0.2 for mini and 0.04 for nano models: an estimate, OpenAI does not say how each model counts against the plan. Scanned when Details opens, then every 15 min while it stays open. Export writes `codexy-projects.csv` again.
- OpenAI status (`Status.swift`): `status.openai.com/proxy/status.openai.com` (the incident.io JSON the page itself loads, has the groups), fallback `/api/v2/summary.json` (Statuspage shape, seen 2026-10-22 with only part of the components and no incidents). Only the "Codex" group (Codex Web, Codex API, CLI, VS Code extension) plus any component named "Codex" set the level. Every 2 minutes. The proxy URL is not a documented API: if it breaks, the fallback still gives the overall indicator.
- Credits (`CodexCredits`, `ResetCredits` in `Usage.swift`): shape from codex-rs `app-server-protocol` v2 (`GetAccountRateLimitsResponse`). Shown under the week row only when there is something (reset credits > 0, balance > 0 or unlimited). Session files carry `credits` but not reset credits.

## Mascot (`Pet.swift`, `Sources/CodexyUsage/pets/*.txt`)
Done:
- Four pets drawn from text files on the 18 x 12 grid: Theo (theo), Bit (bit), Coruja (owl), Livrinho (book). Each has `[normal] [slack] [crit] [sleep]` faces; they reuse the mascot brain (walk, hop, burrow, lie on the back).
- Theo is the default and first in the list. He is the owner's blue heeler, drawn from his photos (the photos stay out of the repo). The old id `heeler` still maps to him.
- Theo walks in side view (`[walk1] [walk2]`, mirrored when going left) and sits (`[sit]`) after ~3 s standing still, when idle or when a session waits for you. Side poses are optional per pet.
- Picker with a live preview in Settings → Aparência (Look) → Mascote. Own pets: `~/Library/Application Support/Codexy/pets/*.txt` (same id replaces a built-in one).
- `--pets DIR` renders every pet in every mood and pose; `CODEXY_PET=<id>` previews one in `--scenes`.

Pending:
- Side views (walk and sit) for Bit, Coruja and Livrinho: they walk facing forward.
- Accessories (skins) are hidden: they are drawn for Clawd's head. Redraw them for the new heads (or give each pet file a head anchor), then show them again.
- App icon with Theo (`Resources/AppIcon.icns`) and README pictures.
- Clawd stays only in dev mode (`CODEXY_PET=clawd`): he is Anthropic's character and is not in the picker.

## Running sessions (`CodexSessions.swift`)
- Codex has no registry like `~/.claude/sessions`. A live thread keeps its rollout file open (codex-rs `rollout/src/recorder.rs`), so: list the user's processes named `codex*` (sysctl), their open files (libproc), keep `sessions/**/rollout-*.jsonl`. Checked live with codex-cli 0.163.0: the TUI starts an app-server child (`codex app-server --listen unix://`) and that child holds the file, so `pid` is the child, not the Terminal process. One process can hold several threads, so the id is the thread id. `source` says "vscode" even for the TUI; `originator` ("codex-tui") tells where a session came from. The Codex desktop app held no rollout file when checked.
- Read: the first line (`session_meta`: id, cwd, source) and the last 256 KB (1 MB if no turn marker): `task_started` / `task_complete` / `turn_aborted`, tool calls with no output yet. Never prompts or answers. Name: `session_index.jsonl` (renamed threads), else the folder.
- Sub-agents, guardian reviews and internal jobs (object `source`, `parent_thread_id`, `thread_source` ≠ user) are hidden.
- "Waiting for you" is a guess: approval prompts are not written to the file. A shell/patch call with no output, file quiet ≥ 3 s, no process started under codex since the call, and `approval_policy` ≠ never → waiting. `request_user_input` → waiting at once. Known misses: an auto-reviewer thinking for a few seconds looks like a prompt; an MCP tool approval is shown as working.

## Hidden or stubbed (the provider data is not wired yet)
- Usage profile (context size, skills, MCP) and the token stats window: Claude-only reports, no Codex counterpart. A tokens-per-day window could be built from the same rollout scan.
- CLI version/update row: removed (Claudy read `claude --version` and ran `claude update`). Status is back, from OpenAI.
- Settings: the Claude Code settings editor tab is gone. The Fable toggle is gone (status is back); "Running sessions" and "Plan and account" toggles stay.
- `Strings.swift` still holds Claudy keys for the removed features; prune when each one is decided.

## Next
- Mascot: see the Mascot section above.
- Decide how often to start `codex app-server` (now once a minute, a fresh process each time) or keep one running.
- Check the project weights against a real week: whether the mini/nano factors and the 8x output weight match how fast the 5h bar moves.
- Sessions, exact "waiting": an opt-in Codex `PermissionRequest`/`Stop` hook (writes to `~/.codex/config.toml`, so only after a click), or the app-server daemon socket (`thread/loaded/list` reports `waitingOnApproval`) when the user runs it.
- Release script, Homebrew cask.
