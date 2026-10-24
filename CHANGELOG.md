# Changelog

## [Unreleased]

## [0.2.2] - 2026-10-23
### Changed
- Usage Details has a labelled expand/collapse row below status and a direct “Tokens per day…” entry; saved visibility preferences are preserved.
- Activity and tokens distinguish loading, no recorded use, unavailable files and partial reads. Limits charts explain first samples, short history, gaps and the weekly quota cycle.

## [0.2.1] - 2026-10-23
### Changed
- Recorded a partial local dashboard validation in `docs/USAGE-VALIDATION.md`: independent counts for four anonymised sessions, real-data chart rendering and remaining client-coverage/quota-calibration checks. No production behaviour changed.
- Documented the usage dashboard backlog in execution order: validate existing data, improve Details discovery and empty states, expose tokens directly, then investigate and implement supported read-only skills/plugins/MCP information. This is planning only.
- The doghouse is pixel art on the mascot's grid (about a third lower, shingled roof, plank walls, arched door). Theo shrinks as he walks to it, sleeps inside with his ears visible under the eave and grows back to full size when he leaves. His side pose fades near the door; bubbles, hearts, sweat and z follow his size.
- Theo no longer burrows: he has a doghouse at the right end of the scene and walks home to sleep (no sessions) or doze (idle 10 min). The other mascots still burrow.

## [0.2.0] - 2026-10-22
### Added
- Tokens per day window (panel menu → "Tokens per day…"): stacked bars by model for 7 or 30 days, with input, output and cached totals per model. Real token counts from the rollout files, the same scan as Details; nothing is read but the counts.

### Changed
- Running sessions: the state (working, waiting for you, idle) now comes from Codex's own app-server daemon when it is running, instead of a guess from the session file; the guess stays as the fallback. An idle session whose file Codex had closed now shows up too.

## [0.1.0] - 2026-10-22
### Added
- First version, built from Claudy Usage: Codex 5h and weekly limits in the menu bar and the panel.
- Reads `codex app-server` (`account/rateLimits/read`), with the newest session file in `~/.codex/sessions` as fallback.
- Four mascots drawn from text files, picked in Settings → Aparência (Look) with a live preview: Theo (default), Bit, Coruja and Livrinho. Each has a normal, slack (low use), near-the-limit and sleeping face. Your own go in `~/Library/Application Support/Codexy/pets`.
- Theo is the owner's blue heeler, drawn from his photos. He walks in side view (two steps, turning with the direction) and sits after a few seconds standing still, also while a session waits for you.
- Plan name in the panel footer; a note when the numbers come from a session file.
- Details: turns and sessions, projects (click one for its models and busiest hours), models and the "When you use it" heatmap, for 24 hours or 7 days. Counted on this Mac from Codex's own session files; no conversation text is read.
- Running Codex sessions in the panel (project, branch / worktree, working / waiting for you / idle), the blinking "?" and the optional notification when one waits for you. Read from the rollout files the `codex` processes keep open; "waiting" is inferred, since Codex does not write approval prompts to disk.
- OpenAI status in the panel and the floating card, Codex only: the components of the "Codex" group on status.openai.com set the dot; other OpenAI services being off is mentioned, not alarmed. A click opens the page. Switch in Settings → Look.
- Reset credits and paid credits under the week row, when Codex reports any (`rateLimitResetCredits`, `rateLimits.credits`): how many, and when the next one expires. Read-only: Codexy never redeems one.
- Extra limits: when Codex reports other buckets (`rateLimitsByLimitId`, a model or feature with its own limits) each gets a line under the week row, and `rateLimitReachedType` shows which limit stopped you. Plus plans report only the main bucket today, so this is covered by tests, not yet seen live.
- Codex version in the Details footer, with "update available" when GitHub's latest release is newer and the command to run in a terminal. Show only: Codexy never updates Codex.
- App icon with Theo, `scripts/package.sh` (universal ad-hoc signed zip with SHA-256) and a README with pictures.
- CI on a macOS runner: `swift build` and `swift test` on every pull request.

### Fixed
- `scripts/bundle.sh` copied a resource bundle that does not exist (`CodexyUsage_CodexyUsage.bundle`); SwiftPM names it `Codexy_CodexyUsage.bundle` after the package, so the script stopped halfway and the app would not open.

### Not yet
- Side views for Bit, Coruja and Livrinho (they walk facing forward); accessories redrawn for the new heads (hidden for now); an app icon with Theo. Clawd, Claudy's crab, is only in dev mode.
