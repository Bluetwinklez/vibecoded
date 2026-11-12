Last update: 2026-11-12. Read `CLAUDE.md` first, then this file.

## Current task

No task in progress. Next candidates: T-006 (backup `NAMES`), CHANGELOG entries for 1.2 and 1.3, PR #40 (see open problems).

## Completed steps (12 Nov 2026)

- U-1 (Media3 code out of `PlayerLogic.kt`): merged through PR #30 (`02bebe8`).
- Wishbox round 1, T-007 performance and the follow-up commits (tappable search box, error box vs TV guide, running show in guide search, Live TV opens on "Start", empty-playlist hints): merged through PR #41 (merge commit `f535c3e`). Device test by the maintainer: all confirmed. Not explicitly tested: playlist after an app restart, search with the system keyboard (setting off by default).
- PR #42: task file T-013, merged.
- T-013 (Back in the search: from a hit to the input/keyboard, from there to the sidebar; also works with Search hidden in the menu): merged through PR #43 (`cfa223b`). Device test by the maintainer on 12 Nov 2026: works.
- Hint texts are English on purpose (maintainer request) and not in the dictionaries. `LiveMemory.sel` is still written but no longer read.

## Open problems

- PR #40 (`integration/2026-11-11`, fork `browanoncoder/IPVIO-Stream`) has conflicts with `main`. A comment asks the author to update the branch. Maybe it also contains PR #9 (subtitle search, still open).
- PR #47 (Stalker: on-demand loading, playback port, review fixes) is merged. CI green, **no device test** (no real Stalker portal). Closed in favour of it: #7, #19 (Stalker part only; its other topics were not taken over), #36, #38, #39.
- Closed without merging (conflicts with `main` after #41, areas were reworked in T-007): #8 (Fire TV Live TV stalls), #13 (content mode; `main` has its own `PlaylistMode`), #14 (search ANR), their follow-ups #32, #33, #34, and #31 (obsolete). Reopen if the problems still show on `main`.
- Branch `fix/round28-major` (T-010 to T-012) and branch `perf/T-007` (T-007 UI rendering, T-008 Xtream loading indicator) are 28 commits behind `main` and in no pull request.
- T-009 backup servers: device test still pending. T-006 (backup `NAMES`): device check of export and restore pending.
- `ipvio_plmode` (content mode per playlist address) is not in the backup; undecided.
- T-004 (quality baseline values) needs ktlint, detekt and Lint runs on the maintainer's machine.

## Next step

Update `fix/round28-major` and `perf/T-007` onto `main` (conflicts expected in the files PR #41 changed) and open one PR each. Then PR #40 / PR #9.
