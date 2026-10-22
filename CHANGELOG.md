# Changelog

## [Unreleased]
### Added
- First version, built from Claudy Usage: Codex 5h and weekly limits in the menu bar and the panel.
- Reads `codex app-server` (`account/rateLimits/read`), with the newest session file in `~/.codex/sessions` as fallback.
- Four mascots to pick in Settings → Look: Theo, a blue heeler (default), Bit, Coruja and Livrinho, each with a normal, slack (low use), near-the-limit and sleeping face. Own ones go in `~/Library/Application Support/Codexy/pets`.
- Theo walks in side view (two steps, turning with the direction) and sits after a few seconds standing still, also while a session waits for you.
- Plan name in the panel footer; a note when the numbers come from a session file.
- OpenAI status in the panel and the floating card, Codex only: the components of the "Codex" group on status.openai.com set the dot; other OpenAI services being off is mentioned, not alarmed. A click opens the page. Switch in Settings → Look.
- Reset credits and paid credits under the week row, when Codex reports any (`rateLimitResetCredits`, `rateLimits.credits`): how many, and when the next one expires. Read-only: Codexy never redeems one.
- CI on a macOS runner: `swift build` and `swift test` on every pull request.
