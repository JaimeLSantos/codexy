# Roadmap

Where Codexy is going. It is a small project made in the open: the list is short on purpose. What is already done is in the [CHANGELOG](CHANGELOG.md); what was checked with real use, and what was not, is in [docs/STATUS.md](docs/STATUS.md).

**Now** — the app works and has a release ([0.2.0](https://github.com/juliobianco/codexy/releases/tag/v0.2.0)): the 5-hour and weekly limits, the exact state of each session, usage by project and model, a tokens-per-day window, OpenAI status, the floating widget, four mascots, settings in English and Portuguese.

## Next

Small, clear, and good for a first contribution.

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
