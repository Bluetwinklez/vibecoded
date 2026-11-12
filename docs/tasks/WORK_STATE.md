Last update: 2026-11-12. Read `CLAUDE.md` first, then this file.

## Current task

**Wishbox round 1 and T-007 performance** on branch `feat/wishbox-perf-runde1`, draft pull request #41 against `main`. The branch holds commit `0f3b073`, a cherry-pick of the local WIP commit `12da745` onto `origin/main`. The CI build on that commit succeeded.

Device test by the maintainer (debug build, app ID `.test`):

- Live TV: recently watched channels row. OK
- Live TV: scroll the channel list and change category. OK
- Playlist content mode (live or VOD). OK
- Hide a category. OK
- Playlist loads after an app restart. Not explicitly confirmed.
- Search with the system keyboard. Not tested (setting `systemKeyboard` is off by default).

## Small follow-ups on the same branch (12 Nov 2026, after the device test)

Commits on top of `0f3b073`: `820ff95`, `73a3dbc`, `f1025e1`, `e0f4303`, `c64910f`, `de98f37`. CI is green on each. The maintainer confirmed on the device that they work ("all done"); no per-item test log beyond that.

- `SearchScreen.kt`: with the app keyboard on, the query box is a `Field` (OK or tap opens the device keyboard). `BackHandler` untouched (T-013).
- `PlayerScreen.kt` (protected area, one condition): playback error box is hidden while the TV guide is open.
- `GuideSearch.kt`: channel hits show the running show (XMLTV, otherwise `Epg.now` for rows on screen).
- `LiveTab.kt`: tab always opens on "HOME"; hint about the playlist content mode when there are no live channels. `LiveMemory.sel` is still written but no longer read.
- `HomeScreen.kt`: same hint on movies, series and home when the playlist has none.
- The hint texts are English on purpose (maintainer request) and not in the dictionaries; the system keyboard setting (`systemKeyboard`) is off by default.

## Completed steps

- U-1 (move Media3 code out of `PlayerLogic.kt`) is merged into `main` through PR #30 (merge commit `02bebe8`, 12 Nov 2026).
- Wishbox round 1 and T-007 performance were committed locally as `12da745` (marked untested).
- The commit is pushed as the backup branch `backup/wishbox-runde1-12da745`.
- The commit is cherry-picked onto `feat/wishbox-perf-runde1` (`0f3b073`) and opened as draft PR #41.

## Open problems

- Search: going back from a selected title in the result list does not return to the sidebar. The back logic in `SearchScreen.kt` is identical on `main`, so the bug predates this work. To be tracked as T-013, created on a branch from `main`.
- Search: with the app keyboard on, the query box was display-only. Fixed in this branch: the box is now a `Field` (OK or tap opens the device keyboard). Not yet tested on a device. The system keyboard is a setting (Settings, keyboard of the device in search) and is **off by default**.
- PR #40 (`integration/2026-11-11`) is open and not merged. It overlaps PR #41 in `LiveTab.kt` and `SearchScreen.kt`. Merge order is undecided.
- Branch `fix/round28-major` (T-010 to T-012) is not in `main` and not in PR #40.
- Branch `perf/T-007` on GitHub: T-008 Xtream loading indicator, device test status unknown.
- T-009 backup servers: device test still pending.
- T-004 (quality baseline values), T-006 (backup `NAMES`, `Backup.kt:17`) and CHANGELOG entries for 1.2 and 1.3 remain open.

## Next step

Decide the merge order of PR #40 and PR #41. Confirm the open device checks (playlist after restart, search with the system keyboard), then mark PR #41 ready for review. Create T-013 from `main`.
