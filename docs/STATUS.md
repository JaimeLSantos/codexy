# Status

## Done (0.1.0, unreleased)
- SwiftPM package `CodexyCore` / `CodexyUsage` / `CodexyCoreTests`, copied from Claudy's provider-neutral code.
- Codex reader (`Usage.swift`): `codex app-server` → `account/rateLimits/read`; fallback to the last `token_count` event of the newest rollout file (plain or `.zst`). Tests with anonymised fixtures (28 tests green).
- Panel: 5h hero + bar, reset time, pace, week row, plan in the footer, 24h / week chart. Menu bar: two mini bars 5h / W.
- Mascots: `Pet.swift` + `pets/*.txt` (theo, bit, owl, book), picker with live preview in Settings → Look, `--pets DIR` renders every mood. Clawd only with `CODEXY_PET=clawd` (dev).
- Own bundle id, data folder, log and defaults domain (`dev.julio.codexy`, `Application Support/Codexy`, `Logs/Codexy.log`).

## Running sessions (`CodexSessions.swift`)
- Codex has no registry like `~/.claude/sessions`. A live thread keeps its rollout file open (codex-rs `rollout/src/recorder.rs`), so: list the user's processes named `codex*` (sysctl), their open files (libproc), keep `sessions/**/rollout-*.jsonl`. Checked live with codex-cli 0.163.0: the TUI starts an app-server child (`codex app-server --listen unix://`) and that child holds the file, so `pid` is the child, not the Terminal process. One process can hold several threads, so the id is the thread id. `source` says "vscode" even for the TUI; `originator` ("codex-tui") tells where a session came from. The Codex desktop app held no rollout file when checked.
- Read: the first line (`session_meta`: id, cwd, source) and the last 256 KB (1 MB if no turn marker): `task_started` / `task_complete` / `turn_aborted`, tool calls with no output yet. Never prompts or answers. Name: `session_index.jsonl` (renamed threads), else the folder.
- Sub-agents, guardian reviews and internal jobs (object `source`, `parent_thread_id`, `thread_source` ≠ user) are hidden.
- "Waiting for you" is a guess: approval prompts are not written to the file. A shell/patch call with no output, file quiet ≥ 3 s, no process started under codex since the call, and `approval_policy` ≠ never → waiting. `request_user_input` → waiting at once. Known misses: an auto-reviewer thinking for a few seconds looks like a prompt; an MCP tool approval is shown as working.

## Hidden or stubbed (the provider data is not wired yet)
- Projects, models, heatmap, usage profile, token stats window: removed from the panel; `ProjectUsage`, `HeatmapView`, `Export.projects` remain as models.
- Status page and CLI version/update rows: removed (Claudy read Anthropic's status page and `claude update`).
- Settings: the Claude Code settings editor tab is gone. Toggles for status/Fable are gone; "Running sessions" and "Plan and account" toggles stay.
- `Strings.swift` still holds Claudy keys for the removed features; prune when each one is decided.

## Next
- Theo (the owner's blue heeler) is drawn from his photos (photos stay out of the repo). He walks in side view and sits when idle or waiting (`[walk1] [walk2] [sit]` in the pet file, optional per pet).
- Accessories (skins) are hidden: they are anchored to Clawd's head. Give each pet file a head anchor, then show them again.
- Bit, Coruja and Livrinho have no side poses yet: they walk facing forward.
- App icon (`Resources/AppIcon.icns`), README pictures.
- Decide how often to start `codex app-server` (now once a minute, a fresh process each time) or keep one running.
- Show credits / reset-credit counts the app-server returns (`credits`, `rateLimitResetCredits`).
- Projects from the rollout files.
- Sessions, exact "waiting": an opt-in Codex `PermissionRequest`/`Stop` hook (writes to `~/.codex/config.toml`, so only after a click), or the app-server daemon socket (`thread/loaded/list` reports `waitingOnApproval`) when the user runs it.
- Release script, Homebrew cask.
