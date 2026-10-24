# Roadmap

Where Codexy is going. It is a small project made in the open: the list is short on purpose. What is already done is in the [CHANGELOG](CHANGELOG.md); what was checked with real use, and what was not, is in [docs/STATUS.md](docs/STATUS.md).

**Now** — the app works and has a release ([0.2.2](https://github.com/juliobianco/codexy/releases/tag/v0.2.2)): the 5-hour and weekly limits, the exact state of each session, usage by project and model, a tokens-per-day window, OpenAI status, the floating widget, four mascots, settings in English and Portuguese.

## Usage dashboard: execution order

Priority proposed on 2026-10-23 after comparing the panel with Claudy. The charts, project/model shares, heatmap and tokens window already exist; this work validates them and makes them easier to find. Item 1 has a [partial local audit](docs/USAGE-VALIDATION.md); its coverage/calibration checks and items 5–6 remain pending. Items 2–4 are included in 0.2.2 and validated with tests and English/Portuguese previews. Start here before the remaining cosmetic work; no release dates are committed.

1. [ ] **Validate the existing dashboard with real data.** **Partial: arithmetic/rendering checked on 2026-10-23; client coverage and quota calibration remain open.** Check 24 hours / 7 days, turns and sessions, projects, models, heatmap and tokens. Compare a small known sample with the local records; check CLI, VS Code and desktop session coverage separately. Done when results and gaps are recorded in `docs/STATUS.md`, including the estimated nature of project/model shares.
2. [x] **Make Details easy to discover.** A labelled Details row below status replaces the header's small arrow and respects the “Usage details” setting. The first-launch default remains collapsed; existing saved choices are preserved. Done when a new user can find the charts without instructions, in English and Portuguese.
3. [x] **Explain missing or partial data.** Distinguish loading, no use in the period, an unavailable data source and quota history that has only just started accumulating. Done when the panel explains each case without presenting missing data as zero use or inventing past limit samples.
4. [x] **Put tokens alongside the other usage views.** Add a direct “Tokens per day…” entry in Details, reusing the existing window. Keep the 24-hour / 7-day Details periods and the 7-day / 30-day tokens periods clearly labelled. Done when the user can open tokens from Details and see input, output, cached totals and the local-data scope.
5. [ ] **Investigate skills, plugins and MCP data sources.** Determine what supported Codex interfaces or local metadata expose, with anonymised examples. Separate installed, enabled/configured and actually used; record coverage, precedence and limitations. Done when there is a documented source for each supported field and a concrete minimum scope for item 6. Configuration inspection must not expose credentials or conversation content.
6. [ ] **Build the supported read-only skills/plugins/MCP section.** Depends on item 5. Show only fields backed by verified sources; label inventory separately from measured use and explain unavailable data. Done when English/Portuguese copy, source-failure behaviour and checks for the new reader pass. Do not promise Claudy's usage profile where equivalent data has not been established.

Items 1–4 improve features already present. Items 5–6 are new work and depend on the data investigation; they are separate from the general `config.toml` viewer below.

## Next

Other planned work, after the dashboard priorities above. Small, clear, and good for a first contribution.

- **Check it with real use** — what only a person at the keyboard can see: *waiting for you* with approvals on (`codex -a on-request`), reset credits and paid credits with a real value, extra limits on a plan that has them, the project weights against how far the 5-hour bar moved, and the Codex desktop app (whether its threads show).
- **A `~/.codex/config.toml` view** — read-only first; any write only after a click, keeping comments and order.
- **Side poses for Bit, Coruja and Livrinho** — they walk facing forward; Theo has `[walk1] [walk2] [sit]`. A pet is a text file, see [the guide](docs/CREATING-ART.md).
- **Accessories** — hats and glasses for the new heads (a head anchor per pet file), then show the picker again.
- **More languages** — adding one is one table of text. Spanish, French.
- **Manual validation on other Macs** — macOS 14 and 15 (no Liquid Glass), Intel, a second display.

## Later

Bigger, or waiting for something.

- **A notarized download** — needs an Apple Developer ID; until then the zip asks for "Open Anyway".
- **A check for new versions of Codexy itself** — notify and open the release page; never download and run code.
- **A global hotkey** to show and hide the floating widget.
- **Accessibility** — VoiceOver labels for the card, the bubble and the settings, and a "reduce motion" switch for the mascot.
- **Claudex** — Claude and Codex in one app. Wait until both readers have settled, then decide between one app with two providers or a shared core package.

## Not planned

A self-update that downloads and runs code, and a lookup of your location by IP address. The reasons are in the README's [Privacy](README.md#privacy-and-security) section.

## How to help

Pick anything above, open an issue to say so, and read [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports with the log (**Settings → System → Open log**, with names removed) are the most useful thing there is.
