Last update: 2026-11-12. Read `CLAUDE.md` first, then this file.

## Current task

**T-013: Back from a selected search result does not return to the sidebar.** Fix is in PR #43 (branch `fix/T-013-search-back`). Cause (from reading the code, not reproduced): Search is hidden in the menu by default, so the sidebar had no entry carrying the `sideFocus` requester and the Back handler failed silently. Fix in `Sidebar.kt` (`anchorId`). CI result and device test: PENDING. Test steps are in `docs/tasks/T-013-search-back-navigation.md`.

## Completed steps (12 Nov 2026)

- U-1 (Media3 code out of `PlayerLogic.kt`): merged through PR #30 (`02bebe8`).
- Wishbox round 1, T-007 performance and the follow-up commits (tappable search box, error box vs TV guide, running show in guide search, Live TV opens on "Start", empty-playlist hints): merged through PR #41 (merge commit `f535c3e`). Device test by the maintainer: all confirmed. Not explicitly tested: playlist after an app restart, search with the system keyboard (setting off by default).
- PR #42: task file T-013, merged.
- Hint texts are English on purpose (maintainer request) and not in the dictionaries. `LiveMemory.sel` is still written but no longer read.

## Open problems

- PR #40 (`integration/2026-11-11`, fork `browanoncoder/IPVIO-Stream`) has conflicts with `main` (also with PR #41). A comment on the PR asks the author to update the branch. Alternative if that does not happen: pull the branch into this repo and resolve the conflicts there (about 65 files).
- Branch `fix/round28-major` (T-010 to T-012) is not in `main` and not in PR #40.
- Branch `perf/T-007` on GitHub: T-008 Xtream loading indicator, device test status unknown.
- T-009 backup servers: device test still pending.
- T-004 (quality baseline values), T-006 (backup `NAMES`, `Backup.kt:17`) and CHANGELOG entries for 1.2 and 1.3 remain open.

## Next step

Check CI on PR #43, device-test T-013, then merge. After that: PR #40 (conflicts), then T-006.
