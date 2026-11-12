Last update: 2026-11-12 (T-015). Read `CLAUDE.md` first, then this file.

## Current task

T-015 (harden the in-app update: `update.json` as primary source, SHA-256, package/version/signer check, clear error texts): implemented on branch `feat/T-015-harden-update`, waiting for CI and the device test. Task file: `docs/tasks/T-015-harden-update.md`. Changed files: `Round17Logic.kt` (`UpdateLogic`), `AppUpdate.kt`, `UpdateVerify.kt` (new), `UpdatePrompt.kt`, `DictK.kt` (10 rows), `UpdateLogicTest.kt` (new), `docs/RELEASE.md`, `docs/SECURITY.md`, `CHANGELOG.md`. Checks that ran: `UpdateLogicTest` 15/15 (with a stand-in for `org.json`, the real jar was not available) and `DictConsistencyTest` 3/3 on the JVM. **Not run:** Gradle build, device test, the signature check on API below 28. Before the next release: create `update.json` as described in `docs/RELEASE.md`.

T-014 (first-start update check card) is merged (PR #57, #58); its device test is still pending.

## Completed steps (12 Nov 2026)

- U-1 (Media3 code out of `PlayerLogic.kt`): merged through PR #30 (`02bebe8`).
- Wishbox round 1, T-007 performance and the follow-up commits (tappable search box, error box vs TV guide, running show in guide search, Live TV opens on "Start", empty-playlist hints): merged through PR #41 (merge commit `f535c3e`). Device test by the maintainer: all confirmed. Not explicitly tested: playlist after an app restart, search with the system keyboard (setting off by default).
- PR #42: task file T-013, merged.
- T-013 (Back in the search: from a hit to the input/keyboard, from there to the sidebar; also works with Search hidden in the menu): merged through PR #43 (`cfa223b`). Device test by the maintainer on 12 Nov 2026: works.
- Hint texts are English on purpose (maintainer request) and not in the dictionaries. `LiveMemory.sel` is still written but no longer read.

## Open problems

- PR #40 (`integration/2026-11-11`, fork `browanoncoder/IPVIO-Stream`, 32 commits, 66 files) still has 10 conflicting files with `main` (CategoriesScreen, HomeScreen, LiveGenre, LiveTab, Models, PlaylistStore, SearchLogic, SearchScreen, CHANGELOG, WORK_STATE). Much of it is already in `main` in another form (Stalker #7, subtitle search #9). A comment asks the author to update the branch. Unique parts that are not in `main`: Live TV focus fixes, MKV seeking (#10), tap-to-seek (#25), Recently added (#22), translations. If the author does not react, port those parts one by one.
- PR #47 (Stalker: on-demand loading, playback port, review fixes) is merged. CI green, **no device test** (no real Stalker portal). Closed in favour of it: #7, #19 (Stalker part only; its other topics were not taken over), #36, #38, #39.
- Closed without merging (conflicts with `main` after #41, areas were reworked in T-007): #8 (Fire TV Live TV stalls), #13 (content mode; `main` has its own `PlaylistMode`), #14 (search ANR), their follow-ups #32, #33, #34, and #31 (obsolete). Reopen if the problems still show on `main`.
- Old branches `fix/round28-major` and `perf/T-007` were sorted out: ported and merged were T-011 (category order), T-009 (refresh default, task file `T-009-refresh-default.md`; the ID T-009 is used twice) through PR #49 and T-008 (Xtream loading progress) through PR #50. CI is green on the merged `main`, no device test yet. **Not ported:** T-010 (load all Stalker movies) and T-012 (EPG name matching, Stalker guide) because they conflict with the on-demand loading of PR #47; the T-007 UI rendering commit and ADR 0004 because PR #41 already covers the same files. The two branches stay on GitHub for reference.
- T-009 backup servers: device test still pending. T-006 (backup `NAMES`): device check of export and restore pending.
- `ipvio_plmode` (content mode per playlist address) is not in the backup; undecided.
- T-004 (quality baseline values) needs ktlint, detekt and Lint runs on the maintainer's machine.

## Next step

Device tests of T-015 (steps in its task file; needs a test release with `update.json`) and of T-014 (steps in the task report: fresh install, offline, older APK). Device tests of everything merged on 12 Nov 2026 (#41, #43, #45, #47 Stalker, #49 category order and refresh default, #50 Xtream progress, #52 online subtitle search from #9). Then decide T-010 and T-012 against the on-demand loading, and PR #40 / PR #9.
