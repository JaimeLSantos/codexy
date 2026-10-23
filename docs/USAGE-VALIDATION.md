# Usage dashboard validation

Local audit: 2026-10-23, commit `f840fa8`. Dashboard checklist item 1 is **partially validated**: arithmetic and rendering passed the checks below; client coverage and quota-weight accuracy still have gaps. No production code was changed in this audit.

## Checks performed

- Built and tested with `--scratch-path "$HOME/Library/Caches/codexy-build"`, outside Documents.
- Enumerated 103 rollout files modified within 30 days, including 81 `.jsonl.zst` files. Only session metadata, turn context and token-count events were used; no conversation text, credentials or account identifiers were exported.
- Took a frozen, anonymised sample of four recent non-fork sessions. An independent Python count and the Swift `RolloutScanner` agreed on **11 turns, 4 sessions, 7,598,812 input tokens (including 7,111,296 cached) and 33,733 output tokens**. Estimated weight agreed within floating-point tolerance: 1,468,509.6. A second scan of that frozen sample returned the same result.
- Scanned the real 7-day and 30-day corpus. Project shares summed to 100% before rounding; token values were non-negative, cached input did not exceed input, and token-day bars summed to the per-model totals for both 7 and 30 local calendar days. The heatmap had 7 rows and 24 columns.
- Rendered Details at 24 hours and 7 days, with the heatmap expanded, and Tokens at 7 and 30 days. Project labels were anonymised before rendering. Inspected the four PNGs: charts, counters, project/model rows, heatmap and token totals rendered without clipping. Temporary rendering hooks were removed afterwards; the real app's history and preferences were not modified by the diagnostic renderer.
- Read limits successfully from `appServer`. The saved history had 333 ordered samples spanning about 44 hours, valid percentage values, and four gaps longer than 20 minutes. Counts reflect a moving live dataset, not a fixed test fixture.
- The 30-day cold scan took about 10 seconds on this Mac. A loading state during that scan is expected.

Observed aggregate counts during the audit (not an independent recount of every file):

| View/filter | Turns | Sessions | Projects |
| --- | ---: | ---: | ---: |
| 24 hours | 12 | 6 | 3 |
| 7 days | 28 | 12 | 6 |
| 30-day scan used by Tokens | 401 | 55 | 10 |

Cached input is already part of input; it must not be added again. Output already includes reasoning. Project/model shares are estimated weights, not raw token shares or a measured share of the plan quota.

## Time ranges that look similar but differ

- Details counters and project/model shares use the rolling period, with an hourly cutoff. The 24-hour boundary can therefore include part of the preceding hour.
- The day limits chart shows up to 24 hours, with a minimum six-hour axis when history is young.
- The weekly limits chart shows the **current quota cycle**, from the previous reset to the next reset. During this audit it had just restarted, so the line occupied only the beginning of the axis. This was not a rendering failure.
- Heatmap rows and Tokens bars use local calendar days. The heatmap remains a seven-day overview in both Details modes.
- Limits history is recorded while Codexy runs. Rollout files supply activity/token history; this audit did not attempt to reconstruct earlier quota samples from them.

## Coverage and checks still open

- **TUI:** a visible `codex-tui` thread was detected. The daemon answered; the session list contained two visible threads, with one busy and none waiting at that instant. This does not validate approval/waiting transitions.
- **VS Code extension:** not independently exercised live. A `source: "vscode"` header alone is insufficient proof: the corpus also uses that source for other origins, including the TUI.
- **Desktop:** historical metadata includes `Codex Desktop` and `codex_work_desktop`, so their records are available to the historical scanner. No visible live thread with either origin was returned during this audit. `Codex.app` was absent at the standard system/user Applications paths; that check does not prove the app is absent elsewhere. Live desktop discovery remains unverified.
- **Historical thread semantics:** the corpus contains internal jobs and auto-review models. The historical scanner counts threads with accepted turn/token events, while the live list explicitly hides internal jobs. Do not equate the historical session counter with the number of user windows or files.
- **Forks and rewrites:** the independent live-data sample deliberately used non-fork, monotonic totals. Existing automated fixtures cover forks, repeated counts and compressed files; this audit is not an independent verification of every fork in the real corpus.
- **Quota accuracy:** compare a controlled work interval with movement of the 5-hour quota before treating project/model weights as calibrated. Passing arithmetic checks does not establish the model factors.

Next action: make Details easier to discover (roadmap item 2), while retaining the client-coverage and quota-calibration checks above as pending work. Loading/partial-history explanations belong to item 3.

Local diagnostic artifacts are under `~/Library/Caches/codexy-validation/` (`report.json`, anonymised sample/reference counts and the four PNGs). They are not committed. The report contains aggregate technical data; snapshots contain no account footer or real project names.
