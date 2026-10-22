# Status

## Done (0.1.0, unreleased)
- SwiftPM package `CodexyCore` / `CodexyUsage` / `CodexyCoreTests`, copied from Claudy's provider-neutral code.
- Codex reader (`Usage.swift`): `codex app-server` → `account/rateLimits/read`; fallback to the last `token_count` event of the newest rollout file (plain or `.zst`). Tests with anonymised fixtures (28 tests green).
- Panel: 5h hero + bar, reset time, pace, week row, plan in the footer, 24h / week chart. Menu bar: two mini bars 5h / W.
- Mascots: `Pet.swift` + `pets/*.txt` (heeler, bit, owl, book), picker with live preview in Settings → Look, `--pets DIR` renders every mood. Clawd only with `CODEXY_PET=clawd` (dev).
- Own bundle id, data folder, log and defaults domain (`dev.julio.codexy`, `Application Support/Codexy`, `Logs/Codexy.log`).

## Hidden or stubbed (the provider data is not wired yet)
- Running sessions: `AppModel.sessions` stays empty, the row is hidden. The git reader (`Git.info`) is ready; Codex keeps `session_index.jsonl` and `state_5.sqlite`, not looked at yet.
- Projects, models, heatmap, usage profile, token stats window: removed from the panel; `ProjectUsage`, `HeatmapView`, `Export.projects` remain as models.
- Status page and CLI version/update rows: removed (Claudy read Anthropic's status page and `claude update`).
- Settings: the Claude Code settings editor tab is gone. Toggles for status/Fable are gone; "Running sessions" and "Plan and account" toggles stay.
- `Strings.swift` still holds Claudy keys for the removed features; prune when each one is decided.

## Next
- Heeler: refine the pixel map from the owner's dog photo (colours and markings come via the project thread).
- Accessories (skins) are hidden: they are anchored to Clawd's head. Give each pet file a head anchor, then show them again.
- Pets face one way: Clawd's turn and look poses are not drawn yet; a mirrored walk would read better.
- App icon (`Resources/AppIcon.icns`), README pictures.
- Decide how often to start `codex app-server` (now once a minute, a fresh process each time) or keep one running.
- Show credits / reset-credit counts the app-server returns (`credits`, `rateLimitResetCredits`).
- Codex sessions list (from `session_index.jsonl` or the app-server's thread APIs), then projects from the rollout files.
- Release script, Homebrew cask.
