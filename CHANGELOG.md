# Changelog

## [Unreleased]
### Added
- First version, built from Claudy Usage: Codex 5h and weekly limits in the menu bar and the panel.
- Reads `codex app-server` (`account/rateLimits/read`), with the newest session file in `~/.codex/sessions` as fallback.
- Four mascots to pick in Settings → Look: Theo, a blue heeler (default), Bit, Coruja and Livrinho, each with a normal, slack (low use), near-the-limit and sleeping face. Own ones go in `~/Library/Application Support/Codexy/pets`.
- Theo walks in side view (two steps, turning with the direction) and sits after a few seconds standing still, also while a session waits for you.
- Plan name in the panel footer; a note when the numbers come from a session file.
- Running Codex sessions in the panel (project, branch / worktree, working / waiting for you / idle), the blinking "?" and the optional notification when one waits for you. Read from the rollout files the `codex` processes keep open; "waiting" is inferred, since Codex does not write approval prompts to disk.
