# Changelog

## [Unreleased]
### Added
- First version, built from Claudy Usage: Codex 5h and weekly limits in the menu bar and the panel.
- Reads `codex app-server` (`account/rateLimits/read`), with the newest session file in `~/.codex/sessions` as fallback.
- Four mascots drawn from text files, picked in Settings → Aparência (Look) with a live preview: Theo (default), Bit, Coruja and Livrinho. Each has a normal, slack (low use), near-the-limit and sleeping face. Your own go in `~/Library/Application Support/Codexy/pets`.
- Theo is the owner's blue heeler, drawn from his photos. He walks in side view (two steps, turning with the direction) and sits after a few seconds standing still, also while a session waits for you.
- Plan name in the panel footer; a note when the numbers come from a session file.
- Running Codex sessions in the panel (project, branch / worktree, working / waiting for you / idle), the blinking "?" and the optional notification when one waits for you. Read from the rollout files the `codex` processes keep open; "waiting" is inferred, since Codex does not write approval prompts to disk.
- OpenAI status in the panel and the floating card, Codex only: the components of the "Codex" group on status.openai.com set the dot; other OpenAI services being off is mentioned, not alarmed. A click opens the page. Switch in Settings → Look.
- Reset credits and paid credits under the week row, when Codex reports any (`rateLimitResetCredits`, `rateLimits.credits`): how many, and when the next one expires. Read-only: Codexy never redeems one.
- CI on a macOS runner: `swift build` and `swift test` on every pull request.

### Not yet
- Side views for Bit, Coruja and Livrinho (they walk facing forward); accessories redrawn for the new heads (hidden for now); an app icon with Theo. Clawd, Claudy's crab, is only in dev mode.
